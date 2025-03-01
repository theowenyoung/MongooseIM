-module(inbox_SUITE).

-include_lib("escalus/include/escalus.hrl").
-include_lib("escalus/include/escalus_xmlns.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("exml/include/exml.hrl").
-include_lib("inbox.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0,
         groups/0,
         suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_group/2,
         end_per_group/2,
         init_per_testcase/2,
         end_per_testcase/2]).
%% tests
-export([disco_service/1,
         returns_valid_form/1,
         returns_error_when_first_bad_form_field_encountered/1,
         returns_error_when_bad_form_field_start_sent/1,
         returns_error_when_bad_form_field_end_sent/1,
         returns_error_when_bad_form_field_order_sent/1,
         returns_error_when_bad_form_field_hidden_read_sent/1,
         returns_error_when_bad_reset_field_jid/1,
         returns_error_when_no_reset_field_jid/1,
         returns_error_when_unknown_field_sent/1
        ]).
-export([msg_sent_stored_in_inbox/1,
         msg_with_no_store_is_not_stored_in_inbox/1,
         msg_with_store_hint_is_always_stored/1,
         carbons_are_not_stored/1,
         user_has_empty_inbox/1,
         user_has_two_unread_messages/1,
         other_resources_do_not_interfere/1,
         reset_unread_counter_with_reset_chat_marker/1,
         reset_unread_counter_with_reset_stanza/1,
         try_to_reset_unread_counter_with_bad_marker/1,
         non_reset_marker_should_not_affect_inbox/1,
         user_has_two_conversations/1,
         msg_sent_to_offline_user/1,
         msg_sent_to_not_existing_user/1,
         user_has_only_unread_messages_or_only_read/1,
         reset_unread_counter_and_show_only_unread/1,
         check_total_unread_count_and_active_conv_count/1,
         check_total_unread_count_when_there_are_no_active_conversations/1,
         total_unread_count_and_active_convs_are_zero_at_no_activity/1
        ]).
-export([simple_groupchat_stored_in_all_inbox/1,
         advanced_groupchat_stored_in_all_inbox/1,
         groupchat_markers_one_reset/1,
         non_reset_marker_should_not_affect_muclight_inbox/1,
         groupchat_reset_stanza_resets_inbox/1,
         create_groupchat/1,
         create_groupchat_no_affiliation_stored/1,
         leave_and_remove_conversation/1,
         leave_and_store_conversation/1,
         groupchat_markers_one_reset_room_created/1,
         groupchat_markers_all_reset_room_created/1,
         system_message_is_correctly_avoided/1,
         no_aff_stored_and_remove_on_kicked/1,
         no_stored_and_remain_after_kicked/1,
         simple_groupchat_stored_in_all_inbox_muc/1,
         simple_groupchat_stored_in_offline_users_inbox_muc/1,
         unread_count_is_the_same_after_going_online_again/1,
         unread_count_is_reset_after_sending_chatmarker/1,
         non_reset_marker_should_not_affect_muc_inbox/1,
         unread_count_is_reset_after_sending_reset_stanza/1,
         private_messages_are_handled_as_one2one/1
        ]).
-export([timestamp_is_updated_on_new_message/1,
         order_by_timestamp_ascending/1,
         get_by_timestamp_range/1,
         get_with_start_timestamp/1,
         get_with_end_timestamp/1]).

-import(muc_light_helper, [room_bin_jid/1]).
-import(inbox_helper, [
                       inbox_modules/0,
                       muclight_modules/0,
                       inbox_opts/0,
                       muc_domain/0,
                       parse_form_iq/1,
                       check_inbox/2, check_inbox/4,
                       clear_inbox_all/0,
                       given_conversations_between/2,
                       assert_invalid_inbox_form_value_error/3,
                       assert_invalid_reset_inbox/4,
                       extract_user_specs/1
                      ]).

-define(ROOM3, <<"testroom3">>).
-define(ROOM4, <<"testroom4">>).

%%--------------------------------------------------------------------
%% Suite configuration
%%--------------------------------------------------------------------

all() ->
    inbox_helper:skip_or_run_inbox_tests(tests()).

tests() ->
    [
     {group, generic},
     {group, one_to_one},
     {group, muclight},
     {group, muclight_config},
     {group, muc},
     {group, timestamps}
    ].

groups() ->
    Gs = [
     {generic, [],
      [
       disco_service,
       returns_valid_form,
       returns_error_when_first_bad_form_field_encountered,
       returns_error_when_bad_form_field_start_sent,
       returns_error_when_bad_form_field_end_sent,
       returns_error_when_bad_form_field_order_sent,
       returns_error_when_bad_form_field_hidden_read_sent,
       returns_error_when_bad_reset_field_jid,
       returns_error_when_no_reset_field_jid,
       returns_error_when_unknown_field_sent
      ]},
     {one_to_one, [],
      [
       user_has_empty_inbox,
       msg_sent_stored_in_inbox,
       msg_with_no_store_is_not_stored_in_inbox,
       msg_with_store_hint_is_always_stored,
       carbons_are_not_stored,
       user_has_two_conversations,
       msg_sent_to_offline_user,
       msg_sent_to_not_existing_user,
       user_has_two_unread_messages,
       other_resources_do_not_interfere,
       reset_unread_counter_with_reset_chat_marker,
       reset_unread_counter_with_reset_stanza,
       try_to_reset_unread_counter_with_bad_marker,
       non_reset_marker_should_not_affect_inbox,
       user_has_only_unread_messages_or_only_read,
       reset_unread_counter_and_show_only_unread,
       check_total_unread_count_and_active_conv_count,
       check_total_unread_count_when_there_are_no_active_conversations,
       total_unread_count_and_active_convs_are_zero_at_no_activity
      ]},
     {muclight, [],
      [
       simple_groupchat_stored_in_all_inbox,
       advanced_groupchat_stored_in_all_inbox,
       groupchat_markers_one_reset,
       non_reset_marker_should_not_affect_muclight_inbox,
       groupchat_reset_stanza_resets_inbox,
       create_groupchat,
       leave_and_remove_conversation,
       groupchat_markers_one_reset_room_created,
       groupchat_markers_all_reset_room_created
      ]},
     {muclight_config, [sequence],
      [
       create_groupchat_no_affiliation_stored,
       leave_and_store_conversation,
       no_aff_stored_and_remove_on_kicked,
       no_stored_and_remain_after_kicked,
       system_message_is_correctly_avoided
      ]},
     {muc, [],
      [
       simple_groupchat_stored_in_all_inbox_muc,
       simple_groupchat_stored_in_offline_users_inbox_muc,
       unread_count_is_the_same_after_going_online_again,
       unread_count_is_reset_after_sending_chatmarker,
       non_reset_marker_should_not_affect_muc_inbox,
       unread_count_is_reset_after_sending_reset_stanza,
       private_messages_are_handled_as_one2one
      ]},
     {timestamps, [],
      [
       timestamp_is_updated_on_new_message,
       order_by_timestamp_ascending,
       get_by_timestamp_range,
       get_with_start_timestamp,
       get_with_end_timestamp
      ]}
    ],
    inbox_helper:maybe_run_in_parallel(Gs).

suite() ->
    escalus:suite().

%%--------------------------------------------------------------------
%% Init & teardown
%%--------------------------------------------------------------------

init_per_suite(Config0) ->
    Config1 = dynamic_modules:save_modules(domain_helper:host_type(), Config0),
    ok = dynamic_modules:ensure_modules(
           domain_helper:host_type(), inbox_modules()),
    ok = dynamic_modules:ensure_modules(
           ct:get_config({hosts, mim, secondary_host_type}),
           [{mod_inbox,
             [{aff_changes, false},
              {remove_on_kicked, true},
              {groupchat, [muclight]},
              {markers, [displayed]}]}]),
    InboxOptions = inbox_opts(),
    escalus:init_per_suite([{inbox_opts, InboxOptions} | Config1]).

end_per_suite(Config) ->
    escalus_fresh:clean(),
    dynamic_modules:stop(ct:get_config({hosts, mim, secondary_host_type}), mod_inbox),
    dynamic_modules:restore_modules(domain_helper:host_type(), Config),
    escalus:end_per_suite(Config).

init_per_group(one_to_one, Config) ->
    dynamic_modules:ensure_modules(domain_helper:host_type(), [{mod_offline, []}]),
    inbox_helper:reload_inbox_option(Config, groupchat, []);
init_per_group(muclight, Config) ->
    ok = dynamic_modules:ensure_modules(domain_helper:host_type(mim), muclight_modules()),
    inbox_helper:reload_inbox_option(Config, groupchat, [muclight]),
    [{group, muclight} | Config];
init_per_group(muclight_config, Config) ->
    ok = dynamic_modules:ensure_modules(domain_helper:host_type(mim), muclight_modules()),
    Config1 = inbox_helper:reload_inbox_option(Config, groupchat, [muclight]),
    escalus:create_users(Config1, escalus:get_users([alice, alice_bis, bob, kate, mike]));
init_per_group(muc, Config) ->
    muc_helper:load_muc(),
    inbox_helper:reload_inbox_option(Config, groupchat, [muc]);
init_per_group(_GroupName, Config) ->
    Config.

end_per_group(muc, _Config) ->
    HostType = domain_helper:host_type(mim),
    dynamic_modules:stop(HostType, mod_muc);
end_per_group(muclight, Config) ->
    HostType = domain_helper:host_type(mim),
    muc_light_helper:clear_db(HostType),
    dynamic_modules:stop(HostType, mod_muc_light),
    Config;
end_per_group(muclight_config, Config) ->
    HostType = domain_helper:host_type(mim),
    muc_light_helper:clear_db(HostType),
    dynamic_modules:stop(HostType, mod_muc_light),
    escalus:delete_users(Config, escalus:get_users([alice, alice_bis, bob, kate, mike]));
end_per_group(_GroupName, Config) ->
    Config.


init_per_testcase(TS, Config)
  when TS =:= create_groupchat_no_affiliation_stored;
       TS =:= system_message_is_correctly_avoided ->
    clear_inbox_all(),
    inbox_helper:reload_inbox_option(Config, aff_changes, false),
    escalus:init_per_testcase(TS, Config);
init_per_testcase(leave_and_store_conversation, Config) ->
    clear_inbox_all(),
    inbox_helper:reload_inbox_option(Config, remove_on_kicked, false),
    escalus:init_per_testcase(leave_and_store_conversation, Config);
init_per_testcase(no_aff_stored_and_remove_on_kicked, Config) ->
    clear_inbox_all(),
    muc_light_helper:create_room(?ROOM3, muc_light_helper:muc_host(), alice, [bob, kate],
                                 Config, muc_light_helper:ver(1)),
    inbox_helper:reload_inbox_option(Config, [{remove_on_kicked, true}, {aff_changes, false}]),
    escalus:init_per_testcase(no_aff_stored_and_remove_on_kicked, Config);
init_per_testcase(no_stored_and_remain_after_kicked, Config) ->
    clear_inbox_all(),
    muc_light_helper:create_room(?ROOM4, muc_light_helper:muc_host(), alice, [bob, kate],
                                 Config, muc_light_helper:ver(1)),
    inbox_helper:reload_inbox_option(Config, [{remove_on_kicked, false}, {aff_changes, true}]),
    escalus:init_per_testcase(no_stored_and_remain_after_kicked, Config);
init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(TS, Config)
  when TS =:= create_groupchat_no_affiliation_stored;
       TS =:= system_message_is_correctly_avoided ->
    clear_inbox_all(),
    inbox_helper:restore_inbox_option(Config),
    escalus:end_per_testcase(TS, Config);
end_per_testcase(leave_and_store_conversation, Config) ->
    clear_inbox_all(),
    inbox_helper:restore_inbox_option(Config),
    escalus:end_per_testcase(leave_and_store_conversation, Config);
end_per_testcase(no_aff_stored_and_remove_on_kicked, Config) ->
    clear_inbox_all(),
    inbox_helper:restore_inbox_option(Config),
    escalus:end_per_testcase(no_aff_stored_and_remove_on_kicked, Config);
end_per_testcase(no_stored_and_remain_after_kicked, Config) ->
    clear_inbox_all(),
    inbox_helper:restore_inbox_option(Config),
    escalus:end_per_testcase(no_stored_and_remain_after_kicked, Config);
end_per_testcase(msg_sent_to_not_existing_user, Config) ->
    HostType = domain_helper:host_type(mim),
    escalus_ejabberd:rpc(mod_inbox_utils, clear_inbox, [HostType, <<"not_existing_user">>,<<"localhost">>]),
    escalus:end_per_testcase(msg_sent_to_not_existing_user, Config);
end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).


%%--------------------------------------------------------------------
%% Generic Inbox tests
%%--------------------------------------------------------------------

disco_service(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
            Server = escalus_client:server(Alice),
            escalus:send(
              Alice, escalus_stanza:to(escalus_stanza:iq_get(?NS_DISCO_INFO, []), Server)),
            Stanza = escalus:wait_for_stanza(Alice),
            Features = exml_query:paths(Stanza, [{element, <<"query">>},
                                                 {element, <<"feature">>},
                                                 {attr, <<"var">>}]),
            ?assertEqual(true, lists:member(inbox_helper:inbox_ns(), Features))
        end).

returns_valid_form(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
        escalus:send(Alice, inbox_helper:get_inbox_form_stanza()),
        ResIQ = escalus:wait_for_stanza(Alice),
        InboxNS = inbox_helper:inbox_ns(),
        #{ field_count := 6 } = Form = parse_form_iq(ResIQ),
        #{ <<"FORM_TYPE">> := #{ type := <<"hidden">>,
                                 value := InboxNS } } = Form,
        #{ <<"start">> := #{ type := <<"text-single">> } } = Form,
        #{ <<"end">> := #{ type := <<"text-single">> } } = Form,
        #{ <<"order">> := #{ type := <<"list-single">>,
                             value := <<"desc">>,
                             options := OrderOptions } } = Form,
        [<<"asc">>, <<"desc">>] = lists:sort(OrderOptions),
        #{ <<"hidden_read">> := #{ type := <<"text-single">> } } = Form
      end).

returns_error_when_bad_form_field_order_sent(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
        assert_invalid_inbox_form_value_error(Alice, <<"order">>, <<"invalid">>)
      end).

returns_error_when_bad_form_field_start_sent(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
        assert_invalid_inbox_form_value_error(Alice, <<"start">>, <<"invalid">>)
      end).

returns_error_when_bad_form_field_end_sent(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
      assert_invalid_inbox_form_value_error(Alice, <<"end">>, <<"invalid">>)
    end).

returns_error_when_bad_form_field_hidden_read_sent(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
      assert_invalid_inbox_form_value_error(Alice, <<"hidden_read">>, <<"invalid">>)
    end).

returns_error_when_bad_reset_field_jid(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
      assert_invalid_reset_inbox(
        Alice, <<"$@/">>, <<"jid">>, <<"invalid-jid">>)
    end).

returns_error_when_no_reset_field_jid(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
      assert_invalid_reset_inbox(
        Alice, undefined, <<"jid">>, <<"jid-required">>)
    end).


returns_error_when_first_bad_form_field_encountered(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
        Stanza = inbox_helper:make_inbox_stanza( #{ <<"start">> => <<"invalid">>,
                                                   <<"end">> => <<"invalid">>}, false),
        escalus:send(Alice, Stanza),
        [ResIQ] = escalus:wait_for_stanzas(Alice, 1),
        escalus_pred:is_iq_error(ResIQ),
        ErrorMsg = inbox_helper:get_error_message(ResIQ),
        inbox_helper:assert_message_content(ErrorMsg, <<"field=end">>, <<"value=invalid">>)
      end).

returns_error_when_unknown_field_sent(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
        Stanza = inbox_helper:make_inbox_stanza( #{ <<"unknown_field">> => <<"unknown_field_value">> }, false),
        escalus:send(Alice, Stanza),
        [ResIQ] = escalus:wait_for_stanzas(Alice, 1),
        escalus_pred:is_iq_error(ResIQ),
        ErrorMsg = inbox_helper:get_error_message(ResIQ),
        inbox_helper:assert_message_content(ErrorMsg, <<"field=unknown_field">>, <<"value=unknown_field_value">>)
      end).


%%--------------------------------------------------------------------
%% Inbox tests one-to-one
%%--------------------------------------------------------------------

user_has_empty_inbox(Config) ->
    escalus:fresh_story(Config, [{kate, 1}], fun(Kate) ->
        Stanza = inbox_helper:make_inbox_stanza(),
        %% Kate logs in for first time and ask for inbox
        escalus:send(Kate, Stanza),
        [ResIQ] = escalus:wait_for_stanzas(Kate, 1),
        true = escalus_pred:is_iq_result(ResIQ),
        %% Inbox is empty
        TotalCount = inbox_helper:get_result_el(ResIQ, <<"count">>),
        0 = TotalCount
      end).

msg_sent_stored_in_inbox(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}], fun(Alice, Bob) ->
        #{ Alice := AliceConvs, Bob := BobConvs } = given_conversations_between(Alice, [Bob]),
        %% Both check inbox
        check_inbox(Alice, AliceConvs),
        check_inbox(Bob, BobConvs)
      end).

msg_with_no_store_is_not_stored_in_inbox(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}], fun(Alice, Bob) ->
        %% Alice sends a message to Bob with a no-store hint
        Body = <<"test">>,
        Msg1 = escalus_stanza:chat_to(Bob, Body),
        Msg2 = escalus_stanza:set_id(Msg1, escalus_stanza:id()),
        Msg3 = mam_helper:add_nostore_hint(Msg2),
        escalus:send(Alice, Msg3),
        MsgSent = escalus:wait_for_stanza(Bob),
        escalus:assert(is_chat_message, MsgSent),
        %% Bob has no unread messages in conversation with Alice
        check_inbox(Bob, []),
        %% Alice has no conv in her inbox either
        check_inbox(Alice, [])
      end).

msg_with_store_hint_is_always_stored(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}], fun(Alice, Bob) ->
        %% Alice sends a message to Bob with a store hint, that would otherwise be ignored
        Msg1 = escalus_stanza:to(#xmlel{name = <<"message">>}, Bob),
        Msg2 = escalus_stanza:set_id(Msg1, escalus_stanza:id()),
        Msg3 = mam_helper:add_store_hint(Msg2),
        escalus:send(Alice, Msg3),
        escalus:wait_for_stanza(Bob),
        %% Alice and Bob has a body-less message in their inbox
        check_inbox(Bob, [#conv{unread = 1, from = Alice, to = Bob, content = <<>>}]),
        check_inbox(Alice, [#conv{unread = 0, from = Alice, to = Bob, content = <<>>}])
      end).

carbons_are_not_stored(Config) ->
    escalus:fresh_story(Config, [{alice, 2}, {bob, 2}], fun(Alice1, Alice2, Bob1, Bob2) ->
        mongoose_helper:enable_carbons([Alice1, Alice2, Bob1, Bob2]),
        #{ Alice1 := AliceConvs, Bob1 := BobConvs } = given_conversations_between(Alice1, [Bob1]),
        %% Both check inbox and carbons aren't there
        check_inbox(Alice1, AliceConvs),
        check_inbox(Bob1, BobConvs)
      end).

user_has_two_conversations(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        #{ Alice := AliceConvs, Bob := BobConvs, Kate := KateConvs } =
        given_conversations_between(Alice, [Bob, Kate]),

        %% Alice has two conversations in her inbox (no unread messages)
        check_inbox(Alice, AliceConvs),

        %% Kate has one conversation with one unread
        check_inbox(Kate, KateConvs),

        %% Bob has one conversation with one unread
        check_inbox(Bob, BobConvs)
      end).

user_has_only_unread_messages_or_only_read(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        given_conversations_between(Alice, [Bob, Kate]),
        % Alice has no unread messages, but requests all conversations
        inbox_helper:get_inbox(Alice, #{ hidden_read => false }, #{count => 2}),

        % Requests only conversations with unread messages
        inbox_helper:get_inbox(Alice, #{ hidden_read => true }, #{count => 0}),
        % Bob has only one, unread message
        inbox_helper:get_inbox(Bob, #{ hidden_read => true }, #{count => 1})
      end).

msg_sent_to_offline_user(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}], fun(Alice, Bob) ->
        %% Bob goes offline
        mongoose_helper:logout_user(Config, Bob),

        %% Alice sends a message to Bob
        Msg1 = escalus_stanza:chat_to(Bob, <<"test">>),
        escalus:send(Alice, Msg1),

        %% Bob goes online again
        {_, BobSpecs} = extract_user_specs(Bob),
        {ok, NewBob} = escalus_client:start(Config, BobSpecs, <<"new-session">>),
        escalus:send(NewBob, escalus_stanza:presence(<<"available">>)),
        Stanzas = escalus:wait_for_stanzas(NewBob, 2),

        escalus_new_assert:mix_match
        ([is_presence, fun(Stanza) -> escalus_pred:is_chat_message(<<"test">>, Stanza) end],
          Stanzas),

        %% Alice has conversation
        check_inbox(Alice, [#conv{unread = 0, from = Alice, to = Bob, content = <<"test">>}]),

        %% Both check inbox and has a conversation
        check_inbox(NewBob, [#conv{unread = 1, from = Alice, to = Bob, content = <<"test">>}])
      end).

msg_sent_to_not_existing_user(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
        %% Alice sends message to user that doesnt exist
        Msg1 = escalus_stanza:chat_to(<<"not_existing_user@localhost">>, <<"test2">>),
        escalus:send(Alice, Msg1),

        %% Alice receives error
        ServiceUnavailable = escalus:wait_for_stanza(Alice),
        escalus_pred:is_error(<<"cancel">>,<<"service-unavailable">>, ServiceUnavailable),

        %% Alice has this conversation in inbox.
        check_inbox(Alice,[#conv{unread = 0,
                                 from = Alice,
                                 to = <<"not_existing_user@localhost">>,
                                 content = <<"test2">>}])
      end).

user_has_two_unread_messages(Config) ->
    escalus:fresh_story(Config, [{kate, 1}, {mike, 1}], fun(Kate, Mike) ->
        inbox_helper:send_msg(Kate, Mike, "Hello"),
        inbox_helper:send_msg(Kate, Mike, "How are you"),
        %% Mike has two unread messages in conversation with Kate
        check_inbox(Mike, [#conv{unread = 2, from = Kate, to = Mike, content = <<"How are you">>}]),
        %% Kate has one conv in her inbox (no unread messages)
        check_inbox(Kate, [#conv{unread = 0, from = Kate, to = Mike, content = <<"How are you">>}])
      end).

other_resources_do_not_interfere(Config) ->
    %% regression test
    escalus:fresh_story(Config, [{kate, 2}, {mike, 1}], fun(Kate, Kate2, Mike) ->
        Prio = #xmlel{name = <<"priority">>, children = [#xmlcdata{content = <<"100">>}]},
        escalus_client:send(Kate2, escalus_stanza:presence(<<"available">>, [Prio])),
        escalus_client:wait_for_stanza(Kate),
        inbox_helper:send_msg(Kate, Mike, "Hello"),
        inbox_helper:send_msg(Kate, Mike, "How are you"),
        %% Mike has two unread messages in conversation with Kate
        check_inbox(Mike, [#conv{unread = 2, from = Kate, to = Mike, content = <<"How are you">>}]),
        %% Kate has one conv in her inbox (no unread messages)
        check_inbox(Kate, [#conv{unread = 0, from = Kate, to = Mike, content = <<"How are you">>}])
                                                  end).

reset_unread_counter_with_reset_chat_marker(Config) ->
    escalus:fresh_story(Config, [{kate, 1}, {mike, 1}], fun(Kate, Mike) ->
        Msg = inbox_helper:send_msg(Kate, Mike, <<"Hi mike">>),
        MsgId = exml_query:attr(Msg, <<"id">>),

        %% Mike has one unread message
        check_inbox(Mike, [#conv{unread = 1, from = Kate, to = Mike, content = <<"Hi mike">>}]),
        ChatMarker = escalus_stanza:chat_marker(Kate, <<"displayed">>, MsgId),
        %% Mike sends "displayed" chat marker to Kate
        escalus:send(Mike, ChatMarker),
        %% Now Mike asks for inbox second time. He has 0 unread messages now
        check_inbox(Mike, [#conv{unread = 0, from = Kate, to = Mike, content = <<"Hi mike">>}])
      end).

reset_unread_counter_with_reset_stanza(Config) ->
    escalus:fresh_story(Config, [{kate, 1}, {mike, 1}], fun(Kate, Mike) ->
        _Msg = inbox_helper:send_msg(Kate, Mike, <<"Hi mike">>),

        %% Mike has one unread message
        check_inbox(Mike, [#conv{unread = 1, from = Kate, to = Mike, content = <<"Hi mike">>}]),
        %% Mike sends "reset" stanza
        inbox_helper:reset_inbox(Mike, Kate),
        %% Now Mike asks for inbox second time. He has 0 unread messages now
        check_inbox(Mike, [#conv{unread = 0, from = Kate, to = Mike, content = <<"Hi mike">>}]),
        %% Kate should not be receiving this stanza
        inbox_helper:assert_has_no_stanzas(Kate)
      end).

reset_unread_counter_and_show_only_unread(Config) ->
    escalus:fresh_story(Config, [{kate, 1}, {mike, 1}, {alice, 1}], fun(Kate, Mike, Alice) ->
        Msg = inbox_helper:send_msg(Kate, Mike),
        MsgId = exml_query:attr(Msg, <<"id">>),
        inbox_helper:get_inbox(Mike, #{ hidden_read => true }, #{count => 1}),

        ChatMarker = escalus_stanza:chat_marker(Kate, <<"displayed">>, MsgId),
        escalus:send(Mike, ChatMarker),

        inbox_helper:get_inbox(Mike, #{ hidden_read => true }, #{count => 0}),

        inbox_helper:send_msg(Alice, Mike),
        % Mike has two conversations, one with unread messages
        inbox_helper:get_inbox(Mike, #{ hidden_read => true }, #{count => 1}),
        inbox_helper:get_inbox(Mike, #{ hidden_read => false }, #{count => 2})
      end).

check_total_unread_count_and_active_conv_count(Config) ->
    escalus:fresh_story(Config, [{kate, 1}, {mike, 1}, {alice, 1}], fun(Kate, Mike, Alice) ->
        inbox_helper:send_and_mark_msg(Kate, Mike),
        inbox_helper:send_msg(Alice, Mike),
        inbox_helper:send_msg(Alice, Mike),
        inbox_helper:send_msg(Kate, Mike),
        inbox_helper:get_inbox(Mike, #{count => 2, unread_messages => 3, active_conversations => 2})
      end).

check_total_unread_count_when_there_are_no_active_conversations(Config) ->
    escalus:fresh_story(Config, [{kate, 1}, {mike, 1}], fun(Kate, Mike) ->
        inbox_helper:send_and_mark_msg(Kate, Mike),

        inbox_helper:get_inbox(Mike, #{count => 1, unread_messages => 0, active_conversations => 0})
  end).

total_unread_count_and_active_convs_are_zero_at_no_activity(Config) ->
    escalus:fresh_story(Config, [{kate, 1}], fun(Kate) ->
        inbox_helper:get_inbox(Kate, #{count => 0, unread_messages => 0, active_conversations => 0})
                                                end).



try_to_reset_unread_counter_with_bad_marker(Config) ->
    escalus:fresh_story(Config, [{kate, 1}, {mike, 1}], fun(Kate, Mike) ->
        Msg1 = escalus_stanza:set_id(escalus_stanza:chat_to(Mike, <<"okey dockey">>), <<"111">>),
        %% Kate sends message to Mike
        escalus:send(Kate, Msg1),
        M1 = escalus:wait_for_stanza(Mike),
        escalus:assert(is_chat_message, M1),
        %% Mike has one unread message
        check_inbox(Mike, [#conv{unread = 1, from = Kate, to = Mike, content = <<"okey dockey">>}]),
        MsgId = <<"badId">>,
        ChatMarker = escalus_stanza:chat_marker(Kate, <<"displayed">>, MsgId),
        %% Mike sends "displayed" chat marker but 'id' field is wrong
        escalus:send(Mike, ChatMarker),
        %% Now Mike asks for inbox second time. Unread count should be still the same
        check_inbox(Mike, [#conv{unread = 1, from = Kate, to = Mike, content = <<"okey dockey">>}])
      end).

non_reset_marker_should_not_affect_inbox(Config) ->
    escalus:fresh_story(Config, [{kate, 1}, {mike, 1}], fun(Kate, Mike) ->
        MsgId = <<"kate_to_mike">>,
        MsgBody = <<"okey dockey">>,
        Msg = escalus_stanza:set_id(escalus_stanza:chat_to(Mike, MsgBody), MsgId),
        %% Kate sends message to Mike
        escalus:send(Kate, Msg),
        M1 = escalus:wait_for_stanza(Mike),
        escalus:assert(is_chat_message, M1),
        %% Mike has one unread message
        check_inbox(Mike, [#conv{unread = 1, from = Kate, to = Mike, content = MsgBody}]),
        ChatMarker = escalus_stanza:chat_marker(Kate, <<"received">>, MsgId),
        %% Mike sends "received" chat marker, which is not a reset_marker
        escalus:send(Mike, ChatMarker),
        CM = escalus:wait_for_stanza(Kate),
        escalus:assert(is_message, CM),
        %% Now Mike asks for inbox second time. Unread count should be still the same
        check_inbox(Mike, [#conv{unread = 1, from = Kate, to = Mike, content = MsgBody}]),
        check_inbox(Kate, [], #{hidden_read => true}, #{})
      end).

%%--------------------------------------------------------------------
%% Inbox tests muclight
%%--------------------------------------------------------------------

simple_groupchat_stored_in_all_inbox(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        Msg = <<"Hi Room!">>,
        Id = <<"MyID">>,
        Room = inbox_helper:create_room(Alice, [Bob, Kate]),
        AliceJid = inbox_helper:to_bare_lower(Alice),
        KateJid = inbox_helper:to_bare_lower(Kate),
        BobJid = inbox_helper:to_bare_lower(Bob),
        RoomJid = room_bin_jid(Room),
        AliceRoomJid = <<RoomJid/binary,"/", AliceJid/binary>>,
        Stanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomJid, Msg), Id),
        %% Alice sends message to a room
        escalus:send(Alice, Stanza),
        R0 = escalus:wait_for_stanza(Alice),
        R1 = escalus:wait_for_stanza(Bob),
        R2 = escalus:wait_for_stanza(Kate),
        escalus:assert(is_groupchat_message, R0),
        escalus:assert(is_groupchat_message, R1),
        escalus:assert(is_groupchat_message, R2),
        %% Alice has 0 unread messages
        check_inbox(Alice, [#conv{unread = 0, from = AliceRoomJid, to = AliceJid, content = Msg}]),
        %% Bob and Kate have one conv with 1 unread message
        check_inbox(Bob, [#conv{unread = 1, from = AliceRoomJid, to = BobJid, content = Msg}]),
        check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid, to = KateJid, content = Msg}])
      end).

advanced_groupchat_stored_in_all_inbox(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        Msg1 = <<"Hi Room!">>,
        Msg2 = <<"How are you?">>,
        Id = <<"MyID">>,
        Room = inbox_helper:create_room(Alice, [Bob, Kate]),
        BobJid = inbox_helper:to_bare_lower(Bob),
        AliceJid = inbox_helper:to_bare_lower(Alice),
        KateJid = inbox_helper:to_bare_lower(Kate),
        RoomJid = room_bin_jid(Room),
        BobRoomJid = <<RoomJid/binary,"/", BobJid/binary>>,
        Stanza1 = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomJid, Msg1), Id),
        %% Alice sends msg to room
        escalus:send(Alice, Stanza1),
        R0 = escalus:wait_for_stanza(Alice),
        R1 = escalus:wait_for_stanza(Bob),
        R2 = escalus:wait_for_stanza(Kate),
        escalus:assert(is_groupchat_message, R0),
        escalus:assert(is_groupchat_message, R1),
        escalus:assert(is_groupchat_message, R2),
        %% Bob sends second message
        Stanza2 = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomJid, Msg2), Id),
        escalus:send(Bob, Stanza2),
        R3 = escalus:wait_for_stanza(Alice),
        R4 = escalus:wait_for_stanza(Bob),
        R5 = escalus:wait_for_stanza(Kate),
        escalus:assert(is_groupchat_message, R3),
        escalus:assert(is_groupchat_message, R4),
        escalus:assert(is_groupchat_message, R5),
        %% Alice have one unread message (from Bob)
        check_inbox(Alice, [#conv{unread = 1, from = BobRoomJid, to = AliceJid, content = Msg2}]),
        %% Bob has 0 unread messages because he sent the last message
        check_inbox(Bob, [#conv{unread = 0, from = BobRoomJid, to = BobJid, content = Msg2}]),
        %% Kate has 2 unread messages (from Alice and Bob)
        check_inbox(Kate, [#conv{unread = 2, from = BobRoomJid, to = KateJid, content = Msg2}])
      end).

groupchat_markers_one_reset(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        AliceJid = inbox_helper:to_bare_lower(Alice),
        BobJid = inbox_helper:to_bare_lower(Bob),
        KateJid = inbox_helper:to_bare_lower(Kate),
        Room = inbox_helper:create_room(Alice, [Bob, Kate]),
        RoomJid = room_bin_jid(Room),
        AliceRoomJid = <<RoomJid/binary,"/", AliceJid/binary>>,
        Id = <<"markerId">>,
        Stanza1 = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomJid, <<"marker time!">>), Id),
        escalus:send(Alice, Stanza1),
        R0 = escalus:wait_for_stanza(Alice),
        R1 = escalus:wait_for_stanza(Bob),
        R2 = escalus:wait_for_stanza(Kate),
        escalus:assert(is_groupchat_message, R0),
        escalus:assert(is_groupchat_message, R1),
        escalus:assert(is_groupchat_message, R2),
        ChatMarkerWOType = escalus_stanza:chat_marker(RoomJid,<<"displayed">>, Id),
        ChatMarker = escalus_stanza:setattr(ChatMarkerWOType, <<"type">>, <<"groupchat">>),
        %% User marks last message
        escalus:send(Bob, ChatMarker),
        %% participants receive marker
        muc_helper:foreach_recipient([Alice, Bob, Kate], fun(Marker) ->
          true = escalus_pred:is_chat_marker(<<"displayed">>, Id, Marker) end),
        %% Bob has 0 unread messages because he reset his counter
        check_inbox(Bob, [#conv{unread = 0, from = AliceRoomJid,
                                to = BobJid, content = <<"marker time!">>}]),
        %% Alice has 0 unread messages because she was the sender
        check_inbox(Alice, [#conv{unread = 0, from = AliceRoomJid,
                                  to = AliceJid, content = <<"marker time!">>}]),
        %% Kate still has unread message
        check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid,
                                 to = KateJid, content = <<"marker time!">>}])
      end).

non_reset_marker_should_not_affect_muclight_inbox(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        % %% GIVEN
        AliceJid = inbox_helper:to_bare_lower(Alice),
        BobJid = inbox_helper:to_bare_lower(Bob),
        KateJid = inbox_helper:to_bare_lower(Kate),
        Room = inbox_helper:create_room(Alice, [Bob, Kate]),
        RoomJid = room_bin_jid(Room),
        AliceRoomJid = <<RoomJid/binary,"/", AliceJid/binary>>,
        Msg = <<"marker time!">>,
        % %% WHEN DONE
        Stanza1 = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomJid, Msg), escalus_stanza:id()),
        escalus:send(Alice, Stanza1),
        R0 = escalus:wait_for_stanza(Alice),
        R1 = escalus:wait_for_stanza(Bob),
        R2 = escalus:wait_for_stanza(Kate),
        escalus:assert(is_groupchat_message, R0),
        escalus:assert(is_groupchat_message, R1),
        escalus:assert(is_groupchat_message, R2),
        % %% AND MARKED WRONG
        inbox_helper:mark_last_muclight_message(Bob, [Alice, Bob, Kate], <<"received">>),
        inbox_helper:mark_last_muclight_message(Kate, [Alice, Bob, Kate], <<"acknowledged">>),
        % %% THEN
        %% Alice has 0 unread messages because she was the sender
        check_inbox(Alice, [#conv{unread = 0, from = AliceRoomJid,
                                  to = AliceJid, content = Msg}]),
        %% Bob still has unread message
        check_inbox(Bob, [#conv{unread = 1, from = AliceRoomJid,
                                to = BobJid, content = Msg}]),
        %% Kate still has unread message
        check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid,
                                 to = KateJid, content = Msg}])
      end).

groupchat_reset_stanza_resets_inbox(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        % %% WITH
        AliceJid = inbox_helper:to_bare_lower(Alice),
        BobJid = inbox_helper:to_bare_lower(Bob),
        KateJid = inbox_helper:to_bare_lower(Kate),
        Room = inbox_helper:create_room(Alice, [Bob, Kate]),
        RoomJid = room_bin_jid(Room),
        AliceRoomJid = <<RoomJid/binary,"/", AliceJid/binary>>,
        % %% WHEN A MESSAGE IS SENT
        MsgStanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomJid, <<"marker time!">>), <<"some_ID">>),
        escalus:send(Alice, MsgStanza),
        inbox_helper:wait_for_groupchat_msg([Alice, Bob, Kate]),
        % verify that Bob has the message on inbox
        check_inbox(Bob, [#conv{unread = 1, from = AliceRoomJid,
                                to = BobJid, content = <<"marker time!">>}]),
        % %% AND WHEN SEND RESET FOR ROOM
        inbox_helper:reset_inbox(Bob, RoomJid),
        % %% THEN INBOX IS RESET FOR BOB, WITHOUT FORWARDING
        %% Bob has 0 unread messages because he reset his counter
        check_inbox(Bob, [#conv{unread = 0, from = AliceRoomJid,
                                to = BobJid, content = <<"marker time!">>}]),
        %% Alice has 0 unread messages because she was the sender
        check_inbox(Alice, [#conv{unread = 0, from = AliceRoomJid,
                                  to = AliceJid, content = <<"marker time!">>}]),
        %% Kate still has unread message
        check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid,
                                 to = KateJid, content = <<"marker time!">>}]),
        %% And nobody received any other stanza
        inbox_helper:assert_has_no_stanzas([Alice, Bob, Kate])
      end).

%% this test combines options:
%% ...
%%{aff_changes, true},
%%{remove_on_kicked, true},
create_groupchat(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomNode = <<"bobroom">>,
        inbox_helper:create_room_and_check_inbox(Bob, [Alice, Kate], RoomNode)
      end).


%% this test combines options:
%% ...
%%{aff_changes, false},
%%{remove_on_kicked, true},
create_groupchat_no_affiliation_stored(Config) ->
     escalus:story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
         InitOccupants = [{Alice, member}, {Kate, member}],
         FinalOccupants = [{Bob, owner} | InitOccupants],
         Msg = <<"Hi all!">>,
         InitConfig = [{<<"roomname">>, <<"Bob's room2">>}],
         RoomNode = <<"bobroom2">>,
         RoomJid = room_bin_jid(RoomNode),
         AliceJid = inbox_helper:to_bare_lower(Alice),
         AliceRoomJid = <<RoomJid/binary,"/", AliceJid/binary>>,
         BobJid = inbox_helper:to_bare_lower(Bob),
         KateJid = inbox_helper:to_bare_lower(Kate),
         %% Bob creates room
         escalus:send(Bob, muc_light_helper:stanza_create_room(RoomNode, InitConfig, InitOccupants)),
         muc_light_helper:verify_aff_bcast(FinalOccupants, FinalOccupants),
         escalus:assert(is_iq_result, escalus:wait_for_stanza(Bob)),
         %% affiliation change messages are not stored in inbox
         check_inbox(Alice, []),
         check_inbox(Bob, []),
         check_inbox(Kate, []),
         Stanza = escalus_stanza:set_id(
           escalus_stanza:groupchat_to(RoomJid, Msg), <<"123">>),
         %% Alice sends a message
         escalus:send(Alice, Stanza),
         R0 = escalus:wait_for_stanza(Alice),
         R1 = escalus:wait_for_stanza(Bob),
         R2 = escalus:wait_for_stanza(Kate),
         escalus:assert(is_groupchat_message, R0),
         escalus:assert(is_groupchat_message, R1),
         escalus:assert(is_groupchat_message, R2),
         %% Alice has 0 unread because she sent the last message
         check_inbox(Alice, [#conv{unread = 0, from = AliceRoomJid, to = AliceJid, content = Msg}]),
         %% Bob and Kate have one unread message
         check_inbox(Bob, [#conv{unread = 1, from = AliceRoomJid, to = BobJid, content = Msg}]),
         check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid, to = KateJid, content = Msg}])
       end).


%% this test combines options:
%% ...
%%{aff_changes, true},
%%{remove_on_kicked, true},
leave_and_remove_conversation(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        Msg = <<"Hi Room!">>,
        Id = <<"MyID">>,
        AliceJid = inbox_helper:to_bare_lower(Alice),
        KateJid = inbox_helper:to_bare_lower(Kate),
        Room = inbox_helper:create_room(Alice, [Bob, Kate]),
        RoomJid = room_bin_jid(Room),
        AliceRoomJid = <<RoomJid/binary,"/", AliceJid/binary>>,
        Stanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomJid, Msg), Id),
        %% Alice sends msg to room
        escalus:send(Alice, Stanza),
        R0 = escalus:wait_for_stanza(Alice),
        R1 = escalus:wait_for_stanza(Bob),
        R2 = escalus:wait_for_stanza(Kate),
        escalus:assert(is_groupchat_message, R0),
        escalus:assert(is_groupchat_message, R1),
        escalus:assert(is_groupchat_message, R2),
        %% Bob leaves the room
        muc_light_helper:user_leave(Room, Bob, [{Alice, owner}, {Kate, member}]),
        %% Alice and Kate have one message
        check_inbox(Alice, [#conv{unread = 0, from = AliceRoomJid, to = AliceJid, content = Msg}]),
        check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid, to = KateJid, content = Msg}]),
        %% Bob doesn't have conversation in his inbox
        check_inbox(Bob, [])
      end).

%% this test combines options:
%% ...
%%{aff_changes, true},
%%{remove_on_kicked, false},
leave_and_store_conversation(Config) ->
    escalus:story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomName = <<"kicking-room">>,
        AliceJid = inbox_helper:to_bare_lower(Alice),
        BobJid = inbox_helper:to_bare_lower(Bob),
        KateJid = inbox_helper:to_bare_lower(Kate),
        RoomJid = room_bin_jid(RoomName),
        AliceRoomJid = <<RoomJid/binary,"/", AliceJid/binary>>,
        Msg = <<"Hi all">>,
        %% Alice creates a room and send msg
        inbox_helper:create_room_send_msg_check_inbox(Alice, [Bob, Kate], RoomName,
                                                      Msg, <<"leave-id">>),
        %% Bob leaves room
        muc_light_helper:user_leave(RoomName, Bob, [{Alice, owner}, {Kate, member}]),
        %% Alice and Kate have conversation
        check_inbox(Alice, [#conv{unread = 0, from = AliceRoomJid, to = AliceJid, content = Msg}]),
        check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid, to = KateJid, content = Msg}]),
        %% Bob still has a conversation in inbox. Two unread - first is invitation,
        %% the second is the leaving affiliation
        check_inbox(Bob, [#conv{unread = 2, from = RoomJid, to = BobJid,
                                verify = fun inbox_helper:verify_is_none_aff_change/2}])
      end).

%% this test combines options:
%% ...
%%{aff_changes, false},
%%{remove_on_kicked, true},
no_aff_stored_and_remove_on_kicked(Config) ->
    escalus:story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        AliceJid = inbox_helper:to_bare_lower(Alice),
        KateJid = inbox_helper:to_bare_lower(Kate),
        RoomJid = room_bin_jid(?ROOM3),
        AliceRoomJid = <<RoomJid/binary, "/", AliceJid/binary>>,
        Msg = <<"Hi all">>,
        Stanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomJid, Msg), <<"33">>),
        %% Alice sends a message
        escalus:send(Alice, Stanza),
        R0 = escalus:wait_for_stanza(Alice),
        R1 = escalus:wait_for_stanza(Bob),
        R2 = escalus:wait_for_stanza(Kate),
        escalus:assert(is_groupchat_message, R0),
        escalus:assert(is_groupchat_message, R1),
        escalus:assert(is_groupchat_message, R2),
        %% Bob leaves the room
        muc_light_helper:user_leave(?ROOM3, Bob, [{Alice, owner}, {Kate, member}]),
        %% Alice and Kate have message in groupchats
        check_inbox(Alice, [#conv{unread = 0, from = AliceRoomJid, to = AliceJid, content = Msg}]),
        check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid, to = KateJid, content = Msg}]),
        %% Bob doesnt have a conversation in inbox
        check_inbox(Bob, [])
      end).


%% this test combines options:
%% ...
%%{aff_changes, true},
%%{remove_on_kicked, false},
no_stored_and_remain_after_kicked(Config) ->
    escalus:story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        AliceJid = inbox_helper:to_bare_lower(Alice),
        KateJid = inbox_helper:to_bare_lower(Kate),
        BobJid = inbox_helper:to_bare_lower(Bob),
        RoomJid = room_bin_jid(?ROOM4),
        AliceRoomJid = <<RoomJid/binary, "/", AliceJid/binary>>,
        Msg = <<"Hi all">>,
        Stanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomJid, Msg), <<"33">>),
        %% Alice sends a message
        escalus:send(Alice, Stanza),
        R0 = escalus:wait_for_stanza(Alice),
        R1 = escalus:wait_for_stanza(Bob),
        R2 = escalus:wait_for_stanza(Kate),
        escalus:assert(is_groupchat_message, R0),
        escalus:assert(is_groupchat_message, R1),
        escalus:assert(is_groupchat_message, R2),
        %% Bob leaves the room
        muc_light_helper:user_leave(?ROOM4, Bob, [{Alice, owner}, {Kate, member}]),
        %% Alice and Kate have message in groupchats
        check_inbox(Alice, [#conv{unread = 0, from = AliceRoomJid, to = AliceJid, content = Msg}]),
        check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid, to = KateJid, content = Msg}]),
        %% Bob have a conversation in inbox. First unread is message from Alice, the second the affiliation change
        check_inbox(Bob, [#conv{ unread = 2, from = RoomJid, to = BobJid,
                               verify = fun inbox_helper:verify_is_none_aff_change/2}])
      end).


groupchat_markers_one_reset_room_created(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        Msg = <<"Welcome guys">>,
        RoomName = <<"markers_room">>,
        RoomJid = room_bin_jid(RoomName),
        AliceJid = inbox_helper:to_bare_lower(Alice),
        AliceRoomJid = <<RoomJid/binary,"/", AliceJid/binary>>,
        BobJid = inbox_helper:to_bare_lower(Bob),
        KateJid = inbox_helper:to_bare_lower(Kate),
        inbox_helper:create_room_send_msg_check_inbox(Alice, [Bob, Kate], RoomName, Msg, <<"1-id">>),
        %% Now Bob sends marker
        inbox_helper:mark_last_muclight_message(Bob, [Alice, Bob, Kate]),
        %% The crew ask for inbox second time. Only Kate has unread messages
        check_inbox(Alice,[#conv{unread = 0, from = AliceRoomJid, to = AliceJid, content = Msg}]),
        check_inbox(Kate, [#conv{unread = 1, from = AliceRoomJid, to = KateJid, content = Msg}]),
        check_inbox(Bob, [#conv{unread = 0, from = AliceRoomJid, to = BobJid, content = Msg}])
      end).

groupchat_markers_all_reset_room_created(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomName = <<"markers_room2">>,
        AliceJid = inbox_helper:to_bare_lower(Alice),
        RoomJid = room_bin_jid(RoomName),
        AliceRoomJid = <<RoomJid/binary,"/", AliceJid/binary>>,
        Msg = <<"Mark me!">>,
        inbox_helper:create_room_send_msg_check_inbox(Alice, [Bob, Kate], RoomName, Msg, <<"2-id">>),
        [inbox_helper:mark_last_muclight_message(U, [Alice, Bob, Kate]) || U <- [Bob, Kate]],
        inbox_helper:foreach_check_inbox([Bob, Kate, Alice], 0, AliceRoomJid, Msg)
      end).

system_message_is_correctly_avoided(Config) ->
    escalus:story(Config, [{alice, 1}, {alice_bis, 1}, {bob, 1}], fun(Alice, AliceBis, Bob) ->
        %% Variables
        Id = <<"MyID">>,
        Msg1 = <<"Hi Room!">>,
        Msg2 = <<"How are you?">>,
        Users = [Alice, AliceBis, Bob],
        InitOccupants = [{M, member} || M <- [AliceBis, Bob]],
        Room = atom_to_binary(?FUNCTION_NAME, utf8),
        BobJid = inbox_helper:to_bare_lower(Bob),
        AliceJid = inbox_helper:to_bare_lower(Alice),
        AliceBisJid = inbox_helper:to_bare_lower(AliceBis),
        RoomJid = room_bin_jid(Room),
        %% Given a room
        muc_light_helper:given_muc_light_room(Room, Alice, InitOccupants),
        BobRoomJid = <<RoomJid/binary,"/", BobJid/binary>>,
        Stanza1 = escalus_stanza:set_id(escalus_stanza:groupchat_to(RoomJid, Msg1), Id),
        %% Alice sends msg to room
        escalus:send(Alice, Stanza1),
        [ escalus:assert(is_groupchat_message, escalus:wait_for_stanza(User)) || User <- Users],
        %% Bob sends second message
        Stanza2 = escalus_stanza:set_id(escalus_stanza:groupchat_to(RoomJid, Msg2), Id),
        escalus:send(Bob, Stanza2),
        [ escalus:assert(is_groupchat_message, escalus:wait_for_stanza(User)) || User <- Users],
        %% Alice has one unread message (from Bob)
        check_inbox(Alice, [#conv{unread = 1, from = BobRoomJid, to = AliceJid, content = Msg2}]),
        %% Bob has 0 unread messages because he sent the last message
        check_inbox(Bob, [#conv{unread = 0, from = BobRoomJid, to = BobJid, content = Msg2}]),
        %% AliceBis has 2 unread messages (from Alice and Bob) and does not have the affiliation
        check_inbox(AliceBis, [#conv{unread = 2, from = BobRoomJid, to = AliceBisJid, content = Msg2}])
      end).

%%--------------------------------------------------------------------
%% Classic MUC tests
%%--------------------------------------------------------------------

simple_groupchat_stored_in_all_inbox_muc(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomConfig = muc_helper:start_room(Config, extract_user_specs(Alice), muc_helper:fresh_room_name(), <<"some_friendly_name">>, default),
        Users = [Alice, Bob, Kate],
        Msg = <<"Hi Room!">>,
        Id = <<"MyID">>,
        Room = ?config(room, RoomConfig),
        RoomAddr = muc_helper:room_address(Room),

        inbox_helper:enter_room(Room, Users),
        inbox_helper:make_members(Room, Alice, Users -- [Alice]),
        Stanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomAddr, Msg), Id),
        escalus:send(Bob, Stanza),
        inbox_helper:wait_for_groupchat_msg(Users),
        [AliceJid, BobJid, KateJid] = lists:map(fun inbox_helper:to_bare_lower/1, Users),
        BobRoomJid = muc_helper:room_address(Room, inbox_helper:nick(Bob)),
        %% Bob has 0 unread messages
        check_inbox(Bob, [#conv{unread = 0, from = BobRoomJid, to = BobJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Alice and Kate have one conv with 1 unread message
        check_inbox(Alice,[#conv{unread = 1, from = BobRoomJid, to = AliceJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        check_inbox(Kate, [#conv{unread = 1, from = BobRoomJid, to = KateJid, content = Msg}],
                    #{}, #{case_sensitive => true})
      end).

simple_groupchat_stored_in_offline_users_inbox_muc(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomConfig = muc_helper:start_room(Config, extract_user_specs(Alice), muc_helper:fresh_room_name(), <<"some_friendly_name">>, default),
        Users = [Alice, Bob, Kate],
        Msg = <<"Hi Room!">>,
        Id = <<"MyID">>,
        Room = ?config(room, RoomConfig),
        RoomAddr = muc_helper:room_address(Room),

        inbox_helper:enter_room(Room, Users),
        inbox_helper:make_members(Room, Alice, Users -- [Alice]),
        inbox_helper:leave_room(Kate, Room, Users),
        Stanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomAddr, Msg), Id),
        escalus:send(Bob, Stanza),
        inbox_helper:wait_for_groupchat_msg(Users -- [Kate]),

        [AliceJid, BobJid, KateJid] = lists:map(fun inbox_helper:to_bare_lower/1, Users),
        BobRoomJid = muc_helper:room_address(Room, inbox_helper:nick(Bob)),
        %% Bob has 0 unread messages
        check_inbox(Bob, [#conv{unread = 0, from = BobRoomJid, to = BobJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Alice and Kate have one conv with 1 unread message
        check_inbox(Alice, [#conv{unread = 1, from = BobRoomJid, to = AliceJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        check_inbox(Kate, [#conv{unread = 1, from = BobRoomJid, to = KateJid, content = Msg}],
                    #{}, #{case_sensitive => true})
      end).


unread_count_is_the_same_after_going_online_again(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomConfig = muc_helper:start_room(Config, extract_user_specs(Alice), muc_helper:fresh_room_name(), <<"some_friendly_name">>, default),
        Users = [Alice, Bob, Kate],
        Msg = <<"Hi Room!">>,
        Id = <<"MyID">>,
        Room = ?config(room, RoomConfig),
        RoomAddr = muc_helper:room_address(Room),

        inbox_helper:enter_room(Room, Users),
        inbox_helper:make_members(Room, Alice, Users -- [Alice]),
        inbox_helper:leave_room(Kate, Room, Users),
        Stanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomAddr, Msg), Id),
        escalus:send(Bob, Stanza),
        inbox_helper:wait_for_groupchat_msg(Users -- [Kate]),
        inbox_helper:enter_room(Room, Kate, Users -- [Kate], 1),
        [AliceJid, BobJid, KateJid] = lists:map(fun inbox_helper:to_bare_lower/1, Users),
        BobRoomJid = muc_helper:room_address(Room, inbox_helper:nick(Bob)),
        %% Bob has 0 unread messages
        check_inbox(Bob, [#conv{unread = 0, from = BobRoomJid, to = BobJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Alice and Kate have one conv with 1 unread message
        check_inbox(Alice, [#conv{unread = 1, from = BobRoomJid, to = AliceJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        check_inbox(Kate, [#conv{unread = 1, from = BobRoomJid, to = KateJid, content = Msg}],
                    #{}, #{case_sensitive => true})
    end).

unread_count_is_reset_after_sending_chatmarker(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomConfig = muc_helper:start_room(Config, extract_user_specs(Alice), muc_helper:fresh_room_name(), <<"some_friendly_name">>, default),
        Users = [Alice, Bob, Kate],
        Msg = <<"Hi Room!">>,
        Id = <<"MyID">>,
        Room = ?config(room, RoomConfig),
        RoomAddr = muc_helper:room_address(Room),

        inbox_helper:enter_room(Room, Users),
        inbox_helper:make_members(Room, Alice, Users -- [Alice]),
        Stanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomAddr, Msg), Id),
        escalus:send(Bob, Stanza),
        inbox_helper:wait_for_groupchat_msg(Users),
        ChatMarkerWOType = escalus_stanza:chat_marker(RoomAddr, <<"displayed">>, Id),
        ChatMarker = escalus_stanza:setattr(ChatMarkerWOType, <<"type">>, <<"groupchat">>),
        %% User marks last message
        escalus:send(Kate, ChatMarker),
        inbox_helper:wait_for_groupchat_msg(Users),

        [AliceJid, BobJid, KateJid] = lists:map(fun inbox_helper:to_bare_lower/1, Users),
        BobRoomJid = muc_helper:room_address(Room, inbox_helper:nick(Bob)),
        %% Bob has 0 unread messages
        check_inbox(Bob, [#conv{unread = 0, from = BobRoomJid, to = BobJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Alice have one conv with 1 unread message
        check_inbox(Alice, [#conv{unread = 1, from = BobRoomJid, to = AliceJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Kate has 0 unread messages
        check_inbox(Kate, [#conv{unread = 0, from = BobRoomJid, to = KateJid, content = Msg}],
                    #{}, #{case_sensitive => true})
      end).

non_reset_marker_should_not_affect_muc_inbox(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomConfig = muc_helper:start_room(Config, extract_user_specs(Alice), muc_helper:fresh_room_name(), <<"some_friendly_name">>, default),
        % %% GIVEN
        Users = [Alice, Bob, Kate],
        Msg = <<"Hi Room!">>,
        Id = <<"MyID">>,
        Room = ?config(room, RoomConfig),
        RoomAddr = muc_helper:room_address(Room),

        % %% WHEN
        inbox_helper:enter_room(Room, Users),
        inbox_helper:make_members(Room, Alice, Users -- [Alice]),
        Stanza = escalus_stanza:set_id(escalus_stanza:groupchat_to(RoomAddr, Msg), Id),
        escalus:send(Bob, Stanza),
        inbox_helper:wait_for_groupchat_msg(Users),
        % %% AND MARKED WRONG
        KateChatMarkerWOType = escalus_stanza:chat_marker(RoomAddr,<<"acknowledged">>, Id),
        KateChatMarker = escalus_stanza:setattr(KateChatMarkerWOType, <<"type">>, <<"groupchat">>),
        escalus:send(Kate, KateChatMarker),
        inbox_helper:wait_for_groupchat_msg(Users),

        [AliceJid, BobJid, KateJid] = lists:map(fun inbox_helper:to_bare_lower/1, Users),
        BobRoomJid = muc_helper:room_address(Room, inbox_helper:nick(Bob)),
        % %% THEN
        %% Bob has 0 unread messages
        check_inbox(Bob, [#conv{unread = 0, from = BobRoomJid, to = BobJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Alice have one conv with 1 unread message
        check_inbox(Alice, [#conv{unread = 1, from = BobRoomJid, to = AliceJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Kate has 1 unread messages
        check_inbox(Kate, [#conv{unread = 1, from = BobRoomJid, to = KateJid, content = Msg}],
                    #{}, #{case_sensitive => true})
      end).

unread_count_is_reset_after_sending_reset_stanza(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomConfig = muc_helper:start_room(Config, extract_user_specs(Alice), muc_helper:fresh_room_name(), <<"some_friendly_name">>, default),
        % %% WITH
        Users = [Alice, Bob, Kate],
        Msg = <<"Hi Room!">>,
        Id = <<"MyID">>,
        Room = ?config(room, RoomConfig),
        RoomAddr = muc_helper:room_address(Room),
        % %% PROVIDED
        inbox_helper:enter_room(Room, Users),
        inbox_helper:make_members(Room, Alice, Users -- [Alice]),
        % %% WHEN A MESSAGE IS SENT
        Stanza = escalus_stanza:set_id(
          escalus_stanza:groupchat_to(RoomAddr, Msg), Id),
        escalus:send(Bob, Stanza),
        inbox_helper:wait_for_groupchat_msg(Users),
        % %% AND WHEN SEND RESET FOR ROOM
        inbox_helper:reset_inbox(Kate, RoomAddr),

        [AliceJid, BobJid, KateJid] = lists:map(fun inbox_helper:to_bare_lower/1, Users),
        BobRoomJid = muc_helper:room_address(Room, inbox_helper:nick(Bob)),
        %% Bob has 0 unread messages
        check_inbox(Bob, [#conv{unread = 0, from = BobRoomJid, to = BobJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Alice have one conv with 1 unread message
        check_inbox(Alice, [#conv{unread = 1, from = BobRoomJid, to = AliceJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Kate has 0 unread messages
        check_inbox(Kate, [#conv{unread = 0, from = BobRoomJid, to = KateJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        inbox_helper:assert_has_no_stanzas([Alice, Bob, Kate])
      end).

private_messages_are_handled_as_one2one(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        RoomConfig = muc_helper:start_room(Config, extract_user_specs(Alice), muc_helper:fresh_room_name(), <<"some_friendly_name">>, default),
        Users = [Alice, Bob, Kate],
        Msg = <<"Hi Room!">>,
        Id = <<"MyID">>,
        Room = ?config(room, RoomConfig),
        BobRoomJid = muc_helper:room_address(Room, inbox_helper:nick(Bob)),
        KateRoomJid = muc_helper:room_address(Room, inbox_helper:nick(Kate)),

        inbox_helper:enter_room(Room, Users),
        inbox_helper:make_members(Room, Alice, Users -- [Alice]),
        Stanza = escalus_stanza:set_id(
          escalus_stanza:chat_to(BobRoomJid, Msg), Id),
        escalus:send(Kate, Stanza),
        _BobsPrivMsg = escalus:wait_for_stanza(Bob),

        KateJid = inbox_helper:to_bare_lower(Kate),
        %% Bob has 1 unread message
        check_inbox(Bob, [#conv{unread = 1, from = KateRoomJid, to = BobRoomJid, content = Msg}],
                    #{}, #{case_sensitive => true}),
        %% Alice gets nothing
        check_inbox(Alice, []),
        %% Kate has 1 conv with 0 unread messages
        check_inbox(Kate, [#conv{unread = 0, from = KateJid, to = BobRoomJid, content = Msg}],
                    #{}, #{case_sensitive => true, check_resource => false})
      end).

%%--------------------------------------------------------------------
%% Timestamp-related tests
%%--------------------------------------------------------------------

timestamp_is_updated_on_new_message(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}], fun(Alice, Bob) ->
         Msg1 = escalus_stanza:chat_to(Bob, <<"Hello Bob">>),
         Msg2 = escalus_stanza:chat_to(Bob, <<"Are you there?">>),

         escalus:send(Alice, Msg1),
         _M1 = escalus:wait_for_stanza(Bob),

         %% We capture a timestamp after first message
         [Item1] = inbox_helper:get_inbox(Alice, #{count => 1}),
         TStamp1 = inbox_helper:timestamp_from_item(Item1),

         escalus:send(Alice, Msg2),
         _M2 = escalus:wait_for_stanza(Bob),

         %% Timestamp after second message must be higher
         [Item2] = inbox_helper:get_inbox(Alice, #{count => 1}),

         TStamp2 = inbox_helper:timestamp_from_item(Item2),

         case TStamp2 > TStamp1 of
             true -> ok;
             false -> error(#{ type => timestamp_is_not_greater,
                               item1 => Item1,
                               item2 => Item2,
                               tstamp1 => TStamp1,
                               tstamp2 => TStamp2 })
         end
  end).

order_by_timestamp_ascending(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        #{ Alice := AliceConvs, Bob := BobConvs, Kate := KateConvs } =
        given_conversations_between(Alice, [Bob, Kate]),

        %% Alice has two conversations in her inbox (no unread messages)
        %% check_inbox will reverse conversation list automatically
        check_inbox(Alice, AliceConvs, #{ order => asc }, #{}),

        %% Kate has one conversation with one unread
        check_inbox(Kate, KateConvs),

        %% Bob has one conversation with one unread
        check_inbox(Bob, BobConvs)
      end).

get_by_timestamp_range(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        #{ Alice := AliceConvs, time_before := TimeBefore } =
        given_conversations_between(Alice, [Bob, Kate]),

        ConvWithBob = lists:keyfind(Bob, #conv.to, AliceConvs),
        TimeAfterBob = ConvWithBob#conv.time_after,

        %% Between given timestamps we have only one conversation: with Bob
        check_inbox(Alice, [ConvWithBob], #{ start => TimeBefore, 'end' => TimeAfterBob }, #{})
    end).

get_with_start_timestamp(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        #{ Alice := AliceConvs } =
        given_conversations_between(Alice, [Bob, Kate]),

        ConvWithBob = lists:keyfind(Bob, #conv.to, AliceConvs),
        TimeAfterBob = ConvWithBob#conv.time_after,
        ConvWithKate = lists:keyfind(Kate, #conv.to, AliceConvs),

        %% After given timestamp we have only one conversation: with Kate
        check_inbox(Alice, [ConvWithKate], #{ start => TimeAfterBob }, #{})
    end).

get_with_end_timestamp(Config) ->
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}, {kate, 1}], fun(Alice, Bob, Kate) ->
        #{ Alice := AliceConvs } =
        given_conversations_between(Alice, [Bob, Kate]),

        ConvWithBob = lists:keyfind(Bob, #conv.to, AliceConvs),
        TimeAfterBob = ConvWithBob#conv.time_after,
        %% Before given timestamp we have only one conversation: with Bob
        %% TODO: Improve this test to store 3+ conversations in Alice's inbox
        check_inbox(Alice, [ConvWithBob], #{ 'end' => TimeAfterBob }, #{})
    end).
