%%%-------------------------------------------------------------------
%% @doc 通用 AI HTTP 客户端 — 带指数退避重试
%%
%% 从各 Provider _send 模块中提取的共享 HTTP 逻辑。
%% 所有 AI Provider 共用同一套重试、超时、日志策略。
%%
%% 对齐: Google GenAI SDK / OpenAI Python SDK 的重试策略
%%   - 指数退避 + 随机抖动
%%   - 可重试状态码: 408, 429, 500, 502, 503, 504
%%   - 最多 5 次尝试 (含首次)
%%
%% 用法:
%%   ai_http_client:request(Url, Headers, Payload).
%%   ai_http_client:request(Url, Headers, Payload, #{log_prefix => <<"openai">>}).
%% @end
%%%-------------------------------------------------------------------

-module(ai_http_client).
-include("common.hrl").

-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% 默认配置 (对齐 Google GenAI SDK / OpenAI Python SDK)
%%====================================================================

-define(DEFAULT_RETRYABLE_STATUS, [408, 429, 500, 502, 503, 504]).
-define(DEFAULT_MAX_ATTEMPTS, 5).       %% 总尝试次数 (含首次)
-define(DEFAULT_INITIAL_DELAY, 1.0).    %% 首次重试基础延迟 (秒)
-define(DEFAULT_EXP_BASE, 2).           %% 指数基数
-define(DEFAULT_MAX_DELAY, 60.0).       %% 最大延迟 (秒)
-define(DEFAULT_JITTER, 1.0).           %% 随机抖动 (秒)

%%====================================================================
%% 公共接口
%%====================================================================

%% @doc 发送 POST 请求, 返回原始响应体 (带自动重试)
%%
%% Opts 可选字段:
%%   log_prefix       => binary()   — 日志文件前缀, 如 <<"gg">>, <<"openai">>
%%   max_attempts     => integer()  — 最大尝试次数 (默认 5)
%%   retryable_status => [integer()]— 可重试 HTTP 状态码列表
%%   enable_log       => boolean()  — 是否写入日志文件 (默认 true)
%%
%% 返回: {ok, RespBody :: binary()} | {error, Reason}
request(Url, Headers, Payload) ->
    request(Url, Headers, Payload, #{}).

request(Url, Headers, Payload, Opts) ->
    MaxAttempts = maps:get(max_attempts, Opts, ?DEFAULT_MAX_ATTEMPTS),
    LogPrefix = maps:get(log_prefix, Opts, <<"ai">>),
    RetryableStatus = maps:get(retryable_status, Opts, ?DEFAULT_RETRYABLE_STATUS),
    EnableLog = maps:get(enable_log, Opts, true),
    do_request(post, Url, Headers, Payload, 0, MaxAttempts, LogPrefix, RetryableStatus, EnableLog).

%%====================================================================
%% 内部: HTTP 请求 + 重试循环
%%====================================================================

do_request(Method, Url, Headers, Payload, Attempt, MaxAttempts, LogPrefix, RetryableStatus, EnableLog) ->
    Options = [
        {connect_timeout, ?HTTP_CONNECT_TIMEOUT},
        {recv_timeout,    ?HTTP_RECV_TIMEOUT}
    ],
    %% 日志文件 (月日时分秒)
    Ts = ai_util:log_timestamp(),
    LogPrefixStr = binary_to_list(LogPrefix),
    case EnableLog of
        true ->
            file:write_file("log/" ++ LogPrefixStr ++ "_payload_" ++ Ts ++ ".json", Payload);
        false ->
            ok
    end,
    case hackney:request(Method, Url, Headers, Payload, Options) of
        {ok, 200, _RespHeaders, ClientRef} ->
            {ok, Body} = hackney:body(ClientRef),
            case EnableLog of
                true ->
                    file:write_file("log/" ++ LogPrefixStr ++ "_reply_" ++ Ts ++ ".json", Body);
                false ->
                    ok
            end,
            {ok, Body};
        {ok, StatusCode, _RespHeaders, ClientRef} ->
            CanRetry = lists:member(StatusCode, RetryableStatus)
                       andalso Attempt + 1 < MaxAttempts,
            case CanRetry of
                true ->
                    %% 读掉 body 释放连接, 然后延迟重试
                    hackney:body(ClientRef),
                    Delay = retry_delay(Attempt),
                    ?INFO("[~s HTTP] ~p 临时错误, ~.1fs 后第~p次重试...~n",
                          [LogPrefixStr, StatusCode, Delay / 1000, Attempt + 1]),
                    timer:sleep(Delay),
                    do_request(Method, Url, Headers, Payload,
                               Attempt + 1, MaxAttempts, LogPrefix,
                               RetryableStatus, EnableLog);
                false ->
                    {ok, Body} = hackney:body(ClientRef),
                    ?INFO("[~s] 请求失败 [~p]: ~ts~n", [LogPrefixStr, StatusCode, Body]),
                    {error, {http_error, StatusCode, Body}}
            end;
        {error, Reason} ->
            case Attempt + 1 < MaxAttempts of
                true ->
                    Delay = retry_delay(Attempt),
                    ?INFO("[~s HTTP] 网络错误 ~p, ~.1fs 后第~p次重试...~n",
                          [LogPrefixStr, Reason, Delay / 1000, Attempt + 1]),
                    timer:sleep(Delay),
                    do_request(Method, Url, Headers, Payload,
                               Attempt + 1, MaxAttempts, LogPrefix,
                               RetryableStatus, EnableLog);
                false ->
                    ?INFO("[~s] 请求错误 (重试~p次仍失败): ~p~n",
                          [LogPrefixStr, MaxAttempts - 1, Reason]),
                    {error, Reason}
            end
    end.

%%====================================================================
%% 重试延迟计算 (指数退避 + 随机抖动)
%%====================================================================

%% @doc Delay = min(initial * base^attempt, max_delay) + random(0, jitter)
retry_delay(Attempt) ->
    Base = ?DEFAULT_INITIAL_DELAY * math:pow(?DEFAULT_EXP_BASE, Attempt),
    Capped = min(Base, ?DEFAULT_MAX_DELAY),
    Jitter = rand:uniform() * ?DEFAULT_JITTER,
    round((Capped + Jitter) * 1000).  %% 返回毫秒

