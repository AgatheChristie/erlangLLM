%%%-------------------------------------------------------------------
%% @doc OpenAI Responses API — 请求构建 + 发送 + 响应解析
%%
%% 基于 OpenAI Responses API (取代旧版 Chat Completions API)。
%% 支持 Provider 配置参数, 兼容 API 可直接复用。
%%
%% 架构:
%%   openai_send  = 请求构建 + 发送 + 响应提取 (Responses API 格式)
%%   openai_test  = 上层便捷接口 + 测试函数
%%
%% Responses API 与旧版 Chat Completions 的核心差异:
%%   - 端点:    /chat/completions → /responses
%%   - 输入:    messages → input (字符串或消息列表)
%%   - 指令:    system 角色消息 → instructions (顶级字段)
%%   - 输出格式: response_format → text.format
%%   - Token 限制: max_completion_tokens → max_output_tokens
%%   - 响应结构: choices[0].message.content → output[].content[].text
%%
%% 调用方式:
%%   %% 使用默认 OpenAI 配置
%%   openai_send:generate_content(#{prompt => <<"你好"/utf8>>}).
%%
%%   %% 使用自定义 Provider 配置
%%   openai_send:generate_content(#{prompt => <<"你好"/utf8>>}, #{
%%       api_url => <<"https://api.deepseek.com/v1">>,
%%       api_key => <<"sk-xxx">>,
%%       model   => <<"deepseek-chat">>,
%%       log_prefix => <<"deepseek">>
%%   }).
%%
%% 流式:
%%   openai_send:stream_content(#{prompt => <<"你好"/utf8>>}, Callback).
%% @end
%%%-------------------------------------------------------------------

-module(openai_send).
-behaviour(ai_send_behavior).
-include("ai_tou.hrl").
-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% 构建 Responses API 请求体
%%====================================================================

%% @doc 把 Opts 翻译成 OpenAI Responses API 的 JSON 请求体
%%
%% 支持的 Opts 字段:
%%   prompt              => binary()          — 必填, 用户消息
%%   system_instruction  => binary()          — 可选, instructions 顶级指令
%%   messages            => [{atom(),binary}] — 可选, 多轮消息 (优先于 prompt)
%%   response_format     => map()             — 可选, text.format 结构体
%%                                              (由 build_response_format/1 构建)
%%   max_output_tokens   => integer()         — 可选, 最大回复 token 数
%%   temperature         => float()           — 可选, 0~2 控制随机性
%%   top_p               => float()           — 可选, 0~1 核采样
%%   stream              => boolean()         — 可选, 是否流式 (内部使用)
%%
%% Config 字段 (可选, 用于兼容 API):
%%   model => binary()  — 覆盖默认模型名
build_request_body(Opts) ->
    build_request_body(Opts, #{}).

build_request_body(Opts, Config) ->
    Model = maps:get(model, Config, ?OPENAI_MODEL),

    %% 1. input — 构建输入 (字符串或消息列表)
    Input = build_input(Opts),

    %% 2. 基础请求体
    Body0 = #{
        <<"model">> => Model,
        <<"input">> => Input
    },

    %% 3. instructions — system 指令提升为顶级字段
    Body1 = case maps:get(?OPT_SYSTEM_INSTRUCTION, Opts, undefined) of
        undefined -> Body0;
        SysInstr  -> Body0#{<<"instructions">> => SysInstr}
    end,

    %% 4. text.format — 结构化输出 (替代旧版 response_format)
    Body2 = case maps:get(?OPT_RESPONSE_FORMAT, Opts, undefined) of
        undefined -> Body1;
        Format    -> Body1#{<<"text">> => #{<<"format">> => Format}}
    end,

    %% 5. 可选参数
    Body3 = maybe_set(<<"max_output_tokens">>, ?OPT_MAX_OUTPUT_TOKENS, Opts, Body2),
    Body4 = maybe_set(<<"temperature">>,        ?OPT_TEMPERATURE,       Opts, Body3),
    Body5 = maybe_set(<<"top_p">>,              ?OPT_TOP_P,             Opts, Body4),

    %% 6. stream
    Body6 = case maps:get(?OPT_STREAM, Opts, false) of
        true  -> Body5#{<<"stream">> => true};
        false -> Body5
    end,

    jiffy:encode(Body6).

%% @doc 构建 input — 单轮返回字符串, 多轮返回消息列表
build_input(Opts) ->
    case maps:get(?OPT_MESSAGES, Opts, undefined) of
        MsgList when is_list(MsgList) ->
            lists:map(fun({Role, Content}) ->
                #{<<"role">> => role_to_bin(Role), <<"content">> => Content}
            end, MsgList);
        undefined ->
            maps:get(?OPT_PROMPT, Opts)
    end.

%% @doc 角色原子转二进制
role_to_bin(user)      -> <<"user">>;
role_to_bin(assistant)  -> <<"assistant">>;
role_to_bin(system)    -> <<"system">>;
role_to_bin(_)         -> <<"user">>.

%% @doc 条件设置字段: Opts 中有该 key 才放进 Body
maybe_set(JsonKey, OptsKey, Opts, Body) ->
    case maps:get(OptsKey, Opts, undefined) of
        undefined -> Body;
        Value     -> Body#{JsonKey => Value}
    end.

%%====================================================================
%% 构建 text.format (供外部调用方使用)
%%====================================================================

%% @doc 构建 text.format — JSON Schema 严格模式
%%
%% Responses API 中 structured output 的 json_schema 结构是扁平的:
%%   name / strict / schema 与 type 同级, 不再嵌套在 json_schema 子对象中
%%
%% 示例:
%%   Schema = jiffy:decode(<<"{...}">>, [return_maps]),
%%   openai_send:build_response_format(Schema).
%%   => #{<<"type">> => <<"json_schema">>,
%%        <<"name">> => <<"structured_output">>,
%%        <<"strict">> => true,
%%        <<"schema">> => Schema}
build_response_format(Schema) when is_map(Schema) ->
    #{
        <<"type">>   => <<"json_schema">>,
        <<"name">>   => <<"structured_output">>,
        <<"strict">> => true,
        <<"schema">> => normalize_schema(Schema)
    };

%% @doc 构建 text.format — 简单 JSON 模式 (无 Schema 约束)
%%
%% 示例: openai_send:build_response_format(json_object).
%%   => #{<<"type">> => <<"json_object">>}
build_response_format(json_object) ->
    #{<<"type">> => <<"json_object">>}.

%% @doc 递归归一化 schema: Gemini 格式 → OpenAI strict 格式
%% 1) 大写类型名 → 小写  2) object 自动补 additionalProperties + required
normalize_schema(Schema) when is_map(Schema) ->
    S1 = maps:map(fun(Key, Val) ->
        case Key of
            <<"type">> when is_binary(Val) -> string:lowercase(Val);
            <<"properties">> when is_map(Val) ->
                maps:map(fun(_K, V) -> normalize_schema(V) end, Val);
            <<"items">> when is_map(Val) -> normalize_schema(Val);
            _ -> Val
        end
    end, Schema),
    ensure_object_strict(S1);
normalize_schema(Other) -> Other.

%% @doc 若 schema 是 object 且有 properties，自动补齐 strict 模式所需字段
ensure_object_strict(Schema) ->
    Type = maps:get(<<"type">>, Schema, undefined),
    Props = maps:get(<<"properties">>, Schema, undefined),
    case {Type, Props} of
        {T, P} when (T =:= <<"object">> orelse T =:= <<"OBJECT">>), is_map(P) ->
            S1 = case maps:is_key(<<"additionalProperties">>, Schema) of
                true  -> Schema;
                false -> Schema#{<<"additionalProperties">> => false}
            end,
            case maps:is_key(<<"required">>, S1) of
                true  -> S1;
                false -> S1#{<<"required">> => maps:keys(P)}
            end;
        _ -> Schema
    end.

%%====================================================================
%% 统一入口: generate_content (非流式)
%%====================================================================

-define(MAX_RETRY, 2).

%% @doc 使用默认 OpenAI 配置
generate_content(Opts) when is_map(Opts) ->
    generate_content(Opts, default_config()).

%% @doc 使用自定义 Provider 配置
%% Config = #{api_url => binary(), api_key => binary(),
%%            model => binary(), log_prefix => binary()}
generate_content(Opts, Config) when is_map(Opts), is_map(Config) ->
    generate_content(Opts, Config, 0).

generate_content(Opts, Config, Attempt) when is_map(Opts), is_map(Config) ->
    Payload = build_request_body(Opts, Config),
    JsonMode = maps:is_key(?OPT_RESPONSE_FORMAT, Opts) orelse maps:get(?OPT_JSON_MODE, Opts, false),
    {Url, Headers, LogPrefix} = request_params(Config),
    case ai_http_client:request(Url, Headers, Payload, #{log_prefix => LogPrefix}) of
        {ok, Body} ->
            RespData = jiffy:decode(Body, [return_maps]),
            TextBin = extract_response_text(RespData),
            case is_degenerate(TextBin) of
                true when Attempt < ?MAX_RETRY ->
                    timer:sleep(500),
                    generate_content(Opts, Config, Attempt + 1);
                _ ->
                    process_response(TextBin, JsonMode)
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% 流式入口: stream_content
%%====================================================================

%% @doc 流式请求 — 使用默认 OpenAI 配置
%%
%% Callback :: fun(Event) -> any()
%%   Event = #{type => data, data => map()} | #{type => done}
%%
%% Responses API 流式事件 (data 中的 JSON):
%%   type = <<"response.output_text.delta">>  → delta 字段为文本增量
%%   type = <<"response.output_text.done">>   → 文本生成完成
%%   type = <<"response.completed">>          → 响应完成
%%
%% 示例:
%%   openai_send:stream_content(
%%     #{prompt => <<"你好"/utf8>>},
%%     fun(#{type := data, data := Json}) ->
%%         case maps:get(<<"type">>, Json, undefined) of
%%             <<"response.output_text.delta">> ->
%%                 io:format("~ts", [maps:get(<<"delta">>, Json, <<>>)]);
%%             _ -> ok
%%         end;
%%     (#{type := done}) -> io:format("~n[完成]~n")
%%     end).
stream_content(Opts, Callback) when is_map(Opts), is_function(Callback, 1) ->
    stream_content(Opts, default_config(), Callback).

%% @doc 流式请求 — 使用自定义配置
stream_content(Opts, Config, Callback) when is_map(Opts), is_map(Config), is_function(Callback, 1) ->
    StreamOpts = Opts#{?OPT_STREAM => true},
    Payload = build_request_body(StreamOpts, Config),
    {Url, Headers, _LogPrefix} = request_params(Config),
    ai_stream:request(Url, Headers, Payload, Callback).

%% @doc 流式请求 — 收集全部文本 (使用默认配置)
%% 返回: {ok, FullText :: binary()} | {error, Reason}
stream_collect(Opts) when is_map(Opts) ->
    stream_collect(Opts, default_config()).

%% @doc 流式请求 — 收集全部文本 (使用自定义配置)
stream_collect(Opts, Config) when is_map(Opts), is_map(Config) ->
    StreamOpts = Opts#{?OPT_STREAM => true},
    Payload = build_request_body(StreamOpts, Config),
    {Url, Headers, _LogPrefix} = request_params(Config),
    ai_stream:request_collect(Url, Headers, Payload, responses_stream_extract_fun()).

%%====================================================================
%% 响应处理
%%====================================================================

%% @doc 处理 AI 响应 (JSON 模式或文本模式)
process_response(TextBin, true) ->
    case ai_json_util:parse_ai_response(TextBin) of
        {ok, Map}          -> {ok, Map};
        {error, ParseErr}  -> {error, {json_parse_error, ParseErr, TextBin}}
    end;
process_response(TextBin, false) ->
    {ok, TextBin}.

%% @doc 退化检测 (回复内容异常时触发重试)
is_degenerate(Bin) when is_binary(Bin) -> false.

%%====================================================================
%% 响应解析 — Responses API 格式
%%====================================================================

%% @doc 提取 Responses API 响应中的文本内容
%%
%% Responses API 返回格式:
%% {
%%   "output": [
%%     {
%%       "type": "message",
%%       "status": "completed",
%%       "content": [
%%         {"type": "output_text", "text": "实际回复"}
%%       ],
%%       "role": "assistant"
%%     }
%%   ]
%% }
extract_response_text(RespData) when is_map(RespData) ->
    Output = maps:get(<<"output">>, RespData, []),
    extract_text_from_output(Output).

extract_text_from_output([]) ->
    <<"未找到回复内容"/utf8>>;
extract_text_from_output([Item | Rest]) when is_map(Item) ->
    case maps:get(<<"type">>, Item, undefined) of
        <<"message">> ->
            Content = maps:get(<<"content">>, Item, []),
            extract_text_from_content(Content);
        _ ->
            extract_text_from_output(Rest)
    end;
extract_text_from_output([_ | Rest]) ->
    extract_text_from_output(Rest).

extract_text_from_content([]) ->
    <<"内容为空"/utf8>>;
extract_text_from_content([Part | Rest]) when is_map(Part) ->
    case maps:get(<<"type">>, Part, undefined) of
        <<"output_text">> ->
            maps:get(<<"text">>, Part, <<"内容为空"/utf8>>);
        _ ->
            extract_text_from_content(Rest)
    end;
extract_text_from_content([_ | Rest]) ->
    extract_text_from_content(Rest).

%%====================================================================
%% Responses API 流式事件提取
%%====================================================================

%% @doc Responses API SSE 事件中的文本增量提取
%%
%% 事件格式 (SSE data 中的 JSON):
%%   {"type": "response.output_text.delta", "delta": "文本片段"}
%%   {"type": "response.output_text.done",  "text": "完整文本"}
%%   {"type": "response.completed",         "response": {...}}
responses_stream_extract_fun() ->
    fun(Json) ->
        case maps:get(<<"type">>, Json, undefined) of
            <<"response.output_text.delta">> ->
                case maps:get(<<"delta">>, Json, undefined) of
                    undefined -> skip;
                    null      -> skip;
                    Delta     -> {text, Delta}
                end;
            <<"response.output_text.done">> ->
                done;
            <<"response.completed">> ->
                done;
            _ ->
                skip
        end
    end.

%% @doc Responses API 流式 content delta 提取 (供 ai_stream:get_content_extract_fun 使用)
%%
%% Flag = ?AI_STREAM_CONTENT → 用于实时推送, 返回 {ok, Delta} | skip
%% Flag = ?AI_STREAM_COLLECT → 用于收集模式, 返回 {text, Delta} | done | skip
responses_content_extract_fun(Flag) ->
    fun(Json) ->
        case maps:get(<<"type">>, Json, undefined) of
            <<"response.output_text.delta">> ->
                case maps:get(<<"delta">>, Json, undefined) of
                    undefined -> skip;
                    null      -> skip;
                    Delta     ->
                        case Flag == ?AI_STREAM_CONTENT of
                            true ->
                                {ok, Delta};
                            _ ->
                                {text, Delta}
                        end

                end;
            <<"response.output_text.done">> ->
                case Flag == ?AI_STREAM_CONTENT of
                    true ->
                        skip;
                    _ ->
                        done
                end;
            <<"response.completed">> ->
                case Flag == ?AI_STREAM_CONTENT of
                    true ->
                        skip;
                    _ ->
                        done
                end;
            _ ->
                skip
        end
    end.




%%====================================================================
%% embeddings
%%====================================================================

embeddings(Input) ->
    openai_embeddings:embeddings(Input).




%%====================================================================
%% Provider 配置
%%====================================================================

%% @doc 默认 OpenAI 配置 (从 ai_tou.hrl 宏读取)
default_config() ->
    #{
        api_url    => ?OPENAI_API_URL,
        api_key    => ?OPENAI_API_KEY,
        model      => ?OPENAI_MODEL,
        log_prefix => <<"openai">>
    }.

%% @doc 从 Config 生成请求参数 {Url, Headers, LogPrefix}
request_params(Config) ->
    ApiUrl = maps:get(api_url, Config, ?OPENAI_API_URL),
    ApiKey = maps:get(api_key, Config, ?OPENAI_API_KEY),
    LogPrefix = maps:get(log_prefix, Config, <<"openai">>),
    Url = <<ApiUrl/binary, "/responses">>,
    Headers = [
        {<<"Authorization">>, <<"Bearer ", ApiKey/binary>>},
        {<<"Content-Type">>,  <<"application/json">>}
    ],
    {Url, Headers, LogPrefix}.
