%%%-------------------------------------------------------------------
%% @doc DeepSeek API 客户端 — 上层便捷接口 + 测试函数
%%
%% 对标 openai_test.erl, 提供便捷的调用方法。
%%
%% 在 shell 中测试:
%%   1> deepseek_test:test_chat().
%%   2> deepseek_test:test_system().
%%   3> deepseek_test:test_json().
%%   4> deepseek_test:test_chat_multi().
%%   5> deepseek_test:test_reasoner().
%% @end
%%%-------------------------------------------------------------------

-module(deepseek_test).
-include("ai_tou.hrl").
-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% 便捷接口
%%====================================================================
%% deepseek_test:get_models().
get_models() ->
    #{api_url := ApiUrl, api_key := ApiKey} = deepseek_send:default_config(),
    Url = <<ApiUrl/binary, "/models">>,
    Headers = [
        {<<"Authorization">>, <<"Bearer ", ApiKey/binary>>},
        {<<"Content-Type">>,  <<"application/json">>}
    ],
    Options = [{connect_timeout, 10000}, {recv_timeout, 30000}],
    case hackney:request(get, Url, Headers, <<>>, Options) of
        {ok, 200, _RespHeaders, ClientRef} ->
            {ok, Body} = hackney:body(ClientRef),
            jiffy:decode(Body, [return_maps]);
        {ok, StatusCode, _RespHeaders, ClientRef} ->
            {ok, Body} = hackney:body(ClientRef),
            {error, {http_error, StatusCode, Body}};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc 简单文本对话
%% 示例: deepseek_test:chat(<<("你好，请介绍一下自己")/utf8>>).
chat(Text) when is_binary(Text) ->
    deepseek_send:generate_content(#{?OPT_PROMPT => Text}).

%% @doc 带 System Instruction 的文本对话
%% 示例: deepseek_test:chat(<<"写一首诗"/utf8>>, <<"你是一位唐代诗人"/utf8>>).
chat(Text, SystemInstruction) when is_binary(Text), is_binary(SystemInstruction) ->
    deepseek_send:generate_content(#{
        ?OPT_PROMPT             => Text,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).

%% @doc 多轮对话
chat_multi(Messages) when is_list(Messages) ->
    deepseek_send:generate_content(#{?OPT_MESSAGES => Messages}).

%% @doc 多轮对话 + System Instruction
chat_multi(Messages, SystemInstruction) when is_list(Messages), is_binary(SystemInstruction) ->
    deepseek_send:generate_content(#{
        ?OPT_MESSAGES           => Messages,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).

%% @doc JSON 结构化输出
%% 注意: DeepSeek 支持 json_object 模式, 但对 json_schema 的支持可能有限。
%% 建议使用 json_object + 在 system prompt 中描述输出格式。
chat_json(Text, Schema) when is_binary(Text), is_map(Schema) ->
    deepseek_send:generate_content(#{
        ?OPT_PROMPT          => Text,
        ?OPT_RESPONSE_FORMAT => openai_send:build_response_format(Schema)
    }).

%% @doc 使用 DeepSeek-R1 推理模型
%% 示例: deepseek_test:reasoner(<<"请一步步推理: 9.11 和 9.9 哪个更大？"/utf8>>).
reasoner(Text) when is_binary(Text) ->
    Config = (deepseek_send:default_config())#{model => <<"deepseek-reasoner">>},
    deepseek_send:generate_content(#{?OPT_PROMPT => Text}, Config).

%%====================================================================
%% 测试函数
%%====================================================================

%% @doc 测试1: 基础文本对话  deepseek_test:test_chat()
test_chat() ->
    chat(<<("你好，请用一句话介绍一下你自己")/utf8>>).

%% @doc 测试2: 带 System Instruction 的对话 deepseek_test:test_system()
test_system() ->
    chat(
        <<("写一首关于月亮的诗")/utf8>>,
        <<("你是一位唐代诗人，擅长七言绝句")/utf8>>
    ).

%% @doc 测试3: 多轮对话   deepseek_test:test_chat_multi()
test_chat_multi() ->
    Messages = [
        {user,      <<("你好")/utf8>>},
        {assistant, <<("你好！有什么可以帮你的？")/utf8>>},
        {user,      <<("今天天气怎么样？")/utf8>>}
    ],
    chat_multi(Messages).

%% @doc 测试4: JSON 结构化输出   deepseek_test:test_json()
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

%% @doc 测试5: 推理模型 (DeepSeek-R1)   deepseek_test:test_reasoner()
test_reasoner() ->
    reasoner(<<("请一步步推理: 一个农夫有17只羊, 除了9只以外都死了, 农夫还剩几只羊？")/utf8>>).
