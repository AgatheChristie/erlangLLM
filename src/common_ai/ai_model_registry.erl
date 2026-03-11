%%%-------------------------------------------------------------------
%% @doc AI 模型注册表 — 从 sys_ai_model 编译数据加载
%%
%% 模型数据以 map 列表形式缓存在 persistent_term 中。
%% 每个模型: #{<<"id">> => N, <<"model">> => Bin, <<"desc">> => Bin, <<"mod_name">> => Bin}
%%
%% 用法:
%%   ai_model_registry:init_models().          %% 启动时加载
%%   ai_model_registry:reload_models().        %% 热更新(重新编译 sys_ai_model 后调用)
%%   ai_model_registry:all_models().           %% 获取所有模型 [map()]
%%   ai_model_registry:get_model(10001).       %% 按 ID 查找
%%   ai_model_registry:id_to_provider(10001).  %% -> doubao
%%
%% @end
%%%-------------------------------------------------------------------

-module(ai_model_registry).
-include("common.hrl").

-compile(export_all).
-compile(nowarn_export_all).

-define(MODELS_CACHE_KEY, {?MODULE, ai_models}).

%%====================================================================
%% 初始化 / 热更新
%%====================================================================

%% @doc 启动时调用: 从 sys_ai_model 加载模型列表并缓存
init_models() ->
    reload_models().

%% @doc 重新加载模型列表 (热更新: 重新编译 sys_ai_model 后调用)
reload_models() ->
    Models = sys_ai_model:all_maps(),
    persistent_term:put(?MODELS_CACHE_KEY, Models),
    ?INFO("[ai_model_registry] Loaded ~p models from sys_ai_model~n",
          [length(Models)]),
    ok.

%%====================================================================
%% 模型列表
%%====================================================================

%% @doc 所有可用模型列表 -> [map()]
all_models() ->
    try
        persistent_term:get(?MODELS_CACHE_KEY)
    catch
        error:badarg ->
            reload_models(),
            persistent_term:get(?MODELS_CACHE_KEY)
    end.

%%====================================================================
%% 查询接口
%%====================================================================

%% @doc 按 ID 查找模型 -> {ok, map()} | error
get_model(ModelId) when is_integer(ModelId) ->
    case [M || M = #{<<"id">> := Id} <- all_models(), Id =:= ModelId] of
        [Model | _] -> {ok, Model};
        []          -> error
    end;
get_model(_) -> error.

%% @doc 根据 model_id 获取 Provider 原子
%% 例: id_to_provider(10001) -> doubao
id_to_provider(ModelId) when is_integer(ModelId) ->
    case get_model(ModelId) of
        {ok, #{<<"mod_name">> := ModName}} ->
            binary_to_atom(ModName, utf8);
        error ->
            undefined
    end;
id_to_provider(_) -> undefined.


%% @doc 同时获取 Provider 和 ModelName
get_provider_and_model(ModelId) ->
    case get_model(ModelId) of
        {ok, #{<<"model">> := ModelName, <<"mod_name">> := ModName}} ->
            Provider = binary_to_atom(ModName, utf8),
            {ok, Provider, ModelName};
        error ->
            error
    end.

%%====================================================================
%% 默认模型
%%====================================================================

default_model_id() -> 30005.

%%====================================================================
%% 模型管理 (运行时可切换)
%%====================================================================

%% ETS 表名 (存储当前配置)
-define(ETS_AI_CONFIG, ets_ai_config).

%% @doc 获取当前选中的 model_id
get_model_id() ->
    ensure_config_ets(),
    case ets:lookup(?ETS_AI_CONFIG, current_model_id) of
        [{_, ModelId}] -> ModelId;
        []             -> ai_model_registry:default_model_id()
    end.

%% @doc 切换模型 (运行时生效)
%% 示例: meili3_adapter:set_model(20001).
set_model(ModelId) when is_integer(ModelId) ->
    case ai_model_registry:get_model(ModelId) of
        {ok, #{<<"model">> := Model}} ->
            Provider = ai_model_registry:id_to_provider(ModelId),
            ensure_config_ets(),
            ets:insert(?ETS_AI_CONFIG, {current_model_id, ModelId}),
            ?INFO("[adapter] AI 模型已切换为: ~p (~ts, ~p)~n", [ModelId, Model, Provider]),
            ok;
        error ->
            {error, {unknown_model_id, ModelId}}
    end.

%%====================================================================
%% 内部: ETS 配置表
%%====================================================================
ensure_config_ets() ->
    case ets:info(?ETS_AI_CONFIG) of
        undefined ->
            ets:new(?ETS_AI_CONFIG, [set, public, named_table]),
            ok;
        _ ->
            ok
    end.










