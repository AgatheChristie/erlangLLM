%%%-------------------------------------------------------------------
%% @doc 豆包 (火山方舟) API 客户端 — 复用 OpenAI 兼容格式
%%
%% 豆包 Chat Completions 端点完全兼容 OpenAI 格式,
%% 因此本模块只是 openai_send 的薄封装 (与 deepseek_send 同理)。
%%
%% 对比旧版 meili.erl:
%%   旧: POST /api/v3/responses   (Responses API, 豆包特有格式)
%%   新: POST /api/v3/chat/completions (OpenAI 兼容格式) ← 本模块
%%
%% 调用方式:
%%   doubao_send:generate_content(#{prompt => <<"你好"/utf8>>}).
%%   doubao_send:generate_content(#{prompt => <<"你好"/utf8>>,
%%       response_format => openai_send:build_response_format(Schema)}).
%%
%% 流式:
%%   doubao_send:stream_content(#{prompt => <<"你好"/utf8>>}, Callback).
%%   doubao_send:stream_collect(#{prompt => <<"你好"/utf8>>}).
%% @end
%%%-------------------------------------------------------------------

-module(doubao_send).
-behaviour(ai_send_behavior).
-include("common.hrl").
-include("ai_tou.hrl").

-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% 非流式接口
%%====================================================================

%% @doc 使用默认豆包配置
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

%% @doc 豆包默认配置
default_config() ->
    #{
        api_url    => ?DOUBAO_API_URL,
        api_key    => ?DOUBAO_API_KEY,
        model      => ?DOUBAO_MODEL,
        log_prefix => <<"doubao">>
    }.
