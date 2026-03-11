%%%-------------------------------------------------------------------
%% @doc AI 发送行为规范 (Behavior)
%%
%% 所有 AI 提供商的 _send 模块必须实现此行为规范。
%% 定义了统一的 AI 请求接口，确保各提供商可互换使用。
%%
%% 实现模块:
%%   openai_send   — OpenAI (Chat Completions)
%%   deepseek_send — DeepSeek (OpenAI 兼容)
%%   doubao_send   — 豆包/火山方舟 (OpenAI 兼容)
%%   glm_send      — 智谱 GLM (OpenAI 兼容)
%%   kimi_send     — 月之暗面 Kimi (OpenAI 兼容)
%%   qianwen_send  — 通义千问 (OpenAI 兼容)
%%
%% 使用示例:
%%   Module = openai_send,   %% 或 deepseek_send / doubao_send
%%   Module:generate_content(#{prompt => <<"你好"/utf8>>}).
%% @end
%%%-------------------------------------------------------------------

-module(ai_send_behavior).

%% =====================================================================
%% 回调函数定义
%% =====================================================================

%% @doc 返回默认配置
%%
%% 配置 Map 通常包含:
%%   api_url    => binary()  — API 基础 URL
%%   api_key    => binary()  — API 密钥
%%   model      => binary()  — 模型名称
%%   log_prefix => binary()  — 日志前缀
-callback default_config() -> Config :: map().

%% @doc 非流式生成 (使用默认配置)
%%
%% Opts 常用字段:
%%   prompt             => binary()          — 用户消息 (必填)
%%   system_instruction => binary()          — 系统指令 (可选)
%%   messages           => [{atom(),binary}] — 多轮对话 (可选, 优先于 prompt)
%%   response_format    => map()             — 完整的 response_format 结构 (可选)
%%                                              openai_send:build_response_format(Schema)
%%   temperature        => float()           — 随机性 0~2 (可选)
%%
%% 返回:
%%   {ok, binary()}     — 文本模式: 返回 AI 回复文本
%%   {ok, map()}        — JSON 模式: 返回解析后的 Map
%%   {error, term()}    — 请求失败
-callback generate_content(Opts :: map()) ->
    {ok, binary() | map()} | {error, term()}.

%% @doc 流式生成 — Callback 模式
%%
%% 实时接收 SSE 事件, 适用于逐字输出等场景。
%%
%% Callback :: fun(Event) -> any()
%%   Event = #{type => data, data => map()}   — 收到一个数据块
%%         | #{type => done}                  — 流结束
%%         | #{type => error, reason => term()} — 出错
-callback stream_content(Opts :: map(), Callback :: fun((map()) -> any())) ->
    ok | {error, term()}.

%% @doc 流式生成 — 收集全部文本
%%
%% 内部使用流式请求, 但自动拼接所有文本块, 返回完整结果。
%% 兼顾流式的低首字延迟和非流式的简单返回值。
-callback stream_collect(Opts :: map()) ->
    {ok, binary()} | {error, term()}.




