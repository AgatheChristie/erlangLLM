%%%-------------------------------------------------------------------
%% @doc babysdk public API
%% @end
%%%-------------------------------------------------------------------

-module(babysdk_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    babysdk_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
