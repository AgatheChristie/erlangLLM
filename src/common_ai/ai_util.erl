
-module(ai_util).
-include("common.hrl").

-compile(export_all).
-compile(nowarn_export_all).



%% @doc 生成日志时间戳 (月日_时分秒)
log_timestamp() ->
    {{_Y, Mon, Day}, {H, M, S}} = calendar:local_time(),
    lists:flatten(io_lib:format("~2..0w~2..0w_~2..0w~2..0w~2..0w", [Mon, Day, H, M, S])).
