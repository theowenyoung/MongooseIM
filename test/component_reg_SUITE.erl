-module(component_reg_SUITE).
-compile([export_all, nowarn_export_all]).

-include_lib("exml/include/exml.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("mongoose.hrl").
-include("external_component.hrl").

all() ->
    [ registering, registering_with_local ].

init_per_suite(C) ->
    {ok, _} = application:ensure_all_started(jid),
    ok = mnesia:create_schema([node()]),
    ok = mnesia:start(),
    [mongoose_config:set_opt(Key, Value) || {Key, Value} <- opts()],
    meck:new(mongoose_domain_api, [no_link]),
    meck:expect(mongoose_domain_api, get_host_type,
                fun(_) -> {error, not_found} end),
    application:ensure_all_started(exometer_core),
    gen_hook:start_link(),
    ejabberd_router:start_link(),
    C.

init_per_testcase(_, C) ->
    gen_hook:start_link(),
    C.

end_per_suite(_C) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    meck:unload(),
    [mongoose_config:unset_opt(Key) || {Key, _Value} <- opts()],
    ok.

opts() ->
    [{all_metrics_are_global, false},
     {routing_modules, [xmpp_router_a, xmpp_router_b, xmpp_router_c]}].

registering(_C) ->
    Dom = <<"aaa.bbb.com">>,
    ejabberd_router:register_component(Dom, mongoose_packet_handler:new(?MODULE)),
    Lookup = ejabberd_router:lookup_component(Dom),
    ?assertMatch([#external_component{}], Lookup),
    ejabberd_router:unregister_component(Dom),
    ?assertMatch([], ejabberd_router:lookup_component(Dom)),
    ok.

registering_with_local(_C) ->
    gen_hook:start_link(),
    Dom = <<"aaa.bbb.com">>,
    ThisNode = node(),
    AnotherNode = 'another@nohost',
    Handler = mongoose_packet_handler:new(?MODULE), %% This handler is only for testing!
    ejabberd_router:register_component(Dom, Handler),
    %% we can find it globally
    ?assertMatch([#external_component{node = ThisNode}], ejabberd_router:lookup_component(Dom)),
    %% and for this node
    ?assertMatch([#external_component{node = ThisNode}],
                 ejabberd_router:lookup_component(Dom, ThisNode)),
    %% but not for another node
    ?assertMatch([], ejabberd_router:lookup_component(Dom, AnotherNode)),
    %% once we unregister it is not available
    ejabberd_router:unregister_component(Dom),
    ?assertMatch([], ejabberd_router:lookup_component(Dom)),
    ?assertMatch([], ejabberd_router:lookup_component(Dom, ThisNode)),
    ?assertMatch([], ejabberd_router:lookup_component(Dom, AnotherNode)),
    %% we can register from both nodes
    ejabberd_router:register_component(Dom, ThisNode, Handler),
    %% passing node here is only for testing
    ejabberd_router:register_component(Dom, AnotherNode, Handler),
    %% both are reachable locally
    ?assertMatch([#external_component{node = ThisNode}],
                 ejabberd_router:lookup_component(Dom, ThisNode)),
    ?assertMatch([#external_component{node = AnotherNode}],
                 ejabberd_router:lookup_component(Dom, AnotherNode)),
    %% if we try global lookup we get two handlers
    ?assertMatch([_, _], ejabberd_router:lookup_component(Dom)),
    %% we unregister one and the result is:
    ejabberd_router:unregister_component(Dom),
    ?assertMatch([], ejabberd_router:lookup_component(Dom, ThisNode)),
    ?assertMatch([#external_component{node = AnotherNode}],
                 ejabberd_router:lookup_component(Dom)),
    ?assertMatch([#external_component{node = AnotherNode}],
                 ejabberd_router:lookup_component(Dom, AnotherNode)),
    ok.

process_packet(_From, _To, _Packet, _Extra) ->
    exit(process_packet_called).
