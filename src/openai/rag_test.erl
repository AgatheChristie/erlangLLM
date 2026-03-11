%%%-------------------------------------------------------------------
%%% @doc RAG 检索增强生成 — 完整测试案例
%%%
%%% 流程: OpenAI Embedding 生成向量 → PostgreSQL pgvector 存储 → 相似搜索 → ChatGPT 回答
%%%
%%% 快速体验:
%%%   1> rag_test:init().               %% 建表
%%%   2> rag_test:load_knowledge().      %% 入库知识（调用 OpenAI + 存入 PG）
%%%   3> rag_test:ask(<<"什么动物最忠诚"/utf8>>).  %% 提问
%%%   4> rag_test:demo().               %% 一键运行全部
%%% @end
%%%-------------------------------------------------------------------
-module(rag_test).
-include("common.hrl").
-include("ai_tou.hrl").
-compile(export_all).
-compile(nowarn_export_all).

-define(PG_USER, "postgres").
-define(PG_PASS, "123456").
-define(PG_DB,   "qifei").
-define(EMBED_DIM, 256).

%%====================================================================
%% 数据库连接
%%====================================================================

get_conn() ->
    {ok, C} = epgsql:connect(#{
        host => "localhost",
        username => ?PG_USER,
        password => ?PG_PASS,
        database => ?PG_DB,
        timeout => 4000
    }),
    C.

%%====================================================================
%% 第一步：初始化 — 创建 pgvector 扩展和知识库表
%%====================================================================

%% rag_test:init().
init() ->
    C = get_conn(),
    epgsql:squery(C, "CREATE EXTENSION IF NOT EXISTS vector"),
    epgsql:squery(C, "DROP TABLE IF EXISTS knowledge"),
    {ok, _, _} = epgsql:squery(C,
        "CREATE TABLE knowledge ("
        "  id SERIAL PRIMARY KEY,"
        "  content TEXT NOT NULL,"
        "  embedding vector(" ++ integer_to_list(?EMBED_DIM) ++ ")"
        ")"),
    epgsql:squery(C,
        "CREATE INDEX IF NOT EXISTS knowledge_embedding_idx "
        "ON knowledge USING ivfflat (embedding vector_cosine_ops) WITH (lists = 1)"),
    ?INFO("[RAG] knowledge table created (dim=~p)", [?EMBED_DIM]),
    ok = epgsql:close(C).

%%====================================================================
%% 第二步：入库知识 — OpenAI 生成向量 + 存入 PostgreSQL
%%====================================================================

knowledge_data() ->
    [
        <<"猫是一种独立而优雅的宠物，擅长捕鼠，喜欢独处"/utf8>>,
        <<"狗是人类最忠诚的伙伴，善于看家护院，喜欢与主人互动"/utf8>>,
        <<"金鱼是常见的观赏鱼，养在鱼缸里，寿命可达10年"/utf8>>,
        <<"苹果富含维生素C和膳食纤维，是最受欢迎的水果之一"/utf8>>,
        <<"香蕉含有丰富的钾元素，适合运动后补充能量"/utf8>>,
        <<"西瓜是夏天最受欢迎的水果，水分含量高达90%以上"/utf8>>,
        <<"Erlang是一门函数式编程语言，擅长并发和分布式系统"/utf8>>,
        <<"PostgreSQL是功能最强大的开源关系数据库，支持向量搜索"/utf8>>,
        <<"太阳系有八大行星，地球是唯一已知存在生命的行星"/utf8>>,
        <<"长城是中国古代的伟大建筑，全长超过两万公里"/utf8>>
    ].

%% rag_test:load_knowledge().
load_knowledge() ->
    Texts = knowledge_data(),
    ?INFO("[RAG] generating embeddings for ~p texts...", [length(Texts)]),

    case openai_test:embedding_vectors(Texts, #{dimensions => ?EMBED_DIM}) of
        {ok, Vectors} ->
            C = get_conn(),
            epgsql:squery(C, "DELETE FROM knowledge"),
            lists:foreach(fun({Text, Vec}) ->
                VecStr = vec_to_pgstr(Vec),
                epgsql:equery(C,
                    "INSERT INTO knowledge (content, embedding) VALUES ($1, $2::vector)",
                    [Text, VecStr])
            end, lists:zip(Texts, Vectors)),
            ok = epgsql:close(C),
            ?INFO("[RAG] ~p knowledge entries stored", [length(Texts)]),
            ok;
        {error, Reason} ->
            ?INFO("[RAG] embedding failed: ~p", [Reason]),
            {error, Reason}
    end.

%%====================================================================
%% 第三步：语义搜索 — 用户问题转向量 → pgvector 找最相似
%%====================================================================

%% rag_test:search(<<"什么动物最忠诚"/utf8>>).
search(Question) ->
    search(Question, 3).

search(Question, TopK) ->
    case openai_test:embedding_vectors(Question, #{dimensions => ?EMBED_DIM}) of
        {ok, [QueryVec]} ->
            C = get_conn(),
            VecStr = vec_to_pgstr(QueryVec),
            {ok, _Cols, Rows} = epgsql:equery(C,
                "SELECT content, 1 - (embedding <=> $1::vector) AS similarity "
                "FROM knowledge "
                "ORDER BY embedding <=> $1::vector "
                "LIMIT $2",
                [VecStr, TopK]),
            ok = epgsql:close(C),
            Results = [{Content, Sim} || {Content, Sim} <- Rows],
            ?INFO("[RAG] search '~ts' top ~p results:", [Question, TopK]),
            lists:foreach(fun({Content, Sim}) ->
                ?INFO("  [~.4f] ~ts", [Sim, Content])
            end, Results),
            {ok, Results};
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% 第四步：完整 RAG — 搜索相关知识 + 交给 ChatGPT 回答
%%====================================================================

%% rag_test:ask(<<"什么动物最忠诚"/utf8>>).
ask(Question) ->
    case search(Question, 3) of
        {ok, Results} ->
            Context = build_context(Results),
            SystemPrompt = <<"你是一个知识问答助手。请根据以下参考资料回答用户的问题。"
                             "如果参考资料中没有相关信息，请诚实地说不知道。\n\n"
                             "参考资料：\n"/utf8, Context/binary>>,
            ?INFO("[RAG] sending to ChatGPT with ~p context entries", [length(Results)]),
            Answer = openai_test:chat(Question, SystemPrompt),
            ?INFO("[RAG] question: ~ts", [Question]),
            ?INFO("[RAG] answer: ~ts", [Answer]),
            {ok, Answer};
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% 一键 Demo
%%====================================================================

%% rag_test:demo().
demo() ->
    ?INFO("========== RAG Demo Start =========="),
    init(),
    load_knowledge(),
    ?INFO("--- search test ---"),
    search(<<"哪种水果适合运动后吃"/utf8>>),
    search(<<"什么编程语言适合做分布式"/utf8>>),
    ?INFO("--- full RAG test ---"),
    ask(<<"什么动物最忠诚"/utf8>>),
    ?INFO("========== RAG Demo End =========="),
    ok.

%%====================================================================
%% 内部工具函数
%%====================================================================

vec_to_pgstr(Vec) ->
    Parts = lists:join(",", [float_to_list(F, [{decimals, 8}]) || F <- Vec]),
    list_to_binary(["[", Parts, "]"]).

build_context(Results) ->
    Numbered = lists:zip(lists:seq(1, length(Results)), Results),
    Lines = [io_lib:format("~p. ~ts\n", [N, Content]) || {N, {Content, _Sim}} <- Numbered],
    unicode:characters_to_binary(Lines).

%%====================================================================
%% 探测 Embedding API 能力
%%====================================================================

%% rag_test:probe_embedding().
probe_embedding() ->
    TestText = <<"这是一段用于测试Embedding接口的中文文本"/utf8>>,
    ?INFO("===== Embedding API 探测 (text-embedding-3-small) ====="),

    Tests = [
        {<<"原生维度(不传dimensions)">>, #{}},
        {<<"dimensions=256">>,  #{dimensions => 256}},
        {<<"dimensions=512">>,  #{dimensions => 512}},
        {<<"dimensions=1024">>, #{dimensions => 1024}},
        {<<"dimensions=1536">>, #{dimensions => 1536}}
    ],

    lists:foreach(fun({Label, Opts}) ->
        ?INFO("[~ts] 测试中...", [Label]),
        case openai_test:embedding_vectors(TestText, Opts) of
            {ok, [Vec]} ->
                ?INFO("[~ts] OK  维度=~p  前3值=~p", [Label, length(Vec), lists:sublist(Vec, 3)]);
            {error, Reason} ->
                ?INFO("[~ts] FAIL ~p", [Label, Reason])
        end
    end, Tests),

    ?INFO("===== 探测完毕 ====="),
    ok.
