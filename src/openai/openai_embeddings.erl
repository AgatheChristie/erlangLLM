%%%-------------------------------------------------------------------
%% @doc OpenAI Embeddings API — 文本向量嵌入
%%
%% 端点: POST /v1/embeddings
%% 文档: https://platform.openai.com/docs/api-reference/embeddings
%%
%% 架构:
%%   openai_embeddings = Embeddings 请求构建 + 发送 + 响应解析
%%   openai_send       = Chat/Responses 请求 (通过 embeddings/1 委托到本模块)
%%   ai_provider       = 统一抽象层 (embeddings/2 → openai_send → 本模块)
%%
%% 调用方式:
%%   %% 通过 ai_provider 统一接口
%%   ai_provider:embeddings(openai, <<"你好世界"/utf8>>).
%%
%%   %% 直接调用
%%   openai_embeddings:embeddings(<<"Hello world">>).
%%   openai_embeddings:embeddings([<<"文本1"/utf8>>, <<"文本2"/utf8>>]).
%%   openai_embeddings:embeddings(<<"Hello">>, #{dimensions => 256}).
%% @end
%%%-------------------------------------------------------------------

-module(openai_embeddings).
-include("common.hrl").
-include("ai_tou.hrl").
-compile(export_all).
-compile(nowarn_export_all).

%%====================================================================
%% Embeddings API
%%====================================================================

%% @doc 文本转向量 — 默认参数
%% Input: binary() 单文本 | [binary()] 批量文本
%% 返回: {ok, RespMap} | {error, Reason}
embeddings(Input) ->
    embeddings(Input, #{}).

%% @doc 文本转向量 — 可选参数
%% Opts:
%%   model           => binary()  — 模型, 默认 text-embedding-3-small
%%   dimensions      => integer() — 输出维度 (仅 v3 系列), 如 256/512/1536
%%   encoding_format => binary()  — 返回格式: <<"float">> | <<"base64">>
embeddings(Input, Opts) ->
    embeddings(Input, Opts, openai_send:default_config()).

%% @doc 文本转向量 — 完整参数 (支持自定义 Provider Config)
embeddings(Input, Opts, Config) ->
    ApiUrl = maps:get(api_url, Config, ?OPENAI_API_URL),
    ApiKey = maps:get(api_key, Config, ?OPENAI_API_KEY),
    LogPrefix = maps:get(log_prefix, Config, <<"openai">>),

    Url = <<ApiUrl/binary, "/embeddings">>,
    Headers = [
        {<<"Authorization">>, <<"Bearer ", ApiKey/binary>>},
        {<<"Content-Type">>, <<"application/json">>}
    ],

    Body0 = #{
        <<"model">> => maps:get(model, Opts, <<"text-embedding-3-small">>),
%%        <<"model">> => maps:get(model, Opts, <<"m3e">>),
        <<"input">> => Input
    },
    Body1 = maybe_set(<<"dimensions">>, dimensions, Opts, Body0),
    Body2 = maybe_set(<<"encoding_format">>, encoding_format, Opts, Body1),

    Payload = jiffy:encode(Body2),
    case ai_http_client:request(Url, Headers, Payload, #{log_prefix => LogPrefix, enable_log => true}) of
        {ok, RespBody} ->
            {ok, jiffy:decode(RespBody, [return_maps])};
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% 便捷函数
%%====================================================================

%% @doc 文本转向量 — 只返回向量列表 (不含元数据)
%% 返回: {ok, [[float()]]} | {error, Reason}
embedding_vectors(Input) ->
    embedding_vectors(Input, #{}).

embedding_vectors(Input, Opts) ->
    case embeddings(Input, Opts) of
        {ok, #{<<"data">> := DataList}} ->
            Vectors = [maps:get(<<"embedding">>, D) || D <- DataList],
            {ok, Vectors};
        Other ->
            Other
    end.

%% @doc 计算两个向量的余弦相似度
%% 返回: float() 范围 [-1, 1], 越接近 1 表示越相似
cosine_similarity(Vec1, Vec2) when length(Vec1) =:= length(Vec2) ->
    Dot = lists:sum([A * B || {A, B} <- lists:zip(Vec1, Vec2)]),
    Norm1 = math:sqrt(lists:sum([A * A || A <- Vec1])),
    Norm2 = math:sqrt(lists:sum([B * B || B <- Vec2])),
    case Norm1 * Norm2 of
        0.0 -> 0.0;
        Denom -> Dot / Denom
    end.

%%====================================================================
%% 内部函数
%%====================================================================

maybe_set(JsonKey, OptsKey, Opts, Body) ->
    case maps:get(OptsKey, Opts, undefined) of
        undefined -> Body;
        Value -> Body#{JsonKey => Value}
    end.
