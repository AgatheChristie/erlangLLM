%%%-------------------------------------------------------------------
%% @doc OpenAI API 客户端 — 上层调用接口
%%
%% 架构:
%%   openai_test = 上层便捷接口 + 测试函数
%%   openai_send = 请求构建 + HTTP 发送 + 重试 + 响应提取
%%
%% 在 shell 中测试:
%%   1> openai_test:test_chat().
%%   2> openai_test:test_system().
%%   3> openai_test:test_json().
%%   4> openai_test:test_chat_multi().
%%   5> openai_test:test_embedding().
%%   6> openai_test:test_embedding_batch().
%%   7> openai_test:test_embedding_similarity().
%% @end
%%%-------------------------------------------------------------------

-module(openai_test).
-include("ai_tou.hrl").
-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% OpenAI Chat Completions API — 便捷接口
%%====================================================================
%% 文档: https://platform.openai.com/docs/api-reference/chat
%%
%% 调用示例:
%%   openai_test:chat(<<("你好，请介绍一下自己")/utf8>>).
%%   openai_test:chat(<<"写首诗"/utf8>>, <<"你是唐代诗人"/utf8>>).
%%   openai_test:chat_json(<<"列出3种水果及颜色"/utf8>>, Schema).

%% @doc 简单文本对话 (便捷接口)
%% 示例: openai_test:chat(<<("惠州这一周的天气怎么样")/utf8>>).
chat(Text) when is_binary(Text) ->
    openai_send:generate_content(#{?OPT_PROMPT => Text}).

%% @doc 带 System Instruction 的文本对话
%% 示例: openai_test:chat(<<"写一首诗"/utf8>>, <<"你是一位唐代诗人"/utf8>>).
chat(Text, SystemInstruction) when is_binary(Text), is_binary(SystemInstruction) ->
    openai_send:generate_content(#{
        ?OPT_PROMPT => Text,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).

%% @doc 多轮对话
%% 注意: OpenAI 的角色是 user 和 assistant
%% 示例:
%%   Messages = [
%%     {user, <<"你好">>},
%%     {assistant, <<"你好！有什么可以帮你的？">>},
%%     {user, <<"今天天气怎么样？">>}
%%   ],
%%   openai_test:chat_multi(Messages).
chat_multi(Messages) when is_list(Messages) ->
    openai_send:generate_content(#{?OPT_MESSAGES => Messages}).

%% @doc 多轮对话 + System Instruction
chat_multi(Messages, SystemInstruction) when is_list(Messages), is_binary(SystemInstruction) ->
    openai_send:generate_content(#{
        ?OPT_MESSAGES => Messages,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).

%% @doc JSON 结构化输出 (Structured Outputs)
%% Schema 使用标准 JSON Schema 格式（小写 type），例如:
%%   Schema = #{
%%     <<"type">> => <<"object">>,
%%     <<"properties">> => #{
%%       <<"name">>  => #{<<"type">> => <<"string">>}
%%     },
%%     <<"required">> => [<<"name">>],
%%     <<"additionalProperties">> => false
%%   }
%% 示例: openai_test:chat_json(<<"列出3种水果及颜色"/utf8>>, Schema).
chat_json(Text, Schema) when is_binary(Text), is_map(Schema) ->
    openai_send:generate_content(#{
        ?OPT_PROMPT => Text,
        ?OPT_RESPONSE_FORMAT => openai_send:build_response_format(Schema)
    }).

%% @doc JSON 结构化输出 + System Instruction
%% 示例: openai_test:chat_json(<<"列出3种水果"/utf8>>, Schema, <<"你是植物学家"/utf8>>).
chat_json(Text, Schema, SystemInstruction) when is_binary(Text), is_map(Schema), is_binary(SystemInstruction) ->
    openai_send:generate_content(#{
        ?OPT_PROMPT => Text,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction,
        ?OPT_RESPONSE_FORMAT => openai_send:build_response_format(Schema)
    }).

%%====================================================================
%% 测试函数
%%====================================================================

%% @doc 测试1: 基础文本对话
%% 示例: openai_test:test_chat().
test_chat() ->
    chat(<<("你好，请用一句话介绍一下你自己")/utf8>>).

%% @doc 测试2: 带 System Instruction 的对话
%% 示例: openai_test:test_system().
test_system() ->
    chat(
        <<("写一首关于月亮的诗")/utf8>>,
        <<("你是一位唐代诗人，擅长七言绝句")/utf8>>
    ).

%% @doc 测试3: 多轮对话
%% 示例: openai_test:test_chat_multi().
test_chat_multi() ->
    Messages = [
        {user, <<("你好")/utf8>>},
        {assistant, <<("你好！有什么可以帮你的？")/utf8>>},
        {user, <<("今天天气怎么样？")/utf8>>}
    ],
    chat_multi(Messages).

%% @doc 测试4: JSON 结构化输出
%% 示例: openai_test:test_json().
test_json() ->
    Schema = test_fruit_schema(),
    chat_json(<<("列出3种水果及其颜色")/utf8>>, Schema).

%% @doc 测试5: JSON 结构化输出 + System Instruction
%% 示例: openai_test:test_json_system().
test_json_system() ->
    Schema = test_fruit_schema(),
    chat_json(
        <<("列出3种热带水果及其颜色")/utf8>>,
        Schema,
        <<("你是一位植物学家，回答要专业准确")/utf8>>
    ).

%% 测试用的水果 Schema (OpenAI JSON Schema 格式)
%% 类型用小写: <<"object">>, <<"array">>, <<"string">>
%% 必须包含 required 和 additionalProperties: false
test_fruit_schema() ->
    #{
        <<"type">> => <<"object">>,
        <<"properties">> => #{
            <<"fruits">> => #{
                <<"type">> => <<"array">>,
                <<"items">> => #{
                    <<"type">> => <<"object">>,
                    <<"properties">> => #{
                        <<"name">> => #{<<"type">> => <<"string">>},
                        <<"color">> => #{<<"type">> => <<"string">>}
                    },
                    <<"required">> => [<<"name">>, <<"color">>],
                    <<"additionalProperties">> => false
                }
            }
        },
        <<"required">> => [<<"fruits">>],
        <<"additionalProperties">> => false
    }.

%%====================================================================
%% Embeddings 便捷入口 (委托到 openai_embeddings)
%%====================================================================
%% 实现: openai_embeddings.erl
%% 文档: https://platform.openai.com/docs/api-reference/embeddings
%%
%% 调用示例:
%%   openai_embeddings:embeddings(<<"Hello world">>).
%%   openai_embeddings:embeddings([<<"文本1"/utf8>>, <<"文本2"/utf8>>]).
%%   openai_embeddings:embeddings(<<"Hello">>, #{dimensions => 256}).

embedding(Input) ->
    openai_embeddings:embeddings(Input).

embedding(Input, Opts) ->
    openai_embeddings:embeddings(Input, Opts).

embedding_vectors(Input) ->
    openai_embeddings:embedding_vectors(Input).

embedding_vectors(Input, Opts) ->
    openai_embeddings:embedding_vectors(Input, Opts).

%%====================================================================
%% Embeddings 测试函数
%%====================================================================

%% @doc 测试6: Embedding 基本调用
%% 示例: openai_test:test_embedding().
test_embedding() ->
    case embedding(<<"OpenAI embeddings convert text into numerical vectors">>,#{dimensions => 256}) of
        {ok, #{<<"data">> := [#{<<"embedding">> := Vec} | _]} = Resp} ->
            io:format("维度: ~p, 前5个值: ~p~n", [length(Vec), lists:sublist(Vec, 5)]),
            io:format("模型: ~ts~n", [maps:get(<<"model">>, Resp, <<"?">>)]),
            io:format("Token: ~p~n", [maps:get(<<"usage">>, Resp, #{})]),
            {ok, Resp};
        Other ->
            Other
    end.

%% @doc 测试7: 批量 Embedding
%% 示例: openai_test:test_embedding_batch().
test_embedding_batch() ->
    Texts = [
        <<("猫")/utf8>>,
        <<("狗")/utf8>>,
        <<("鸟")/utf8>>
    ],
    case embedding(Texts) of
        {ok, #{<<"data">> := DataList} = Resp} ->
            lists:foreach(fun(#{<<"index">> := Idx, <<"embedding">> := Vec}) ->
                io:format("第~p个: 维度=~p, 前3值=~p~n",
                    [Idx, length(Vec), lists:sublist(Vec, 3)])
                          end, DataList),
            {ok, Resp};
        Other ->
            Other
    end.

%% @doc 测试8: Embedding 语义相似度对比
%%
%% 预期结果: "猫 vs 狗" 相似度 > "猫 vs 苹果" 和 "狗 vs 苹果"
%% 因为猫和狗都是动物, 语义更接近
%%
%% 示例: openai_test:test_embedding_similarity().
test_embedding_similarity() ->
    Texts = [
        <<("猫是可爱的动物")/utf8>>,
        <<("狗是忠诚的伙伴")/utf8>>,
        <<("苹果是一种水果")/utf8>>
    ],
    case embedding_vectors(Texts, #{dimensions => 256}) of
        {ok, [V1, V2, V3]} ->
            Sim12 = openai_embeddings:cosine_similarity(V1, V2),
            Sim13 = openai_embeddings:cosine_similarity(V1, V3),
            Sim23 = openai_embeddings:cosine_similarity(V2, V3),
            io:format("~ts vs ~ts: ~.4f~n", [<<"猫"/utf8>>, <<"狗"/utf8>>, Sim12]),
            io:format("~ts vs ~ts: ~.4f~n", [<<"猫"/utf8>>, <<"苹果"/utf8>>, Sim13]),
            io:format("~ts vs ~ts: ~.4f~n", [<<"狗"/utf8>>, <<"苹果"/utf8>>, Sim23]),
            #{cat_dog => Sim12, cat_apple => Sim13, dog_apple => Sim23};
        Other ->
            Other
    end.

%% @doc 测试9: 降维 Embedding (256 维, 节省存储)
%% 示例: openai_test:test_embedding_256d().
test_embedding_256d() ->
    case embedding(<<"Hello world">>, #{dimensions => 256}) of
        {ok, #{<<"data">> := [#{<<"embedding">> := Vec} | _]}} ->
            io:format("降维后维度: ~p (原始 1536)~n", [length(Vec)]),
            {ok, length(Vec)};
        Other ->
            Other
    end.
