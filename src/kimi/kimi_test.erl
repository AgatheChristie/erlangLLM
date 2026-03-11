%%%-------------------------------------------------------------------
%% @doc 月之暗面 Kimi (Moonshot) API 客户端 — 上层便捷接口 + 测试函数
%%
%% 对标 openai_test.erl, 提供便捷的调用方法。
%%
%% 在 shell 中测试:
%%   1> kimi_test:test_chat().
%%   2> kimi_test:test_system().
%%   3> kimi_test:test_json().
%%   4> kimi_test:test_chat_multi().
%%   5> kimi_test:test_stream().
%% @end
%%%-------------------------------------------------------------------

-module(kimi_test).
-include("ai_tou.hrl").
-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% 便捷接口
%%====================================================================

%% @doc 简单文本对话
%% 示例: kimi_test:chat(<<("你好，请介绍一下自己")/utf8>>).
chat(Text) when is_binary(Text) ->
    kimi_send:generate_content(#{?OPT_PROMPT => Text}).

%% @doc 带 System Instruction 的文本对话
%% 示例: kimi_test:chat(<<"写一首诗"/utf8>>, <<"你是一位唐代诗人"/utf8>>).
chat(Text, SystemInstruction) when is_binary(Text), is_binary(SystemInstruction) ->
    kimi_send:generate_content(#{
        ?OPT_PROMPT             => Text,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).

%% @doc 多轮对话
chat_multi(Messages) when is_list(Messages) ->
    kimi_send:generate_content(#{?OPT_MESSAGES => Messages}).

%% @doc 多轮对话 + System Instruction
chat_multi(Messages, SystemInstruction) when is_list(Messages), is_binary(SystemInstruction) ->
    kimi_send:generate_content(#{
        ?OPT_MESSAGES           => Messages,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).

%% @doc JSON 结构化输出
chat_json(Text, Schema) when is_binary(Text), is_map(Schema) ->
    kimi_send:generate_content(#{
        ?OPT_PROMPT          => Text,
        ?OPT_RESPONSE_FORMAT => openai_send:build_response_format(Schema)
    }).

%%====================================================================
%% 流式接口
%%====================================================================

%% @doc 流式对话 — Callback 模式
stream(Text, Callback) when is_binary(Text), is_function(Callback, 1) ->
    kimi_send:stream_content(#{?OPT_PROMPT => Text}, Callback).

%% @doc 流式对话 — 收集全部文本
stream_collect(Text) when is_binary(Text) ->
    kimi_send:stream_collect(#{?OPT_PROMPT => Text}).

%%====================================================================
%% 测试函数
%%====================================================================

%% @doc 测试1: 基础文本对话  kimi_test:test_chat()
test_chat() ->
    chat(<<("你好，请用一句话介绍一下你自己")/utf8>>).

%% @doc 测试2: 带 System Instruction 的对话  kimi_test:test_system()
test_system() ->
    chat(
        <<("写一首关于月亮的诗")/utf8>>,
        <<("你是一位唐代诗人，擅长七言绝句")/utf8>>
    ).

%% @doc 测试3: 多轮对话  kimi_test:test_chat_multi()
test_chat_multi() ->
    Messages = [
        {user,      <<("你好")/utf8>>},
        {assistant, <<("你好！有什么可以帮你的？")/utf8>>},
        {user,      <<("今天天气怎么样？")/utf8>>}
    ],
    chat_multi(Messages).

%% @doc 测试4: JSON 结构化输出  kimi_test:test_json()
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

%% @doc 测试5: 流式对话  kimi_test:test_stream()
test_stream() ->
    stream(<<("用100字描述一下春天")/utf8>>,
        fun(#{type := data, data := Json}) ->
            case maps:get(<<"choices">>, Json, []) of
                [#{<<"delta">> := Delta} | _] ->
                    case maps:get(<<"content">>, Delta, undefined) of
                        undefined -> ok;
                        null      -> ok;
                        Content   -> io:format("~ts", [Content])
                    end;
                _ -> ok
            end;
        (#{type := done}) ->
            io:format("~n[完成]~n");
        (_) -> ok
        end).

%% @doc 测试6: 流式收集完整文本  kimi_test:test_stream_collect()
test_stream_collect() ->
    stream_collect(<<("用50字介绍月之暗面")/utf8>>).
