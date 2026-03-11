%%%-------------------------------------------------------------------
%% @doc 月之暗面 Kimi (Moonshot) API 客户端 — 复用 OpenAI 兼容格式
%%
%% Kimi (Moonshot) API 兼容 OpenAI Chat Completions 格式,
%% 因此本模块只是 openai_send 的薄封装, 替换为 Kimi 的配置即可。
%%
%% 调用方式:
%%   kimi_send:generate_content(#{prompt => <<"你好"/utf8>>}).
%%   kimi_send:generate_content(#{prompt => <<"你好"/utf8>>,
%%       response_format => openai_send:build_response_format(Schema)}).
%%
%% 流式:
%%   kimi_send:stream_content(#{prompt => <<"你好"/utf8>>}, Callback).
%%   kimi_send:stream_collect(#{prompt => <<"你好"/utf8>>}).
%%
%% 也可以切换模型:
%%   kimi_send:generate_content(#{prompt => <<"解释量子计算"/utf8>>},
%%       (kimi_send:default_config())#{model => <<"moonshot-v1-32k">>}).
%% @end
%%%-------------------------------------------------------------------

-module(kimi_send).
-behaviour(ai_send_behavior).
-include("common.hrl").
-include("ai_tou.hrl").

-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% 非流式接口
%%====================================================================

%% @doc 使用默认 Kimi 配置
generate_content(Opts) when is_map(Opts) ->
    openai_send:generate_content(Opts, default_config()).

%% @doc 使用自定义配置 (如切换模型)
generate_content(Opts, Config) when is_map(Opts), is_map(Config) ->
    openai_send:generate_content(Opts, Config).

%%====================================================================
%% 流式接口
%%====================================================================

%% @doc 流式请求 — Callback 模式
stream_content(Opts, Callback) when is_map(Opts), is_function(Callback, 1) ->
    openai_send:stream_content(Opts, default_config(), Callback).

%% @doc 流式请求 — 收集全部文本
stream_collect(Opts) when is_map(Opts) ->
    openai_send:stream_collect(Opts, default_config()).

%%====================================================================
%% 配置
%%====================================================================

%% @doc Kimi (Moonshot) 默认配置
default_config() ->
    #{
        api_url    => ?KIMI_API_URL,
        api_key    => ?KIMI_API_KEY,
        model      => ?KIMI_MODEL,
        log_prefix => <<"kimi">>
    }.
