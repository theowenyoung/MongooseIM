%%%-------------------------------------------------------------------
%%% @author bartek
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Apr 2017 16:09
%%%-------------------------------------------------------------------
-module(roster_SUITE).
-author("bartek").

-include_lib("eunit/include/eunit.hrl").
-include("ejabberd_c2s.hrl").
-include("mongoose.hrl").
-include_lib("exml/include/exml_stream.hrl").
-include_lib("mod_roster.hrl").
-compile([export_all, nowarn_export_all]).

-define(_eq(E, I), ?_assertEqual(E, I)).
-define(eq(E, I), ?assertEqual(E, I)).
-define(am(E, I), ?assertMatch(E, I)).
-define(ne(E, I), ?assert(E =/= I)).

-define(ACC_PARAMS, #{location => ?LOCATION,
                      lserver => domain(),
                      host_type => host_type(),
                      element => undefined}).

-define(HOST_TYPE, <<"test type">>).

all() -> [
    roster_old,
    roster_old_with_filter,
    roster_new,
    roster_case_insensitive
].

init_per_suite(C) ->
    ok = mnesia:create_schema([node()]),
    ok = mnesia:start(),
    {ok, _} = application:ensure_all_started(jid),
    {ok, _} = application:ensure_all_started(exometer_core),
    meck:new(gen_iq_handler, [no_link]),
    meck:expect(gen_iq_handler, add_iq_handler_for_domain, fun(_, _, _, _, _, _) -> ok end),
    meck:expect(gen_iq_handler, remove_iq_handler_for_domain, fun(_, _, _) -> ok end),
    meck:new(mongoose_domain_api, [no_link]),
    meck:expect(mongoose_domain_api, get_domain_host_type, fun(_) -> {ok, host_type()} end),
    [mongoose_config:set_opt(Key, Value) || {Key, Value} <- opts()],
    C.

end_per_suite(C) ->
    [mongoose_config:unset_opt(Key) || {Key, _Value} <- opts()],
    meck:unload(),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    C.

opts() ->
    [{hosts, []},
     {all_metrics_are_global, false}].

init_per_testcase(_TC, C) ->
    init_ets(),
    gen_hook:start_link(),
    gen_mod:start(),
    gen_mod:start_module(host_type(), mod_roster, []),
    C.

end_per_testcase(_TC, C) ->
    Acc = mongoose_acc:new(?ACC_PARAMS),
    mod_roster:remove_user(Acc, a(), domain()),
    gen_mod:stop_module(host_type(), mod_roster),
    delete_ets(),
    C.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% TESTS %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


roster_old(_C) ->
    R1 = get_roster_old(),
    ?assertEqual(length(R1), 0),
    ok = mod_roster:set_items(host_type(), alice_jid(), addbob_stanza()),
    assert_state_old(none, none),
    subscription(out, subscribe),
    assert_state_old(none, out),
    ok.

roster_old_with_filter(_C) ->
    R1 = get_roster_old(),
    ?assertEqual(0, length(R1)),
    ok = mod_roster:set_items(host_type(), alice_jid(), addbob_stanza()),
    assert_state_old(none, none),
    subscription(in, subscribe),
    R2 = get_roster_old(),
    ?assertEqual(0, length(R2)),
    R3 = get_full_roster(),
    ?assertEqual(1, length(R3)),
    ok.

roster_new(_C) ->
    R1 = mod_roster:get_roster_entry(host_type(), alice_jid(), bob_ljid(), short),
    ?assertEqual(does_not_exist, R1),
    ok = mod_roster:set_items(host_type(), alice_jid(), addbob_stanza()),
    assert_state_old(none, none),
    ct:pal("get_roster_old(): ~p", [get_roster_old()]),
    R2 = mod_roster:get_roster_entry(host_type(), alice_jid(), bob_ljid(), short),
    ?assertMatch(#roster{}, R2), % is not guaranteed to contain full info
    R3 = mod_roster:get_roster_entry(host_type(), alice_jid(), bob_ljid(), full),
    assert_state(R3, none, none, [<<"friends">>]),
    subscription(out, subscribe),
    R4 = mod_roster:get_roster_entry(host_type(), alice_jid(), bob_ljid(), full),
    assert_state(R4, none, out, [<<"friends">>]).


roster_case_insensitive(_C) ->
    ok = mod_roster:set_items(host_type(), alice_jid(), addbob_stanza()),
    R1 = get_roster_old(),
    ?assertEqual(1, length(R1)),
    R2 = get_roster_old(ae()),
    ?assertEqual(1, length(R2)),
    R3 = mod_roster:get_roster_entry(host_type(), alice_jid(), bob_ljid(), full),
    assert_state(R3, none, none, [<<"friends">>]),
    R3 = mod_roster:get_roster_entry(host_type(), alicE_jid(), bob_ljid(), full),
    assert_state(R3, none, none, [<<"friends">>]),
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%% HELPERS %%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

assert_state(Rentry, Subscription, Ask, Groups) ->
    ?assertEqual(Subscription, Rentry#roster.subscription),
    ?assertEqual(Ask, Rentry#roster.ask),
    ?assertEqual(Groups, Rentry#roster.groups).

subscription(Direction, Type) ->
    TFun = fun() ->
                   mod_roster:process_subscription_t(host_type(), Direction, alice_jid(),
                                                     bob_jid(), Type, <<>>)
           end,
    {atomic, _} = mod_roster:transaction(host_type(), TFun).

get_roster_old() ->
    get_roster_old(a()).

get_roster_old(User) ->
    Acc = mongoose_acc:new(?ACC_PARAMS),
    Acc1 = mod_roster:get_user_roster(Acc, jid:make(User, domain(), <<>>)),
    mongoose_acc:get(roster, items, Acc1).

get_full_roster() ->
    Acc0 = mongoose_acc:new(?ACC_PARAMS),
    Acc1 = mongoose_acc:set(roster, show_full_roster, true, Acc0),
    Acc2 = mod_roster:get_user_roster(Acc1, alice_jid()),
    mongoose_acc:get(roster, items, Acc2).

assert_state_old(Subscription, Ask) ->
    [Rentry] = get_roster_old(),
    ?assertEqual(Subscription, Rentry#roster.subscription),
    ?assertEqual(Ask, Rentry#roster.ask).

init_ets() ->
    catch ets:new(mongoose_services, [named_table]),
    ok.

delete_ets() ->
    catch ets:delete(mongoose_services),
    ok.

alice_jid() ->
    jid:make(a(), domain(), <<>>).

alicE_jid() ->
    jid:make(ae(), domain(), <<>>).

a() -> <<"alice">>.
ae() -> <<"alicE">>.

domain() -> <<"localhost">>.

bob() -> <<"bob@localhost">>.

bob_jid() ->
    jid:make(<<"bob">>, domain(), <<>>).

bob_ljid() ->
    jid:to_lower(bob_jid()).

host_type() -> <<"test type">>.

addbob_stanza() ->
    #xmlel{children = [
        #xmlel{
            attrs = [{<<"jid">>, bob()}],
            children = [
                #xmlel{name = <<"group">>,
                    children = [
                        #xmlcdata{content = <<"friends">>}
                    ]}
            ]}
        ]
    }.
