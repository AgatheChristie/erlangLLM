%%%-------------------------------------------------------------------
%%% @author taiqi
%%% @copyright (C) 2022, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. 4月 2022 11:29
%%%-------------------------------------------------------------------
-ifndef(LOGGER_HRL__).
-define(LOGGER_HRL__, 1).

-define(log_color_none   , "\e[m").
-define(log_color_red    , "\e[1m\e[31m").
-define(log_color_yellow , "\e[1m\e[33m").
-define(log_color_green  , "\e[0m\e[32m").
-define(log_color_black  , "\e[0;30m").
-define(log_color_blue   , "\e[0;34m").
-define(log_color_purple , "\e[0;35m").
-define(log_color_cyan   , "\e[0;36m").
-define(log_color_white  , "\e[0;37m").






-ifdef(DEBUG_LOG).
-define(DEBUG(Format, Args),
    logger:debug(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-else.
-define(DEBUG(Format, Args), ok).
-endif.

-ifdef(DEBUG_LOG).
-define(INFO(Format, Args),
    logger:info(lists:concat([?log_color_blue, Format,?log_color_none]), Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-else.
-define(INFO(Format, Args),
    logger:info(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-endif.
-ifdef(DEBUG_LOG).
-define(WARNING_MSG(Format, Args),
    logger:info(lists:concat([?log_color_blue, Format,?log_color_none]), Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-else.
-define(WARNING_MSG(Format, Args),
    logger:info(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-endif.

-ifdef(DEBUG_LOG).
-define(ERROR(Format, Args),
    logger:error(lists:concat([?log_color_red, Format,?log_color_none]), Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-else.
-define(ERROR(Format, Args),
    logger:error(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-endif.


-ifdef(DEBUG_LOG).
-define(C2SINFO(Format, Args),
    logger:info(lists:concat([?log_color_purple, Format,?log_color_none]), Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-else.
-define(C2SINFO(Format, Args),
    logger:info(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-endif.

-ifdef(DEBUG_LOG).
-define(S2CINFO(Format, Args),
    logger:info(lists:concat([?log_color_green, Format,?log_color_none]), Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-else.
-define(S2CINFO(Format, Args),
    logger:info(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
-endif.




%%-define(INFO(Format, Args),
%%    logger:info(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).
%%
%%-define(ERROR(Format, Args),
%%    logger:error(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).

-define(DEBUG(Format), ?DEBUG(Format, [])).
-define(INFO(Format), ?INFO(Format, [])).
-define(ERROR(Format), ?ERROR(Format, [])).

-define(ROBOT_DEBUG(Format, Args),
    logger:debug(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).

-define(ROBOT_DEBUG(Format), ?ROBOT_DEBUG(Format, [])).

-define(ROBOT_ERROR(Format, Args),
    logger:error(Format, Args, #{module => ?MODULE, line => ?LINE, domain => [game]})).

-define(ROBOT_ERROR(Format), ?ROBOT_ERROR(Format, [])).


-ifdef(COMBAT_LOG).
-define(COMBAT_DEBUG(Format, Args),
    logger:info(lists:concat([?log_color_blue, Format,?log_color_none]), Args, #{module => ?MODULE, line => ?LINE, domain => [game]})
).
-else.
-define(COMBAT_DEBUG(Format, Args), ok).
-endif.

-define(COMBAT_DEBUG(Format), ?COMBAT_DEBUG(Format, [])).

-endif.


