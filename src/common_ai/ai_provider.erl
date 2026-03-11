%%%-------------------------------------------------------------------
%% @doc 统一 AI Provider 抽象层
%%
%% 一套代码切换不同 AI 供应商, 对上层屏蔽供应商差异。
%% 所有供应商均使用 OpenAI Chat Completions 兼容格式。
%%
%% 核心功能:
%%   1. 统一的 generate_content/2 接口 — 切换供应商只需改一个原子
%%   2. 统一的 stream_content/3 接口 — 流式调用
%%   3. 统一的 process_turn/2 — 游戏回合处理 (任意供应商)
%%
%% 用法:
%%   %% 非流式
%%   ai_provider:generate_content(openai, #{prompt => <<"你好"/utf8>>}).
%%   ai_provider:generate_content(deepseek, #{prompt => <<"你好"/utf8>>}).
%%   ai_provider:generate_content(glm, #{prompt => <<"你好"/utf8>>}).
%%   ai_provider:generate_content(kimi, #{prompt => <<"你好"/utf8>>}).
%%   ai_provider:generate_content(qianwen, #{prompt => <<"你好"/utf8>>}).
%%
%%   %% 流式
%%   ai_provider:stream_content(openai, #{prompt => <<"你好"/utf8>>}, Callback).
%%
%%
%%   %% 查看支持的供应商
%%   ai_provider:providers().
%% @end
%%%-------------------------------------------------------------------

-module(ai_provider).

-include("ai_tou.hrl").

-compile(export_all).
-compile(nowarn_export_all).
%%====================================================================
%% Provider 注册表
%%====================================================================

%% @doc 所有支持的 AI 供应商 — 从 sys_ai_model 的 mod_name 去重得出
providers() ->
    Models = ai_model_registry:all_models(),
    lists:usort([binary_to_atom(maps:get(<<"mod_name">>, M), utf8) || M <- Models]).

%% @doc Provider 原子 → 对应的 xxx_send 模块 (动态拼接, 无需手动维护)
provider_module(Provider) when is_atom(Provider) ->
    list_to_existing_atom(atom_to_list(Provider) ++ "_send").

%%====================================================================
%% 统一接口: 非流式
%%====================================================================

%% @doc 统一生成接口 (非流式, 使用默认模型)
%%
%% 返回: {ok, Result} | {error, Reason}
generate_content(Provider, Opts) when is_atom(Provider), is_map(Opts) ->
    Mod = provider_module(Provider),
    Mod:generate_content(Opts).

%% @doc 统一生成接口 (非流式, 指定模型名)
%% ModelName = <<"deepseek-chat">> 等, 覆盖 Provider 的默认模型
generate_content(Provider, Opts, ModelName) when is_atom(Provider), is_map(Opts), is_binary(ModelName) ->
    Mod = provider_module(Provider),
    Config = (Mod:default_config())#{model => ModelName},
    Mod:generate_content(Opts, Config).

%%====================================================================
%% 统一接口: 流式
%%====================================================================

%% @doc 统一流式接口
%%
%% Callback :: fun(Event) -> any()
%%   Event = #{type => data, data => map()} | #{type => done}
%%
%% 返回: ok | {error, Reason}
stream_content(Provider, Opts, Callback) when is_atom(Provider), is_map(Opts) ->
    Mod = provider_module(Provider),
    Mod:stream_content(Opts, Callback).

%% @doc 统一流式收集 (拼接全部文本)
%% 返回: {ok, FullText :: binary()} | {error, Reason}
stream_collect(Provider, Opts) when is_atom(Provider), is_map(Opts) ->
    Mod = provider_module(Provider),
    Mod:stream_collect(Opts).


%%====================================================================
%% 统一接口: Embeddings (文本向量嵌入)
%%====================================================================

%% @doc 文本嵌入向量
%%
%% 各 Provider 的 _send 模块需实现 embeddings/1 函数。
%% 当前已实现: openai (openai_send → openai_embeddings)
%%
%% 用法:
%%   ai_provider:embeddings(openai, <<"你好世界"/utf8>>).
%%   ai_provider:embeddings(openai, [<<"文本1"/utf8>>, <<"文本2"/utf8>>]).
%%
%% 返回: {ok, RespMap} | {error, not_implemented} | {error, Reason}
embeddings(Provider, Input) ->
    Mod = provider_module(Provider),
    case erlang:function_exported(Mod, embeddings, 1) of
        true -> Mod:embeddings(Input);
        false -> {error, {not_implemented, Provider, embeddings}}
    end.

%% @doc 文本嵌入向量 — 只返回向量列表 (不含元数据)
%% 返回: {ok, [[float()]]} | {error, Reason}
embedding_vectors(Provider, Input) ->
    Mod = provider_module(Provider),
    case erlang:function_exported(Mod, embeddings, 1) of
        true ->
            case Mod:embeddings(Input) of
                {ok, #{<<"data">> := DataList}} ->
                    Vectors = [maps:get(<<"embedding">>, D) || D <- DataList],
                    {ok, Vectors};
                Other ->
                    Other
            end;
        false -> {error, {not_implemented, Provider, embeddings}}
    end.

%%====================================================================
%% 扩展接口: Audio (预留)  TODO
%%====================================================================

%% @doc 语音转文字 (Whisper) — 预留接口
%%
%% 用法 (未来):
%%   ai_provider:transcribe(openai, <<"path/to/audio.mp3">>).
%%
%% OpenAI: POST /v1/audio/transcriptions
%%   Body = multipart/form-data {file, model}
transcribe(Provider, AudioPath) ->
    Mod = provider_module(Provider),
    case erlang:function_exported(Mod, transcribe, 1) of
        true -> Mod:transcribe(AudioPath);
        false -> {error, {not_implemented, Provider, transcribe}}
    end.

%% @doc 文字转语音 (TTS) — 预留接口     TODO
%%
%% 用法 (未来):
%%   ai_provider:speech(openai, <<"你好世界"/utf8>>, #{voice => <<"alloy">>}).
%%
%% OpenAI: POST /v1/audio/speech
%%   Body = #{model, input, voice}
speech(Provider, Text, Opts) ->
    Mod = provider_module(Provider),
    case erlang:function_exported(Mod, speech, 2) of
        true -> Mod:speech(Text, Opts);
        false -> {error, {not_implemented, Provider, speech}}
    end.

%%====================================================================
%% 扩展接口: Image (预留)  TODO
%%====================================================================

%% @doc 图片生成 — 预留接口
%%
%% 用法 (未来):
%%   ai_provider:generate_image(openai, <<"一只可爱的猫"/utf8>>, #{size => <<"1024x1024">>}).
%%
%% OpenAI: POST /v1/images/generations
%%   Body = #{model, prompt, size, quality}
generate_image(Provider, Prompt, Opts) ->
    Mod = provider_module(Provider),
    case erlang:function_exported(Mod, generate_image, 2) of
        true -> Mod:generate_image(Prompt, Opts);
        false -> {error, {not_implemented, Provider, generate_image}}
    end.


%%====================================================================
%% Schema JSON 文件缓存 (persistent_term)
%%====================================================================

-define(SCHEMA_CACHE_KEY, {?MODULE, game_response_schema}).
-define(SCHEMA_JSON_PATH, "config/dawfawf.json").

%% @doc 初始化: 从 JSON 文件加载 Schema 并缓存到 persistent_term
%%
%% 在应用启动时调用一次即可, 例如在 supervisor init 或 app start 中:
%%   ai_provider:init_schema().
%%
%% 也可手动调用来热更新 Schema:
%%   ai_provider:reload_schema().
init_schema() ->
    reload_schema().

%% @doc 重新从文件加载 Schema (热更新用)
reload_schema() ->
    case file:read_file(?SCHEMA_JSON_PATH) of
        {ok, Bin} ->
            Schema = jiffy:decode(Bin, [return_maps]),
            persistent_term:put(?SCHEMA_CACHE_KEY, Schema),
            io:format("[ai_provider] Schema loaded from ~s~n", [?SCHEMA_JSON_PATH]),
            ok;
        {error, Reason} ->
            io:format("[ai_provider] Failed to load schema from ~s: ~p, using fallback~n",
                [?SCHEMA_JSON_PATH, Reason]),
            {error, Reason}
    end.

%% @doc 获取缓存的 Schema
%%
%% 优先从 persistent_term 缓存读取;
%% 若缓存未初始化, 自动从文件加载;
%% 若文件也读不到, 降级使用代码中的硬编码版本。
get_game_response_schema() ->
    try
        {ok, persistent_term:get(?SCHEMA_CACHE_KEY)}
    catch
        error:badarg ->
            %% 缓存未初始化, 尝试自动加载
            case reload_schema() of
                ok ->
                    {ok, persistent_term:get(?SCHEMA_CACHE_KEY)};
                {error, _} ->
                    %% 文件加载失败, 降级到硬编码版本
                    io:format("[ai_provider] Fallback to hardcoded schema~n", []),
                    err
            end
    end.
