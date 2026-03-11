-module(sys_ai_model).


-record(sys_ai_model, {
    id,
    model,
    desc,
    mod_name
}).

-export([get/1, get/2, is_has/1, list/0, to_map/1, all_maps/0]).

%% --- doubao ---
get(10001) -> #sys_ai_model{id = 10001, model = <<"doubao-seed-1-8-251228">>,       desc = <<"字节种子模型 (2025.12)"/utf8>>,            mod_name = <<"doubao">>};
get(10002) -> #sys_ai_model{id = 10002, model = <<"doubao-seed-1-6-251002">>,       desc = <<"字节种子模型 (2025.10)"/utf8>>,            mod_name = <<"doubao">>};
get(10003) -> #sys_ai_model{id = 10003, model = <<"doubao-seed-2-0-pro-260215">>,   desc = <<"字节种子模型 (2026.02)"/utf8>>,            mod_name = <<"doubao">>};
%% --- deepseek ---
get(20001) -> #sys_ai_model{id = 20001, model = <<"deepseek-chat">>,                desc = <<"DeepSeek-V3 通用对话"/utf8>>,              mod_name = <<"deepseek">>};
get(20002) -> #sys_ai_model{id = 20002, model = <<"deepseek-reasoner">>,            desc = <<"DeepSeek-R1 推理模型"/utf8>>,              mod_name = <<"deepseek">>};
%% --- openai ---
get(30001) -> #sys_ai_model{id = 30001, model = <<"gpt-4o">>,                       desc = <<"GPT-4o 多模态旗舰"/utf8>>,                mod_name = <<"openai">>};
get(30002) -> #sys_ai_model{id = 30002, model = <<"gpt-4o-mini">>,                  desc = <<"GPT-4o-mini 轻量"/utf8>>,                 mod_name = <<"openai">>};
get(30003) -> #sys_ai_model{id = 30003, model = <<"gpt-4.1">>,                      desc = <<"gpt-4.1 旗舰"/utf8>>,                     mod_name = <<"openai">>};
get(30004) -> #sys_ai_model{id = 30004, model = <<"gpt-5.1">>,                      desc = <<"gpt-5.1 旗舰"/utf8>>,                     mod_name = <<"openai">>};
get(30005) -> #sys_ai_model{id = 30005, model = <<"gpt-5.2">>,                      desc = <<"gpt-5.2 好旗舰"/utf8>>,                   mod_name = <<"openai">>};
%% --- glm ---
get(50001) -> #sys_ai_model{id = 50001, model = <<"glm-4.7-flash">>,               desc = <<"GLM-4.7 免费模型 200K上下文"/utf8>>,       mod_name = <<"glm">>};
get(50002) -> #sys_ai_model{id = 50002, model = <<"glm-4.7">>,                     desc = <<"GLM-4.7 高智能 200K上下文"/utf8>>,         mod_name = <<"glm">>};
get(50003) -> #sys_ai_model{id = 50003, model = <<"glm-5">>,                       desc = <<"GLM-5 最新旗舰 200K上下文"/utf8>>,         mod_name = <<"glm">>};
%% --- kimi ---
get(60001) -> #sys_ai_model{id = 60001, model = <<"kimi-k2.5">>,                   desc = <<"Kimi K2.5 最新旗舰多模态 256K"/utf8>>,     mod_name = <<"kimi">>};
get(60002) -> #sys_ai_model{id = 60002, model = <<"kimi-k2-turbo-preview">>,       desc = <<"Kimi K2 Turbo 快速 256K"/utf8>>,           mod_name = <<"kimi">>};
get(60003) -> #sys_ai_model{id = 60003, model = <<"kimi-k2-thinking">>,            desc = <<"Kimi K2 深度思考 256K"/utf8>>,              mod_name = <<"kimi">>};
%% --- qianwen ---
get(70001) -> #sys_ai_model{id = 70001, model = <<"qwen-max">>,                    desc = <<"通义千问 Max 最强效果"/utf8>>,              mod_name = <<"qianwen">>};
get(70002) -> #sys_ai_model{id = 70002, model = <<"qwen-plus">>,                   desc = <<"通义千问 Plus 性能均衡"/utf8>>,             mod_name = <<"qianwen">>};
get(70003) -> #sys_ai_model{id = 70003, model = <<"qwen-turbo">>,                  desc = <<"通义千问 Turbo 高速低成本"/utf8>>,          mod_name = <<"qianwen">>};
get(70004) -> #sys_ai_model{id = 70004, model = <<"qwen-long">>,                   desc = <<"通义千问 Long 超长上下文"/utf8>>,            mod_name = <<"qianwen">>};
get(_Id) -> io:format("data not exist:~p", [_Id]), throw({error, 20}).

get(ML, Id) ->
    case catch sys_ai_model:get(Id) of
        #sys_ai_model{} = T -> T;
        _ -> io:format("function data info:~w ~p", [ML, Id]), throw({error, 20})
    end.

is_has(Id) ->
    case lists:member(Id, list()) of
        true -> sys_ai_model:get(Id);
        false -> false
    end.

list() ->
    [10001, 10002, 10003,
     20001, 20002,
     30001, 30002, 30003, 30004, 30005,
     50001, 50002, 50003,
     60001, 60002, 60003,
     70001, 70002, 70003, 70004].

to_map(#sys_ai_model{id = Id, model = Model, desc = Desc, mod_name = ModName}) ->
    #{<<"id">> => Id, <<"model">> => Model, <<"desc">> => Desc, <<"mod_name">> => ModName}.

all_maps() ->
    [to_map(sys_ai_model:get(Id)) || Id <- list()].
