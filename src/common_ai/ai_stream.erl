%%%-------------------------------------------------------------------
%% @doc SSE (Server-Sent Events) 流式请求客户端
%%
%% 支持两种 AI API 流式响应格式:
%%   1. Responses API (OpenAI) — 基于 type 字段的事件:
%%      data: {"type":"response.output_text.delta","delta":"你"}
%%      data: {"type":"response.output_text.delta","delta":"好"}
%%      data: {"type":"response.completed","response":{...}}
%%      data: [DONE]
%%
%%   2. Chat Completions 兼容格式 (DeepSeek / 豆包 / Kimi 等):
%%      data: {"choices":[{"delta":{"content":"你"}}]}
%%      data: {"choices":[{"delta":{"content":"好"}}]}
%%      data: [DONE]
%%
%% 三种使用模式:
%%   1. Callback 模式: 每个事件调用回调函数
%%      ai_stream:request(Url, Headers, Payload, fun(Event) -> ... end).
%%
%%   2. 进程消息模式: 事件发送到指定进程
%%      ai_stream:request_to_pid(Url, Headers, Payload, self()),
%%      receive {ai_stream_data, Json} -> ...; ai_stream_done -> ... end.
%%
%%   3. 收集模式: 收集所有文本片段拼接为完整响应
%%      ai_stream:request_collect(Url, Headers, Payload, ExtractFun).
%%
%% @end
%%%-------------------------------------------------------------------

-module(ai_stream).
-include("common.hrl").
-include("ai_tou.hrl").

-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% 公共接口
%%====================================================================

%% @doc 流式请求 — Callback 模式
%%
%% 每收到一个 SSE 事件, 调用 Callback(Event):
%%   Event = #{type => data, data => map()}     — 正常数据事件 (已 JSON 解析)
%%         | #{type => done}                    — 流结束标记 [DONE]
%%         | #{type => error, reason => term()}  — 解析错误
%%
%% 返回: ok | {error, Reason}
%%
%% 示例:
%%   Callback = fun(#{type := data, data := Json}) ->
%%       Text = meili3_util:get_nested(Json,
%%           [<<"choices">>, <<"delta">>, <<"content">>], <<>>),
%%       io:format("~ts", [Text]);
%%   (#{type := done}) -> io:format("~n[完成]~n")
%%   end,
%%   ai_stream:request(Url, Headers, Payload, Callback).
request(Url, Headers, Payload, Callback) when is_function(Callback, 1) ->
    Options = [
        {connect_timeout, ?HTTP_CONNECT_TIMEOUT},
        {recv_timeout, ?HTTP_RECV_TIMEOUT}
    ],

    %% 日志文件 (月日时分秒)
    Ts = ai_util:log_timestamp(),

    file:write_file("log/" ++ "liushi_payload_" ++ Ts ++ ".json", Payload),
    case hackney:request(post, Url, Headers, Payload, Options) of
        {ok, 200, _RespHeaders, ClientRef} ->
            stream_loop(ClientRef, <<>>, Callback);
        {ok, StatusCode, _RespHeaders, ClientRef} ->
            {ok, Body} = hackney:body(ClientRef),
            ?INFO("[ai_stream] HTTP 错误 ~p: ~ts~n", [StatusCode, Body]),
            {error, {http_error, StatusCode, Body}};
        {error, Reason} ->
            ?INFO("[ai_stream] 网络错误: ~p~n", [Reason]),
            {error, Reason}
    end.

%% @doc 流式请求 — 进程消息模式
%%
%% 将事件以消息形式发送到指定进程:
%%   {ai_stream_data, JsonMap}  — 正常数据
%%   ai_stream_done             — 流结束
%%   {ai_stream_error, Reason}  — 错误
%%
%% 适合在 WebSocket handler 或 gen_server 中接收。
%%
%% 示例:
%%   ai_stream:request_to_pid(Url, Headers, Payload, self()),
%%   receive
%%       {ai_stream_data, Json} -> handle_chunk(Json);
%%       ai_stream_done -> done
%%   end.
request_to_pid(Url, Headers, Payload, Pid) when is_pid(Pid) ->
    request(Url, Headers, Payload, fun(Event) ->
        case Event of
            #{type := data, data := Json} ->
                Pid ! {ai_stream_data, Json};
            #{type := done} ->
                Pid ! ai_stream_done;
            #{type := error, reason := Reason} ->
                Pid ! {ai_stream_error, Reason}
        end
                                   end).

%% @doc 流式请求 — 收集模式 (拼接所有文本片段)
%%
%% ExtractFun 从每个 JSON 事件中提取文本片段:
%%   ExtractFun(JsonMap) -> {text, Binary} | skip | done
%%
%% 返回: {ok, FullText :: binary()} | {error, Reason}
%%
%% 示例 (OpenAI 格式):
%%   ExtractFun = fun(Json) ->
%%       case meili3_util:get_nested(Json,
%%                [<<"choices">>], []) of
%%           [#{<<"delta">> := #{<<"content">> := C}}|_] -> {text, C};
%%           [#{<<"finish_reason">> := <<"stop">>}|_] -> done;
%%           _ -> skip
%%       end
%%   end,
%%   {ok, FullText} = ai_stream:request_collect(Url, Headers, Payload, ExtractFun).
request_collect(Url, Headers, Payload, ExtractFun) when is_function(ExtractFun, 1) ->
    Ref = make_ref(),
    Self = self(),
    CallBack = fun(Event) ->
        case Event of
            #{type := data, data := Json} ->
                case ExtractFun(Json) of
                    {text, Text} -> Self ! {Ref, text, Text};
                    done -> Self ! {Ref, done};
                    skip -> ok
                end;
            #{type := done} ->
                Self ! {Ref, done};
            _ ->
                ok
        end
               end,
    case request(Url, Headers, Payload, CallBack) of
        ok ->
            collect_texts(Ref, []);
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% Provider 专用: OpenAI 兼容格式 (OpenAI / DeepSeek)
%%====================================================================


%%====================================================================
%% 流式工具: Content Delta 提取
%%====================================================================

%% @doc Responses API 格式 (OpenAI) — 基于 type 字段区分事件
get_content_extract_fun(_, Flag) ->
    fun(Json) ->
        case maps:get(<<"type">>, Json, undefined) of
            <<"response.output_text.delta">> ->
                case maps:get(<<"delta">>, Json, undefined) of
                    undefined -> skip;
                    null      -> skip;
                    Delta     -> ?IF(Flag == ?AI_STREAM_CONTENT, {ok, Delta}, {text, Delta})
                end;
            <<"response.output_text.done">> ->
                ?IF(Flag == ?AI_STREAM_CONTENT, skip, done);
            <<"response.completed">> ->
                ?IF(Flag == ?AI_STREAM_CONTENT, skip, done);
            _ ->
                skip
        end
    end.

%%====================================================================
%% 内部: SSE 解析循环
%%====================================================================

stream_loop(ClientRef, Buffer, Callback) ->
    case hackney:stream_body(ClientRef) of
        {ok, Data} ->
            NewBuffer = <<Buffer/binary, Data/binary>>,
            {Events, Rest} = parse_sse_events(NewBuffer),
            lists:foreach(fun(EventData) ->
                process_sse_event(EventData, Callback)
                          end, Events),
            stream_loop(ClientRef, Rest, Callback);
        done ->
            case byte_size(Buffer) > 0 of
                true ->
                    {Events, _} = parse_sse_events(<<Buffer/binary, "\n\n">>),
                    lists:foreach(fun(EventData) ->
                        process_sse_event(EventData, Callback)
                                  end, Events);
                false ->
                    ok
            end,
            ok;
        {error, Reason} ->
            Callback(#{type => error, reason => Reason}),
            {error, Reason}
    end.

%% @doc 处理单个 SSE 事件的数据部分
process_sse_event(<<"[DONE]">>, Callback) ->
    Callback(#{type => done});
process_sse_event(EventData, Callback) ->
    try
        JsonMap = jiffy:decode(EventData, [return_maps]),
%%       ?INFO("JsonMap:~p end",[JsonMap]),
        Callback(#{type => data, data => JsonMap})
    catch _:ParseErr ->
        ?INFO("[ai_stream] SSE 事件解析失败: ~p, 原始数据: ~ts~n",
            [ParseErr, EventData]),
        Callback(#{type => error, reason => {parse_error, EventData}})
    end.


%% @doc 流式调用核心：SSE → chunk 推送 → 累积全文 → 处理结果
%%
%% 两种推送模式 (通过 StreamOpts 的 mode 字段控制):
%%   text      — 直接推送 content delta (默认, 适合纯文本响应)
%%   json_text — 从累积 JSON 中增量提取 "text" 字段推送 (适合 JSON 结构化响应)
%%
%% StreamOpts:
%%   mode       => text | json_text  (默认 text)
%%   model_name => binary()          (可选, 覆盖 Provider 默认模型)
do_stream_generate(Opts, WsPid, Provider, DoFun) ->
    do_stream_generate(Opts, WsPid, Provider, DoFun, #{}).

do_stream_generate(Opts, WsPid, Provider, DoFun, StreamOpts) ->
    Mode = maps:get(mode, StreamOpts, text),
    ModelName = maps:get(model_name, StreamOpts, undefined),

    put(?DIC_S_JSON_BUF, <<>>),
    case Mode of
        json_text ->
            put(?DIC_S_TEXT_SENT, 0),
            put(?DIC_S_TEXT_DONE_SENT, false);
        _ -> ok
    end,

    ContentFun = get_content_extract_fun(Provider, ?AI_STREAM_CONTENT),

    Callback = fun(Event) ->
        case Event of
            #{type := data, data := Json} ->
%%                ?INFO("[debug] SSE event: ~p~n", [Json]),
                case ContentFun(Json) of
                    {ok, Content} ->
                        Buf0 = get(?DIC_S_JSON_BUF),
                        Buf1 = <<Buf0/binary, Content/binary>>,
                        put(?DIC_S_JSON_BUF, Buf1),
                        case Mode of
                            json_text ->
                                Sent0 = get(?DIC_S_TEXT_SENT),
                                Sent1 = push_text_field(WsPid, Buf1, Sent0),
                                put(?DIC_S_TEXT_SENT, Sent1);
                            text ->
                                WsPid ! {ai_stream_chunk, Content}
                        end;
                    skip -> ok
                end;
            #{type := error, reason := Reason} ->
                WsPid ! {ai_stream_error, Reason};
            _E ->
                ?INFO("[debug] SSE 222222222qqqqq: ~p~n", [_E]),
                ok
        end
               end,

    Mod = ai_provider:provider_module(Provider),
    ?INFO("[debug][do_stream] Provider=~p, Mod=~p, ModelName=~p~n",
          [Provider, Mod, ModelName]),
    StreamResult = case ModelName of
                       undefined ->
                           Mod:stream_content(Opts, Callback);
                       _ ->
                           Config = (Mod:default_config())#{model => ModelName},
                           openai_send:stream_content(Opts, Config, Callback)
                   end,

    case StreamResult of
        ok ->
            FullBuf = get(?DIC_S_JSON_BUF),
            ?INFO("[debug][do_stream] FullBuf size=~p~n", [byte_size(FullBuf)]),
            case Mode of
                text ->
                    WsPid ! ai_stream_done;
                json_text ->
                    case get(?DIC_S_TEXT_DONE_SENT) of
                        true -> ok;
                        _    -> WsPid ! ai_stream_done
                    end
            end,
            case FullBuf of
                <<>> -> {error, empty_response};
                _    ->
                    Ts = ai_util:log_timestamp(),
                    file:write_file("log/" ++ atom_to_list(Provider) ++ "_stream_" ++ Ts ++ ".json", FullBuf),
                    DoFun(FullBuf)
            end;
        {error, Reason} ->
            WsPid ! {ai_stream_error, Reason},
            ?ERROR("[ai_stream] stream error: ~p~n", [Reason]),
            {error, Reason}
    end.



%%====================================================================
%% 流式工具: JSON "text" 字段增量提取
%%====================================================================

%% @doc 从累积的 JSON buffer 中增量提取 "text" 字段并推送给 WsPid
%% SentLen = 已推送的文本字节数 (避免重复发送)
%% 返回: 新的 SentLen
push_text_field(WsPid, JsonBuf, SentLen) ->
    case ai_json_util:extract_text_from_json(JsonBuf) of
        {Status, Text} ->
            TextLen = byte_size(Text),
            if TextLen > SentLen ->
                NewPart = binary:part(Text, SentLen, TextLen - SentLen),
                WsPid ! {ai_stream_chunk, NewPart},
                %% text 字段完整关闭时，立即通知前端"文本结束"
                %% 这比等整个 stream 结束早 4-5 秒（AI 还在生成 choices/stats JSON）
                maybe_send_stream_done(Status, WsPid),
                TextLen;

                true ->
                    %% 没有新文本，但状态可能变为 complete
                    maybe_send_stream_done(Status, WsPid),
                    SentLen
            end;
        not_found ->
            SentLen
    end.

%% @doc text 字段完成时，立即通知前端流结束 (仅发一次)
%% 这让前端能在 AI 还在生成 choices/stats 时就显示"生成选项中..."
maybe_send_stream_done(complete, WsPid) ->
    case get(?DIC_S_TEXT_DONE_SENT) of
        true ->
            ok;  %% 已经发过了
        _ ->
            ?INFO("[ai_provider] text 字段完成, 提前发送 stream_done~n", []),
            WsPid ! ai_stream_done,
            put(?DIC_S_TEXT_DONE_SENT, true)
    end;
maybe_send_stream_done(_Partial, _WsPid) ->
    ok.

%%====================================================================
%% SSE 协议解析
%%====================================================================

%% @doc 从缓冲区中解析完整的 SSE 事件
%%
%% SSE 协议: 事件之间用空行 (\n\n) 分隔
%% 每个事件由多行组成, 常见行前缀:
%%   event: xxx    — 事件类型 (可选)
%%   data: {...}   — 数据内容 (核心)
%%   id: xxx       — 事件 ID (可选)
%%   retry: xxx    — 重连延迟 (可选)
%%
%% 返回: {[EventData], RemainingBuffer}
parse_sse_events(Buffer) ->
    parse_sse_events(Buffer, []).

parse_sse_events(Buffer, Acc) ->
    case binary:match(Buffer, <<"\n\n">>) of
        {Pos, _Len} ->
            EventBlock = binary:part(Buffer, 0, Pos),
            Rest = binary:part(Buffer, Pos + 2, byte_size(Buffer) - Pos - 2),
            case extract_data_from_event(EventBlock) of
                {ok, Data} ->
                    parse_sse_events(Rest, Acc ++ [Data]);
                skip ->
                    parse_sse_events(Rest, Acc)
            end;
        nomatch ->
            %% 也检查 \r\n\r\n (某些服务器用 CRLF)
            case binary:match(Buffer, <<"\r\n\r\n">>) of
                {Pos2, _} ->
                    EventBlock = binary:part(Buffer, 0, Pos2),
                    Rest = binary:part(Buffer, Pos2 + 4, byte_size(Buffer) - Pos2 - 4),
                    case extract_data_from_event(EventBlock) of
                        {ok, Data} ->
                            parse_sse_events(Rest, Acc ++ [Data]);
                        skip ->
                            parse_sse_events(Rest, Acc)
                    end;
                nomatch ->
                    {Acc, Buffer}
            end
    end.

%% @doc 从 SSE 事件块中提取 data 字段
%% 支持多行 data 拼接 (SSE 规范允许多个 data: 行)
extract_data_from_event(EventBlock) ->
    Lines = binary:split(EventBlock, [<<"\n">>, <<"\r\n">>], [global]),
    DataParts = lists:filtermap(fun(Line) ->
        case Line of
            <<"data: ", DataPart/binary>> -> {true, DataPart};
            <<"data:", DataPart/binary>> -> {true, ai_json_util:binary_trim(DataPart)};
            _ -> false
        end
                                end, Lines),
    case DataParts of
        [] -> skip;
        _ ->
            Joined = iolist_to_binary(lists:join(<<"\n">>, DataParts)),
            {ok, Joined}
    end.

%%====================================================================
%% 内部工具
%%====================================================================

%% 收集所有文本片段
collect_texts(Ref, Acc) ->
    receive
        {Ref, text, Text} ->
            collect_texts(Ref, [Text | Acc]);
        {Ref, done} ->
            {ok, iolist_to_binary(lists:reverse(Acc))}
    after 600000 ->  %% 10 分钟超时
        {error, stream_timeout}
    end.
