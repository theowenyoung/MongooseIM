%% @doc Config parsing and processing for the TOML format
-module(mongoose_config_parser_toml).

-behaviour(mongoose_config_parser).

-export([parse_file/1]).

-ifdef(TEST).
-export([parse/1,
         extract_errors/1]).
-endif.

-include("mongoose_config_spec.hrl").

%% Input: TOML parsed by tomerl
-type toml_key() :: binary().
-type toml_value() :: tomerl:value().
-type toml_section() :: tomerl:section().

%% Output: list of config records, containing key-value pairs
-type option_value() :: atom() | binary() | string() | float(). % parsed leaf value
-type config_part() :: term(). % any part of a top-level option value, may contain config errors
-type top_level_config() :: {mongoose_config:key(), mongoose_config:value()}.
-type config_error() :: #{class := error, what := atom(), text := string(), any() => any()}.
-type config() :: top_level_config() | config_error().

-type list_processor() :: fun((path(), [config_part()]) -> config_part())
                        | fun(([config_part()]) -> config_part()).

-type processor() :: fun((path(), config_part()) -> config_part())
                   | fun((config_part()) -> config_part()).

-type step() :: parse | validate | process | format.

%% Path from the currently processed config node to the root
%%   - toml_key(): key in a toml_section()
%%   - item: item in a list
%%   - {host, Host}: item in the list of hosts in host_config
-type path() :: [toml_key() | item | {host, jid:server()}].

-export_type([toml_key/0, toml_value/0, toml_section/0,
              option_value/0, config/0, config_error/0, config_part/0,
              list_processor/0, processor/0]).

-spec parse_file(FileName :: string()) -> mongoose_config_parser:state().
parse_file(FileName) ->
    case tomerl:read_file(FileName) of
        {ok, Content} ->
            process(Content);
        {error, Error} ->
            Text = tomerl:format_error(Error),
            error(config_error([#{what => toml_parsing_failed, text => Text}]))
    end.

-spec process(toml_section()) -> mongoose_config_parser:state().
process(Content) ->
    Config = parse(Content),
    Hosts = proplists:get_value(hosts, Config, []),
    HostTypes = proplists:get_value(host_types, Config, []),
    Opts = unfold_globals(Config, Hosts ++ HostTypes),
    case extract_errors(Opts) of
        [] ->
            build_state(Hosts, HostTypes, Opts);
        Errors ->
            error(config_error(Errors))
    end.

%% @doc Repeat global options for each host type for simpler lookup
%% Put them at the end so host_config can override them
%% Options with tags (shaper, acl, access) are left as globals as they can be set on both levels
-spec unfold_globals([config()], [mongooseim:host_type()]) -> [config()].
unfold_globals(Config, AllHostTypes) ->
    {GlobalOpts, Opts} = lists:partition(fun is_global_to_unfold/1, Config),
    Opts ++ [{{Key, HostType}, Value} || {{Key, global}, Value} <- GlobalOpts,
                                         HostType <- AllHostTypes].

is_global_to_unfold({{_Key, global}, _Value}) -> true;
is_global_to_unfold(_) -> false.

config_error(Errors) ->
    {config_error, "Could not read the TOML configuration file", Errors}.

-spec parse(toml_section()) -> [config()].
parse(Content) ->
    handle([], Content, mongoose_config_spec:root()).

%% TODO replace with binary_to_existing_atom where possible, prevent atom leak
b2a(B) -> binary_to_atom(B, utf8).

-spec ensure_keys([toml_key()], toml_section()) -> any().
ensure_keys(Keys, Section) ->
    case lists:filter(fun(Key) -> not maps:is_key(Key, Section) end, Keys) of
        [] -> ok;
        MissingKeys -> error(#{what => missing_mandatory_keys, missing_keys => MissingKeys})
    end.

-spec parse_section(path(), toml_section(), mongoose_config_spec:config_section()) ->
          [config_part()].
parse_section(Path, M, #section{items = Items, defaults = Defaults}) ->
    FilteredDefaults = maps:filter(fun(K, _V) -> not maps:is_key(K, M) end, Defaults),
    ProcessedConfig = maps:map(fun(K, V) -> handle([K|Path], V, get_spec_for_key(K, Items)) end, M),
    ProcessedDefaults = maps:map(fun(K, V) -> handle_default([K|Path], V, maps:get(K, Items)) end,
                                 FilteredDefaults),
    lists:flatmap(fun({_K, ConfigParts}) -> ConfigParts end,
                  lists:keysort(1, maps:to_list(maps:merge(ProcessedDefaults, ProcessedConfig)))).

-spec get_spec_for_key(toml_key(), map()) -> mongoose_config_spec:config_node().
get_spec_for_key(Key, Items) ->
    case maps:is_key(Key, Items) of
        true ->
            maps:get(Key, Items);
        false ->
            case maps:find(default, Items) of
                {ok, Spec} -> Spec;
                error -> error(#{what => unexpected_key, key => Key})
            end
    end.

-spec parse_list(path(), [toml_value()], mongoose_config_spec:config_list()) -> [config_part()].
parse_list(Path, L, #list{items = ItemSpec}) ->
    lists:flatmap(fun(Elem) ->
                          Key = item_key(Path, Elem),
                          handle([Key|Path], Elem, ItemSpec)
                  end, L).

-spec handle(path(), toml_value(), mongoose_config_spec:config_node()) -> [config_part()].
handle(Path, Value, Spec) ->
    handle(Path, Value, Spec, [parse, validate, process, format]).

-spec handle_default(path(), toml_value(), mongoose_config_spec:config_node()) -> [config_part()].
handle_default(Path, Value, Spec) ->
    handle(Path, Value, Spec, [format]).

-spec handle(path(), toml_value(), mongoose_config_spec:config_node(), [step()]) -> [config_part()].
handle(Path, Value, Spec, Steps) ->
    lists:foldl(fun(_, [#{what := _, class := error}] = Error) ->
                        Error;
                   (Step, Acc) ->
                        try_step(Step, Path, Value, Acc, Spec)
                end, Value, Steps).

-spec handle_step(step(), path(), toml_value(), mongoose_config_spec:config_node()) ->
          config_part().
handle_step(parse, Path, Value, Spec) ->
    ParsedValue = case Spec of
                      #section{} when is_map(Value) ->
                          check_required_keys(Spec, Value),
                          validate_keys(Spec, Value),
                          parse_section(Path, Value, Spec);
                      #list{} when is_list(Value) ->
                          parse_list(Path, Value, Spec);
                      #option{type = Type} when not is_list(Value), not is_map(Value) ->
                          convert(Value, Type)
                  end,
    case extract_errors(ParsedValue) of
        [] -> ParsedValue;
        Errors -> Errors
    end;
handle_step(validate, _Path, ParsedValue, Spec) ->
    validate(ParsedValue, Spec),
    ParsedValue;
handle_step(process, Path, ParsedValue, Spec) ->
    process(Path, ParsedValue, process_spec(Spec));
handle_step(format, Path, ProcessedValue, Spec) ->
    format(Path, ProcessedValue, Spec).

-spec check_required_keys(mongoose_config_spec:config_section(), toml_section()) -> any().
check_required_keys(#section{required = all, items = Items}, Section) ->
    ensure_keys(maps:keys(Items), Section);
check_required_keys(#section{required = Required}, Section) ->
    ensure_keys(Required, Section).

-spec validate_keys(mongoose_config_spec:config_section(), toml_section()) -> any().
validate_keys(#section{validate_keys = Validator}, Section) ->
    lists:foreach(fun(Key) ->
                          mongoose_config_validator:validate(b2a(Key), atom, Validator)
                  end, maps:keys(Section)).

-spec validate(config_part(), mongoose_config_spec:config_node()) -> any().
validate(Value, #section{validate = Validator}) ->
    mongoose_config_validator:validate_section(Value, Validator);
validate(Value, #list{validate = Validator}) ->
    mongoose_config_validator:validate_list(Value, Validator);
validate(Value, #option{type = Type, validate = Validator}) ->
    mongoose_config_validator:validate(Value, Type, Validator).

-spec process_spec(mongoose_config_spec:config_section() |
                   mongoose_config_spec:config_list()) -> undefined | list_processor();
                  (mongoose_config_spec:config_option()) -> undefined | processor().
process_spec(#section{process = Process}) -> Process;
process_spec(#list{process = Process}) -> Process;
process_spec(#option{process = Process}) -> Process.

-spec process(path(), config_part(), undefined | processor()) -> config_part().
process(_Path, V, undefined) -> V;
process(_Path, V, F) when is_function(F, 1) -> F(V);
process(Path, V, F) when is_function(F, 2) -> F(Path, V).

-spec convert(toml_value(), mongoose_config_spec:option_type()) -> option_value().
convert(V, boolean) when is_boolean(V) -> V;
convert(V, binary) when is_binary(V) -> V;
convert(V, string) -> binary_to_list(V);
convert(V, atom) -> b2a(V);
convert(<<"infinity">>, int_or_infinity) -> infinity; %% TODO maybe use TOML '+inf'
convert(V, int_or_infinity) when is_integer(V) -> V;
convert(V, int_or_atom) when is_integer(V) -> V;
convert(V, int_or_atom) -> b2a(V);
convert(V, integer) when is_integer(V) -> V;
convert(V, float) when is_float(V) -> V.

-spec format(path(), config_part(), mongoose_config_spec:config_node()) -> [config_part()].
format(Path, V, #section{format = Format, format_items = FormatItems}) ->
    wrap(Path, format_items(Path, V, FormatItems), Format);
format(Path, V, #list{format = Format, format_items = FormatItems}) ->
    wrap(Path, format_items(Path, V, FormatItems), Format);
format(Path, V, #option{format = Format}) ->
    wrap(Path, V, Format).

-spec format_items(path(), config_part(), mongoose_config_spec:format_items()) -> config_part().
format_items(_Path, KVs, map) ->
    Keys = lists:map(fun({K, _}) -> K end, KVs),
    mongoose_config_validator:validate_list(Keys, unique),
    maps:from_list(KVs);
format_items(Path, KVs, {foreach, Format}) ->
    Keys = lists:map(fun({K, _}) -> K end, KVs),
    mongoose_config_validator:validate_list(Keys, unique),
    lists:flatmap(fun({K, V}) -> wrap(Path, V, {Format, K}) end, KVs);
format_items(_Path, Value, none) ->
    Value.

-spec wrap(path(), config_part(), mongoose_config_spec:format()) -> [config_part()].
wrap([Key|_] = Path, V, host_config) ->
    wrap(Path, V, {host_config, b2a(Key)});
wrap([Key|_] = Path, V, global_config) ->
    wrap(Path, V, {global_config, b2a(Key)});
wrap(Path, V, {host_config, Key}) ->
    [{{Key, get_host(Path)}, V}];
wrap(Path, V, {global_config, Key}) ->
    global = get_host(Path),
    [{Key, V}];
wrap([Key|_] = Path, V, {host_or_global_config, Tag}) ->
    [{{Tag, b2a(Key), get_host(Path)}, V}];
wrap([item|_] = Path, V, default) ->
    wrap(Path, V, item);
wrap([Key|_] = Path, V, default) ->
    wrap(Path, V, {kv, b2a(Key)});
wrap(_Path, V, {kv, Key}) ->
    [{Key, V}];
wrap(_Path, V, item) ->
    [V];
wrap(_Path, _V, skip) ->
    [];
wrap([Key|_], V, prepend_key) ->
    L = [b2a(Key) | tuple_to_list(V)],
    [list_to_tuple(L)];
wrap(_Path, V, none) when is_list(V) ->
    V.

-spec get_host(path()) -> jid:server() | global.
get_host(Path) ->
    case lists:reverse(Path) of
        [<<"host_config">>, {host, Host} | _] -> Host;
        _ -> global
    end.

-spec try_step(step(), path(), toml_value(), term(),
               mongoose_config_spec:config_node()) -> config_part().
try_step(Step, Path, Value, Acc, Spec) ->
    try
        handle_step(Step, Path, Acc, Spec)
    catch error:Reason:Stacktrace ->
            BasicFields = #{what => toml_processing_failed,
                            class => error,
                            stacktrace => Stacktrace,
                            text => error_text(Step),
                            toml_path => path_to_string(Path),
                            toml_value => Value},
            ErrorFields = error_fields(Reason),
            [maps:merge(BasicFields, ErrorFields)]
    end.

-spec error_text(step()) -> string().
error_text(parse) -> "Malformed option in the TOML configuration file";
error_text(validate) -> "Incorrect option value in the TOML configuration file";
error_text(process) -> "Unable to process a value the TOML configuration file";
error_text(format) -> "Unable to format an option in the TOML configuration file".

-spec error_fields(any()) -> map().
error_fields(#{what := Reason} = M) -> maps:remove(what, M#{reason => Reason});
error_fields(Reason) -> #{reason => Reason}.

-spec path_to_string(path()) -> string().
path_to_string(Path) ->
    Items = lists:flatmap(fun node_to_string/1, lists:reverse(Path)),
    string:join(Items, ".").

node_to_string(item) -> [];
node_to_string({host, _}) -> [];
node_to_string(Node) -> [binary_to_list(Node)].

-spec item_key(path(), toml_value()) -> {host, jid:server()} | item.
item_key([<<"host_config">>], #{<<"host_type">> := Host}) -> {host, Host};
item_key([<<"host_config">>], #{<<"host">> := Host}) -> {host, Host};
item_key(_, _) -> item.

%% Processing of the parsed options

-spec build_state([jid:server()], [jid:server()], [top_level_config()]) ->
          mongoose_config_parser:state().
build_state(Hosts, HostTypes, Opts) ->
    lists:foldl(fun(F, StateIn) -> F(StateIn) end,
                mongoose_config_parser:new_state(),
                [fun(S) -> mongoose_config_parser:set_hosts(Hosts, S) end,
                 fun(S) -> mongoose_config_parser:set_host_types(HostTypes, S) end,
                 fun(S) -> mongoose_config_parser:set_opts(Opts, S) end,
                 fun mongoose_config_parser:dedup_state_opts/1,
                 fun mongoose_config_parser:add_dep_modules/1]).

%% Any nested config_part() may be a config_error() - this function extracts them all recursively
-spec extract_errors([config()]) -> [config_error()].
extract_errors(Config) ->
    extract(fun(#{what := _, class := error}) -> true;
               (_) -> false
            end, Config).

-spec extract(fun((config_part()) -> boolean()), config_part()) -> [config_part()].
extract(Pred, Data) ->
    case Pred(Data) of
        true -> [Data];
        false -> extract_items(Pred, Data)
    end.

-spec extract_items(fun((config_part()) -> boolean()), config_part()) -> [config_part()].
extract_items(Pred, L) when is_list(L) -> lists:flatmap(fun(El) -> extract(Pred, El) end, L);
extract_items(Pred, T) when is_tuple(T) -> extract_items(Pred, tuple_to_list(T));
extract_items(Pred, M) when is_map(M) -> extract_items(Pred, maps:to_list(M));
extract_items(_, _) -> [].
