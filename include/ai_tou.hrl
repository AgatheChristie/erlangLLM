
%%====================================================================
%% 测试用业务相关
%%====================================================================

-define(AI_STREAM_CONTENT,  1).  %% 流式普通
-define(AI_STREAM_COLLECT, 2).   %% 流式收集


%% 这三个消息是推送给WS的
%%ai_stream_done  ai_stream_chunk ai_stream_error

%% @doc text 字段完成时，立即通知前端流结束 (仅发一次)
%% 这让前端能在 AI 还在生成 choices/stats 时就显示"生成选项中..."
-define(DIC_S_TEXT_DONE_SENT, stream_text_done_sent).   %% bool

-define(DIC_S_JSON_BUF, stream_json_buf).   %% <<>>



%% SentLen = 已推送的文本字节数 (避免重复发送)
-define(DIC_S_TEXT_SENT, stream_text_sent).   %% int

%%====================================================================
%% Opts 字段名宏 — 统一管理, 避免拼写错误
%%====================================================================

%% ── 必填 ──────────────────────────────────────────────────────────
-define(OPT_PROMPT,              prompt).              %% binary()  — 用户消息
-define(OPT_SYSTEM_INSTRUCTION,  system_instruction).  %% binary()  — system 角色指令

%% ── 消息 ──────────────────────────────────────────────────────────
-define(OPT_MESSAGES,            messages).             %% [{atom(), binary()}] — 多轮对话 (优先于 prompt)

%% ── 结构化输出 ────────────────────────────────────────────────────
-define(OPT_RESPONSE_FORMAT,     response_format).     %% map()     — 完整的 response_format (OpenAI 格式)
-define(OPT_JSON_MODE,           json_mode).            %% boolean() — JSON 模式

%% ── 可选生成参数 ──────────────────────────────────────────────────
-define(OPT_MAX_OUTPUT_TOKENS, max_output_tokens).         %% pos_integer() — 最大回复 token 数 (Responses API)
-define(OPT_MAX_COMPLETION_TOKENS, ?OPT_MAX_OUTPUT_TOKENS).
%%【AI 大模型核心高频义】温度系数、温度参数
%%这是你对接 OpenAI/Claude/Gemini API 时的核心超参数，也是你当前场景最需要关注的释义。
%%核心含义：控制大模型输出内容的随机性、创造性与发散度，是 LLM 最常用的调优参数。
%%取值规则：主流模型取值范围为 0~2，部分模型支持更高上限。
%%取值趋近 0：输出越确定、越保守、聚焦事实，重复度高，适合代码生成、固定规则的游戏逻辑、精准问答。
%%取值 0.6~0.9：平衡创造性与稳定性，是游戏文案、剧情生成、对话设计的黄金区间。
%%取值≥1：输出越随机、发散、有创造性，容易出现天马行空的内容，适合灵感发散、创意类创作。
-define(OPT_TEMPERATURE,         temperature).          %% float()   — 随机性 0.0 ~ 2.0
-define(OPT_TOP_P,               top_p).                %% float()   — 核采样 0.0 ~ 1.0
-define(OPT_STOP,                stop).                 %% [binary()] — 停止词列表
-define(OPT_SEED,                seed).                 %% integer() — 固定随机种子

%% ── 内部控制 ──────────────────────────────────────────────────────
-define(OPT_STREAM,              stream).               %% boolean() — 是否流式 (内部使用)





%%====================================================================
%% 豆包 (火山方舟) API 配置
%%
%% 豆包同时支持两种 API:
%%   1. Chat Completions (OpenAI 兼容) — /api/v3/chat/completions ← 本项目使用
%%   2. Responses API (豆包特有)       — /api/v3/responses
%%
%% 使用 Chat Completions 格式可与 OpenAI/DeepSeek 共用 openai_send 模块。
%%
%% 文档: https://www.volcengine.com/docs/82379/1569618
%%====================================================================

%% 用量查询
%% https://console.volcengine.com/finance/resource-package
%%
%% https://console.volcengine.com/ark/region:ark+cn-beijing/usageTracking?




-define(DOUBAO_API_KEY, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(DOUBAO_MODEL,   <<"doubao-seed-1-8-251228">>).
-define(DOUBAO_API_URL, <<"https://ark.cn-beijing.volces.com/api/v3">>).


%%====================================================================
%% OPENAI API 配置  openai_send 会自动拼上 /responses
%%====================================================================


-define(OPENAI_API_KEY, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).   %% ME
-define(OPENAI_MODEL,   <<"gpt-5.2">>).
-define(OPENAI_API_URL, <<"https://aaaaaaaaaa.com/v1">>).


-define(OPENAI_API_KEY_MY, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(OPENAI_MODEL_MY,   <<"gpt-5.2">>).
-define(OPENAI_API_URL_MY, <<"https://api.openai.com/v1">>).

%%-define(OPENAI_API_URL_MY, <<"https://api.openai.com/v1/responses">>).



%%====================================================================
%% DeepSeek API 配置
%%
%% DeepSeek 完全兼容 OpenAI Chat Completions API 格式
%% 文档: https://platform.deepseek.com/api-docs
%%
%% 可用模型:
%%   deepseek-chat      — 通用对话模型 (DeepSeek-V3)
%%   deepseek-reasoner  — 推理增强模型 (DeepSeek-R1)
%%====================================================================

-define(DEEPSEEK_API_KEY, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(DEEPSEEK_MODEL,   <<"deepseek-reasoner">>).
-define(DEEPSEEK_API_URL, <<"https://api.deepseek.com/v1">>).



%%====================================================================
%% 月之暗面 Kimi (Moonshot) API 配置
%%
%% Kimi 兼容 OpenAI Chat Completions API 格式
%% 文档: https://platform.moonshot.cn/docs
%%
%% 可用模型:
%%   moonshot-v1-8k    — 8K 上下文
%%   moonshot-v1-32k   — 32K 上下文
%%   moonshot-v1-128k  — 128K 上下文
%%====================================================================

-define(KIMI_API_KEY, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(KIMI_MODEL,   <<"moonshot-v1-8k">>).
-define(KIMI_API_URL, <<"https://api.moonshot.cn/v1">>).



%%====================================================================
%% 智谱 GLM API 配置
%%
%% 智谱 GLM 兼容 OpenAI Chat Completions API 格式
%% 文档: https://open.bigmodel.cn/dev/api
%%
%% 可用模型:
%%   glm-4-flash  — 免费高速模型
%%   glm-4-plus   — 高质量模型
%%   glm-4        — 标准模型
%%====================================================================

-define(GLM_API_KEY, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(GLM_MODEL,   <<"glm-4-flash">>).
-define(GLM_API_URL, <<"https://open.bigmodel.cn/api/paas/v4">>).



%%====================================================================
%% 通义千问 (Qianwen) API 配置
%%
%% 通义千问兼容 OpenAI Chat Completions API 格式
%% 文档: https://help.aliyun.com/zh/model-studio/getting-started/
%%
%% 可用模型:
%%   qwen-plus       — 性能与效果均衡
%%   qwen-turbo      — 高速低成本
%%   qwen-max        — 最强效果
%%   qwen-long       — 超长上下文
%%====================================================================

-define(QIANWEN_API_KEY, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(QIANWEN_MODEL,   <<"qwen-plus">>).
-define(QIANWEN_API_URL, <<"https://dashscope.aliyuncs.com/compatible-mode/v1">>).


%%====================================================================
%% 豆包 Seedream 图片生成 API 配置
%%
%% 使用豆包 Seedream 3.0 文生图模型
%% 端点: POST /v1/doubao/rawproxy/api/v3/images/generations
%% 返回: {"data": [{"url": "..."}]}
%%====================================================================

-define(DOUBAO_IMAGE_API_KEY, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(DOUBAO_IMAGE_MODEL,   <<"Doubao-Seedream-3.0-t2i">>).
-define(DOUBAO_IMAGE_API_URL, <<"https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(DOUBAO_IMAGE_SIZE,    <<"1024x1024">>).
-define(FUSHENG_IMAGE_IDLE_SECONDS, 10).


%%====================================================================
%% LLM 图片生成配置 (chat/completions + 图片输出模型)
%%
%% 使用具备图片输出能力的 LLM (如 gpt-4o / gpt-image-1)
%% 通过 chat/completions 端点, 模型在文本回复中返回 base64 图片
%% 默认复用 OpenAI 代理地址和密钥, 可独立配置为不同的提供商
%%====================================================================

-define(LLM_IMAGE_API_KEY, ?OPENAI_API_KEY_MY).
-define(LLM_IMAGE_MODEL,   <<"gpt-4o">>).
-define(LLM_IMAGE_API_URL, ?OPENAI_API_URL_MY).