%% 查看WSL IP地址  wsl hostname -I

-ifndef(COMMON_H_H_).
-define(COMMON_H_H_, 1).

-include("logger.hrl").


-define(CONFIG_NUMBER,    100000000).

-define(HTTP_CONNECT_TIMEOUT, 1500000).%% 给 15 分钟
-define(HTTP_RECV_TIMEOUT, 1200000).  %% AI 生成可能较慢，给 20 分钟

%%=====================HS===========================

-define(C2SERR(Code), throw({error, Code})).
-define(IS_C2SERR(R), {error, R}).
%%=====================HS===========================

%% 获取秒数值或毫秒数值
-define(WEEK_S, 604800).
-define(DAY_S, 86400).
-define(HOUR_S, 3600).
-define(HALF_HOUR_S, 1800).
-define(MINU_S, 60).
-define(WEEK_S(N), (?WEEK_S * (N))).
-define(DAY_S(N), (?DAY_S * (N))).
-define(HOUR_S(N), (?HOUR_S * (N))).
-define(MINU_S(N), (?MINU_S * (N))).

-define(NONE, none).

%% @doc 一天多少分钟
-define(DAY_MIN, 1440).

-define(WEEK_MS, 604800000).
-define(DAY_MS, 86400000).
-define(HOUR_MS, 3600000).
-define(HALF_HOUR_MS, 1800000).
-define(MINU_MS, 60000).
-define(SEC_MS, 1000).
-define(WEEK_MS(N), (?WEEK_MS * (N))).
-define(DAY_MS(N), (?DAY_MS * (N))).
-define(HOUR_MS(N), (?HOUR_MS * (N))).
-define(MINU_MS(N), (?MINU_MS * (N))).
-define(SEC_MS(N), (?SEC_MS * (N))).

-define(FALSE, 0).
-define(TRUE, 1).
-define(UNDEF, undefined).
-define(NULL, null).


-define(LOGIN_HANDLE, 0).
-define(LEVEL_UP_HANDLE, 1).

-define(ONE_HUNDRED, 100).
-define(TEN_THOUSAND, 10000).


%% 语言翻译，返回给玩家的文本信息需要经过此宏的转换 <<("青云法袍")/utf8>>
-ifndef(LANGUAGE).
-define(T(TEXT), <<(TEXT)/utf8>>).
-else.
-define(T(Text), <<(TEXT)/utf8>>).
-endif.


-define(T_UNICODE(Text), unicode:characters_to_binary(Text, utf8)).

%% 带catch的gen_server:call/2，返回{error, timeout} | {error, noproc} | {error, term()} | term() | {exit, normal}
%% 此宏只会返回简略信息，如果需要获得更详细的信息，请使用以下方式自行处理:
-define(CALL(CallPid, CallRequest, TimeOut),
    try
        gen_server:call(CallPid, CallRequest, TimeOut)
    catch T:E:S ->
        ?ERROR("call_pid:~p req:~p timeout:~p get_stacktrace:~p, T: ~p, E:~p~n", [CallPid, CallRequest, TimeOut, S, T, E]),
        {error, element(1, E)}
    end
).

-define(CALL(CallPid, CallRequest), ?CALL(CallPid, CallRequest, 5000)).

-define(CATCH(Fun, Default), (
        try Fun
        catch T:E:R ->
            io:format("~p:~p:~p~n", [T, E, R]),
            Default
        end
)).
-define(CATCH(Fun), ?CATCH(Fun, ok)).

-define(CATCH_INFO(Fun, Default), (
        try Fun
        catch T:E:R ->
            ?INFO("~p:~p:~p~n", [T, E, R]),
            Default
        end
)).
-define(CATCH_INFO(Fun), ?CATCH_INFO(Fun, ok)).

%% @doc 执行一个方法，如果报错，返回默认值
-define(CATCH_ERROR(Fun, Default), (
        try Fun
        catch T:E:R ->
            ?ERROR("~p:~p:~p~n", [T, E, R]),
            Default
        end
)).
-define(CATCH_ERROR(Fun), ?CATCH_ERROR(Fun, ok)).

-define(DEFAULT(_Data, _Default),     (
        case _Data of
            undefined ->
                _Default;
            false ->
                _Default;
            error ->
                _Default;
            _RetData ->
                _RetData
        end
)).

-define(IF(TrueOrFalse, A, B),
    case TrueOrFalse of
        true -> A;
        false -> B
    end
).

-define(IF(TrueOrFalse, A),
    case TrueOrFalse of
        true -> A;
        false -> ok
    end
).

-define(ASSERT(TrueOrFalse, ECode),
    case TrueOrFalse of
        true -> ignore;
        false -> ?C2SERR(ECode)
    end
).


-define(MODULE_LINE, {?MODULE, ?LINE}).


-define(ASSERT_MAP(Data),
    case is_map(Data) of
        true -> Data;
        false -> ?C2SERR(1010009)
    end
).

-define(ASSERT_MAP(Data, ECode),
    case is_map(Data) of
        true -> Data;
        false -> ?C2SERR(ECode)
    end
).

-define(ASSERT_TUPLE(Data, ECode),
    case is_tuple(Data) of
        true -> Data;
        false -> ?C2SERR(ECode)
    end
).


-define(ASSERT_RECORD(Data, RecordName),
    case is_record(Data, RecordName) of
        true -> Data;
        false -> ?C2SERR(1010009)
    end
).

-define(ASSERT_RECORD(Data, RecordName, ECode),
    case is_record(Data, RecordName) of
        true -> Data;
        false -> ?C2SERR(ECode)
    end
).

%% 将record转换成tuplelist
-define(RECORD_TO_TUPLE_LIST(Rec, Ref), lists:zip([record_name | record_info(fields, Rec)], tuple_to_list(Ref))).

-define(_U(Text), Text).


-define(CALL_TIMEOUT, 5000).

-define(PROB_FULL, 10000).


-endif.
