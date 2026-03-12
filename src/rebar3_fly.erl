-module(rebar3_fly).

-export([init/1]).

init(State) ->
    rebar3_fly_prv:init(State).
