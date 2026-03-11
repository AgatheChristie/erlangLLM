%%%-------------------------------------------------------------------
%% @doc 豆包 (火山方舟) API 客户端 — 上层便捷接口 + 测试函数
%%
%% 重构: 已从 Responses API 切换为 Chat Completions (OpenAI 兼容格式)。
%% 底层通过 doubao_send → openai_send → ai_http_client 调用。
%%
%% 好处:
%%   - 和 OpenAI / DeepSeek 走统一的 ai_provider 体系
%%   - 共享重试、流式、Schema 转换等基础设施
%%   - 可通过 ai_provider:generate_content(doubao, Opts) 统一调用
%%
%% 在 shell 中测试:
%%   1> doubao_test:test_chat().
%%   2> doubao_test:test_system().
%%   3> doubao_test:test_json().
%%   4> doubao_test:test_chat_multi().
%%   5> doubao_test:test_stream().
%% @end
%%%-------------------------------------------------------------------

-module(doubao_test).
-include("common.hrl").
-include("ai_tou.hrl").

-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% 便捷接口 (Chat Completions 格式)
%%====================================================================

%% @doc 简单文本对话
%% 示例: doubao_test:chat(<<("你好，请介绍一下自己")/utf8>>).
chat(Text) when is_binary(Text) ->
    doubao_send:generate_content(#{?OPT_PROMPT => Text}).

%% @doc 带 System Instruction 的文本对话
%% 示例: doubao_test:chat(<<"写一首诗"/utf8>>, <<"你是一位唐代诗人"/utf8>>).
chat(Text, SystemInstruction) when is_binary(Text), is_binary(SystemInstruction) ->
    doubao_send:generate_content(#{
        ?OPT_PROMPT             => Text,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).




%% @doc 多轮对话
%% 示例:
%%   Messages = [
%%     {user, <<"你好">>},
%%     {assistant, <<"你好！有什么可以帮你的？">>},
%%     {user, <<"今天天气怎么样？">>}
%%   ],
%%   doubao_test:chat_multi(Messages).
chat_multi(Messages) when is_list(Messages) ->
    doubao_send:generate_content(#{?OPT_MESSAGES => Messages}).

%% @doc 多轮对话 + System Instruction
chat_multi(Messages, SystemInstruction) when is_list(Messages), is_binary(SystemInstruction) ->
    doubao_send:generate_content(#{
        ?OPT_MESSAGES           => Messages,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction
    }).

%% @doc JSON 结构化输出
%% Schema 使用标准 JSON Schema 格式 (小写 type), 例如:
%%   Schema = #{
%%     <<"type">> => <<"object">>,
%%     <<"properties">> => #{
%%       <<"name">> => #{<<"type">> => <<"string">>}
%%     },
%%     <<"required">> => [<<"name">>],
%%     <<"additionalProperties">> => false
%%   }
chat_json(Text, Schema) when is_binary(Text), is_map(Schema) ->
    doubao_send:generate_content(#{
        ?OPT_PROMPT          => Text,
        ?OPT_RESPONSE_FORMAT => openai_send:build_response_format(Schema)
    }).

%% @doc JSON 结构化输出 + System Instruction
%% 示例: doubao_test:chat_json(<<"列出3种水果"/utf8>>, Schema, <<"你是植物学家"/utf8>>).
chat_json(Text, Schema, SystemInstruction) when is_binary(Text), is_map(Schema), is_binary(SystemInstruction) ->
    doubao_send:generate_content(#{
        ?OPT_PROMPT             => Text,
        ?OPT_SYSTEM_INSTRUCTION => SystemInstruction,
        ?OPT_RESPONSE_FORMAT    => openai_send:build_response_format(Schema)
    }).

%%====================================================================
%% 流式接口
%%====================================================================

%% @doc 流式对话 — Callback 模式
%% 示例:
%%   doubao_test:stream(<<"写一首诗"/utf8>>,
%%     fun(#{type := data, data := Json}) ->
%%         case maps:get(<<"choices">>, Json, []) of
%%             [#{<<"delta">> := #{<<"content">> := C}} | _] ->
%%                 io:format("~ts", [C]);
%%             _ -> ok
%%         end;
%%     (#{type := done}) -> io:format("~n")
%%     end).
stream(Text, Callback) when is_binary(Text), is_function(Callback, 1) ->
    doubao_send:stream_content(#{?OPT_PROMPT => Text}, Callback).

%% @doc 流式对话 — 收集全部文本
%% 示例: {ok, Text} = doubao_test:stream_collect(<<"写一首诗"/utf8>>).
stream_collect(Text) when is_binary(Text) ->
    doubao_send:stream_collect(#{?OPT_PROMPT => Text}).

%%====================================================================
%% 兼容旧接口 (保留, 内部已切换为 Chat Completions)
%%====================================================================

%% @doc 兼容旧版 doubao_chat/1 调用
doubao_chat(Text) when is_binary(Text) ->
    chat(Text).

%% @doc 兼容旧版 doubao_chat_multi/1 调用
doubao_chat_multi(Messages) when is_list(Messages) ->
    chat_multi(Messages).

%%====================================================================
%% 测试函数
%%====================================================================

%% @doc 测试1: 基础文本对话  doubao_test:test_chat().
test_chat() ->
    chat(<<("你好，请用一句话介绍一下你自己")/utf8>>).

%% @doc 测试2: 带 System Instruction 的对话  doubao_test:test_system().
test_system() ->
    chat(
        <<("写一首关于月亮的诗")/utf8>>,
        <<("你是一位唐代诗人，擅长七言绝句")/utf8>>
    ).

%% @doc 测试3: 多轮对话  doubao_test:test_chat_multi().
test_chat_multi() ->
    Messages = [
        {user,      <<("你好")/utf8>>},
        {assistant, <<("你好！有什么可以帮你的？")/utf8>>},
        {user,      <<("今天天气怎么样？")/utf8>>}
    ],
    chat_multi(Messages).

%% @doc 测试4: JSON 结构化输出  doubao_test:test_json().
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

%% @doc 测试5: 流式对话 (打印到控制台)  doubao_test:test_stream().
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

%% @doc 测试6: 流式收集完整文本  doubao_test:test_stream_collect().
test_stream_collect() ->
    stream_collect(<<("用50字介绍惠州")/utf8>>).







