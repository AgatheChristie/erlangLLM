
-module(qianwen_test).
-include("common.hrl").
-include("ai_tou.hrl").
-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% 便捷接口
%%====================================================================
%% qianwen_test:get_models(10).
get_models() ->
    get_models(50).
get_models(Num) ->
    #{api_url := ApiUrl, api_key := ApiKey} = qianwen_send:default_config(),
    Url = <<ApiUrl/binary, "/models">>,
    Headers = [
        {<<"Authorization">>, <<"Bearer ", ApiKey/binary>>},
        {<<"Content-Type">>,  <<"application/json">>}
    ],
    Options = [{connect_timeout, 10000}, {recv_timeout, 30000}],
    case hackney:request(get, Url, Headers, <<>>, Options) of
        {ok, 200, _RespHeaders, ClientRef} ->
            {ok, Body} = hackney:body(ClientRef),
            #{<<"data">> := Models} = jiffy:decode(Body, [return_maps]),
            Sorted = lists:sort(
                fun(A, B) ->
                    maps:get(<<"created">>, A, 0) >= maps:get(<<"created">>, B, 0)
                end,
                Models
            ),
            Top = lists:sublist(Sorted, Num),
            [begin
                Ts = maps:get(<<"created">>, M, 0),
                Id = maps:get(<<"id">>, M, <<>>),

%%                LocalTime = date_utils:seconds_to_datetime(Ts),
                #{<<"id">> => Id, <<"created">> => Ts}
            end || M <- Top];
        {ok, StatusCode, _RespHeaders, ClientRef} ->
            {ok, Body} = hackney:body(ClientRef),
            {error, {http_error, StatusCode, Body}};
        {error, Reason} ->
            {error, Reason}
    end.


%% @doc 简单文本对话
%% 示例: qianwen_test:chat(<<("你好，请介绍一下自己")/utf8>>).
chat(Text) when is_binary(Text) ->
    qianwen_send:generate_content(#{?OPT_PROMPT => Text}).

%% @doc 带 System Instruction 的文本对话
%% 示例: qianwen_test:chat(<<"写一首诗"/utf8>>, <<"你是一位唐代诗人"/utf8>>).
chat(Text, SystemInstruction) when is_binary(Text), is_binary(SystemInstruction) ->
    qianwen_send:generate_content(#{
        ?OPT_PROMPT             => Text,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).

%% @doc 多轮对话
chat_multi(Messages) when is_list(Messages) ->
    qianwen_send:generate_content(#{?OPT_MESSAGES => Messages}).

%% @doc 多轮对话 + System Instruction
chat_multi(Messages, SystemInstruction) when is_list(Messages), is_binary(SystemInstruction) ->
    qianwen_send:generate_content(#{
        ?OPT_MESSAGES           => Messages,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).

%% @doc JSON 结构化输出
chat_json(Text, Schema) when is_binary(Text), is_map(Schema) ->
    qianwen_send:generate_content(#{
        ?OPT_PROMPT          => Text,
        ?OPT_RESPONSE_FORMAT => openai_send:build_response_format(Schema)
    }).

%% @doc 使用 qwen-max 高质量模型
%% 示例: qianwen_test:chat_max(<<"请详细分析这个问题"/utf8>>).
chat_max(Text) when is_binary(Text) ->
    Config = (qianwen_send:default_config())#{model => <<"qwen-max">>},
    qianwen_send:generate_content(#{?OPT_PROMPT => Text}, Config).

%%====================================================================
%% 测试函数
%%====================================================================

%% @doc 测试1: 基础文本对话  qianwen_test:test_chat()
test_chat() ->
    chat(<<("你好，请用一句话介绍一下你自己")/utf8>>).

%% @doc 测试2: 带 System Instruction 的对话 qianwen_test:test_system()
test_system() ->
    chat(
        <<("写一首关于月亮的诗")/utf8>>,
        <<("你是一位唐代诗人，擅长七言绝句")/utf8>>
    ).

%% @doc 测试3: 多轮对话   qianwen_test:test_chat_multi()
test_chat_multi() ->
    Messages = [
        {user,      <<("你好")/utf8>>},
        {assistant, <<("你好！有什么可以帮你的？")/utf8>>},
        {user,      <<("今天天气怎么样？")/utf8>>}
    ],
    chat_multi(Messages).

%% @doc 测试4: JSON 结构化输出   qianwen_test:test_json()
test_json() ->
    Schema = #{
        <<"type">> => <<"object">>,
        <<"properties">> => #{
            <<"fruits">> => #{
                <<"type">>  => <<"array">>,
                <<"items">> => #{
                    <<"type">> => <<"object">>,
                    <<"properties">> => #{
                        <<"name">>  => #{<<"type">> => <<"string">>},
                        <<"color">> => #{<<"type">> => <<"string">>}
                    },
                    <<"required">> => [<<"name">>, <<"color">>],
                    <<"additionalProperties">> => false
                }
            }
        },
        <<"required">> => [<<"fruits">>],
        <<"additionalProperties">> => false
    },
    chat_json(<<("列出3种水果及其颜色")/utf8>>, Schema).

%% @doc 测试5: qwen-max 高质量模型   qianwen_test:test_max()
test_max() ->
    chat_max(<<("请一步步推理: 一个农夫有17只羊, 除了9只以外都死了, 农夫还剩几只羊？")/utf8>>).
