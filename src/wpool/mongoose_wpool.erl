%%%-------------------------------------------------------------------
%%% @doc
%%% This is here because there are pool options which have to be given when calling
%%% the pool (selection strategy, timeout), while we want to set it once for the pool and not
%%% worry about them later, hence additional storage.
%%% @end
%%%-------------------------------------------------------------------
-module(mongoose_wpool).
-author("bartlomiej.gorny@erlang-solutions.com").
-include("mongoose.hrl").

-type call_timeout() :: pos_integer() | undefined.
-record(mongoose_wpool, {
          name :: pool_name(),
          atom_name :: wpool:name(),
          strategy :: wpool:strategy() | undefined,
          call_timeout :: call_timeout()
         }).
-dialyzer({no_match, start/4}).

%% API
-export([ensure_started/0,
         start/2, start/3, start/4, start/5,
         stop/0, stop/1, stop/2, stop/3,
         get_worker/1, get_worker/2, get_worker/3,
         call/2, call/3, call/4, call/5,
         cast/2, cast/3, cast/4, cast/5,
         get_pool_settings/3, get_pools/0, stats/3]).

-export([start_sup_pool/3]).
-export([start_configured_pools/0]).
-export([start_configured_pools/1]).
-export([start_configured_pools/2]).
-export([is_configured/1]).
-export([make_pool_name/3]).
-export([call_start_callback/2]).

%% Mostly for tests
-export([expand_pools/2]).

-ignore_xref([behaviour_info/1, call/2, cast/2, cast/3, expand_pools/2, get_worker/2,
              is_configured/2, is_configured/1, is_configured/1, start/2, start/3,
              start/5, start_configured_pools/1, start_configured_pools/2, stats/3,
              stop/1, stop/2]).

-type pool_type() :: redis | riak | http | rdbms | cassandra | elastic | generic
                     | rabbit | ldap.

%% Config scope
-type scope() :: global | host | mongooseim:host_type().
-type host_type_or_global() :: mongooseim:host_type_or_global().

-type tag() :: atom().
%% Name of a process
-type proc_name() :: atom().

%% ID of a pool. Used as a key for an ETS table
-type pool_name() :: {PoolType :: pool_type(),
                      HostType :: host_type_or_global(),
                      Tag :: tag()}.

-type pool_opts() :: [wpool:option()].
-type conn_opts() :: [{atom(), any()}].

-type pool_tuple_in() :: {PoolType :: pool_type(),
                          HostType :: scope(),
                          Tag :: tag(),
                          WpoolOpts :: pool_opts(),
                          ConnOpts :: conn_opts()}.
%% Pool tuple with expanded HostType argument
-type pool_tuple() :: {PoolType :: pool_type(),
                       %% does not contain `host' atom
                       HostType :: host_type_or_global(),
                       Tag :: tag(),
                       WpoolOpts :: pool_opts(),
                       ConnOpts :: conn_opts()}.
-type pool_error() :: {pool_not_started, term()}.
-type worker_result() :: {ok, pid()} | {error, pool_error()}.
-type pool_record_result() :: {ok, #mongoose_wpool{}} | {error, pool_error()}.
-type start_result() :: {ok, pid()} | {error, term()}.
-type stop_result() :: ok | term().

-export_type([pool_type/0]).
-export_type([tag/0]).
-export_type([scope/0]).
-export_type([proc_name/0]).
-export_type([pool_opts/0]).
-export_type([conn_opts/0]).

-type callback_fun() :: init | start | default_opts | is_supported_strategy | stop.

-callback init() -> ok | {error, term()}.
-callback start(scope(), tag(), WPoolOpts :: pool_opts(), ConnOpts :: conn_opts()) ->
    {ok, {pid(), proplists:proplist()}} | {ok, pid()} |
    {external, pid()} | {error, Reason :: term()}.
-callback default_opts() -> conn_opts().
-callback is_supported_strategy(Strategy :: wpool:strategy()) -> boolean().
-callback stop(scope(), tag()) -> ok.

-optional_callbacks([default_opts/0, is_supported_strategy/1]).

ensure_started() ->
    wpool:start(),
    case whereis(mongoose_wpool_sup) of
        undefined ->
            mongoose_wpool_sup:start_link();
        _ ->
            ok
    end,

    case ets:info(?MODULE) of
        undefined ->
            % we set heir here because the whole thing may be started by an ephemeral process
            ets:new(?MODULE, [named_table, public,
                {read_concurrency, true},
                {keypos, #mongoose_wpool.name},
                {heir, whereis(mongoose_wpool_sup), undefined}]);
        _ ->
            ok
    end.

start_configured_pools() ->
    Pools = mongoose_config:get_opt(outgoing_pools, []),
    start_configured_pools(Pools).

start_configured_pools(PoolsIn) ->
    start_configured_pools(PoolsIn, ?ALL_HOST_TYPES).

start_configured_pools(PoolsIn, HostTypes) ->
    [call_callback(init, PoolType, []) || PoolType <- get_unique_types(PoolsIn)],
    Pools = expand_pools(PoolsIn, HostTypes),
    [start(Pool) || Pool <- Pools].

-spec start(pool_tuple()) -> start_result().
start({PoolType, HostType, Tag, PoolOpts, ConnOpts}) ->
    start(PoolType, HostType, Tag, PoolOpts, ConnOpts).

-spec start(pool_type(), pool_opts()) -> start_result().
start(PoolType, PoolOpts) ->
    start(PoolType, global, PoolOpts).

-spec start(pool_type(), host_type_or_global(), pool_opts()) -> start_result().
start(PoolType, HostType, PoolOpts) ->
    start(PoolType, HostType, default, PoolOpts).

-spec start(pool_type(), host_type_or_global(), tag(),
            pool_opts()) -> start_result().
start(PoolType, HostType, Tag, PoolOpts) ->
    start(PoolType, HostType, Tag, PoolOpts, []).

-spec start(pool_type(), host_type_or_global(), tag(),
            pool_opts(), conn_opts()) -> start_result().
start(PoolType, HostType, Tag, PoolOpts, ConnOpts) ->
    {Opts0, WpoolOptsIn} = proplists:split(PoolOpts, [strategy, call_timeout]),
    Opts = lists:append(Opts0) ++ default_opts(PoolType),
    Strategy = proplists:get_value(strategy, Opts, best_worker),
    CallTimeout = proplists:get_value(call_timeout, Opts, 5000),
    %% If a callback doesn't explicitly blacklist a strategy, let's proceed.
    CallbackModule = make_callback_module_name(PoolType),
    case catch CallbackModule:is_supported_strategy(Strategy) of
        false ->
            error({strategy_not_supported, PoolType, HostType, Tag, Strategy});
        _ ->
            start(PoolType, HostType, Tag, WpoolOptsIn, ConnOpts, Strategy, CallTimeout)
    end.

-spec start(pool_type(), host_type_or_global(), tag(),
            pool_opts(), conn_opts(), wpool:strategy(), call_timeout()) ->
    start_result().
start(PoolType, HostType, Tag, WpoolOptsIn, ConnOpts, Strategy, CallTimeout) ->
    case mongoose_wpool_mgr:start(PoolType, HostType, Tag, WpoolOptsIn, ConnOpts) of
        {ok, Pid} ->
            ets:insert(?MODULE, #mongoose_wpool{name = {PoolType, HostType, Tag},
                                                atom_name = make_pool_name(PoolType, HostType, Tag),
                                                strategy = Strategy,
                                                call_timeout = CallTimeout}),
            {ok, Pid};
        {external, Pid} ->
            ets:insert(?MODULE, #mongoose_wpool{name = {PoolType, HostType, Tag},
                                                atom_name = make_pool_name(PoolType, HostType, Tag)
                                               }),
            {ok, Pid};
        Error ->
            Error
    end.

%% @doc this function starts the worker_pool's pool under a specific supervisor
%% in MongooseIM application.
%% It's needed for 2 reasons:
%% 1. We want to have a full control of all the pools and its restarts
%% 2. When a pool is started via wpool:start_pool it's supposed be called by a supervisor,
%%    if not, there is no way to stop the pool.
-spec start_sup_pool(pool_type(), proc_name(), [wpool:option()]) ->
    {ok, pid()} | {error, term()}.
start_sup_pool(PoolType, ProcName, WpoolOpts) ->
    SupName = mongoose_wpool_type_sup:name(PoolType),
    ChildSpec = #{id => ProcName,
                  start => {wpool, start_pool, [ProcName, WpoolOpts]},
                  restart => temporary,
                  type => supervisor,
                  modules => [wpool]},
    supervisor:start_child(SupName, ChildSpec).

-spec stop() -> term().
stop() ->
    [stop_pool(PoolName) || PoolName <- get_pools()].

-spec stop_pool(pool_name()) -> stop_result().
stop_pool({PoolType, HostType, Tag}) ->
    stop(PoolType, HostType, Tag).

-spec stop(pool_type()) -> stop_result().
stop(PoolType) ->
    stop(PoolType, global).

-spec stop(pool_type(), host_type_or_global()) -> stop_result().
stop(PoolType, HostType) ->
    stop(PoolType, HostType, default).

-spec stop(pool_type(), host_type_or_global(), tag()) -> stop_result().
stop(PoolType, HostType, Tag) ->
    try
        ets:delete(?MODULE, {PoolType, HostType, Tag}),
        call_callback(stop, PoolType, [HostType, Tag]),
        mongoose_wpool_mgr:stop(PoolType, HostType, Tag)
    catch
        C:R:S ->
            ?LOG_ERROR(#{what => pool_stop_failed,
                         pool_type => PoolType, server => HostType, pool_tag => Tag,
                         pool_key => {PoolType, HostType, Tag},
                         class => C, reason => R, stacktrace => S})
    end.

-spec is_configured(pool_type()) -> boolean().
is_configured(PoolType) ->
    Pools = mongoose_config:get_opt(outgoing_pools, []),
    lists:keymember(PoolType, 1, Pools).

-spec get_worker(pool_type()) -> worker_result().
get_worker(PoolType) ->
    get_worker(PoolType, global).

-spec get_worker(pool_type(), host_type_or_global()) -> worker_result().
get_worker(PoolType, HostType) ->
    get_worker(PoolType, HostType, default).

-spec get_worker(pool_type(), host_type_or_global(), tag()) -> worker_result().
get_worker(PoolType, HostType, Tag) ->
    case get_pool(PoolType, HostType, Tag) of
        {ok, #mongoose_wpool{strategy = Strategy} = Pool} ->
            Worker = wpool_pool:Strategy(make_pool_name(Pool)),
            {ok, whereis(Worker)};
        Err ->
            Err
    end.

call(PoolType, Request) ->
    call(PoolType, global, Request).

call(PoolType, HostType, Request) ->
    call(PoolType, HostType, default, Request).

call(PoolType, HostType, Tag, Request) ->
    case get_pool(PoolType, HostType, Tag) of
        {ok, #mongoose_wpool{strategy = Strategy, call_timeout = CallTimeout} = Pool} ->
            wpool:call(make_pool_name(Pool), Request, Strategy, CallTimeout);
        Err ->
            Err
    end.

call(PoolType, HostType, Tag, HashKey, Request) ->
    case get_pool(PoolType, HostType, Tag) of
        {ok, #mongoose_wpool{call_timeout = CallTimeout} = Pool} ->
            wpool:call(make_pool_name(Pool), Request, {hash_worker, HashKey}, CallTimeout);
        Err ->
            Err
    end.

cast(PoolType, Request) ->
    cast(PoolType, global, Request).

cast(PoolType, HostType, Request) ->
    cast(PoolType, HostType, default, Request).

cast(PoolType, HostType, Tag, Request) ->
    case get_pool(PoolType, HostType, Tag) of
        {ok, #mongoose_wpool{strategy = Strategy} = Pool} ->
            wpool:cast(make_pool_name(Pool), Request, Strategy);
        Err ->
            Err
    end.

cast(PoolType, HostType, Tag, HashKey, Request) ->
    case get_pool(PoolType, HostType, Tag) of
        {ok, #mongoose_wpool{} = Pool} ->
            wpool:cast(make_pool_name(Pool), Request, {hash_worker, HashKey});
        Err ->
            Err
    end.

-spec get_pool_settings(pool_type(), host_type_or_global(), tag()) ->
    #mongoose_wpool{} | undefined.
get_pool_settings(PoolType, HostType, Tag) ->
    case get_pool(PoolType, HostType, Tag) of
        {ok, PoolRec} -> PoolRec;
        {error, {pool_not_started, _}} -> undefined
    end.

-spec get_pools() -> [pool_name()].
get_pools() ->
    lists:map(fun(#mongoose_wpool{name = Name}) -> Name end, ets:tab2list(?MODULE)).

stats(PoolType, HostType, Tag) ->
    wpool:stats(make_pool_name(PoolType, HostType, Tag)).

-spec make_pool_name(pool_type(), scope(), tag()) -> proc_name().
make_pool_name(PoolType, HostType, Tag) when is_atom(HostType) ->
    make_pool_name(PoolType, atom_to_binary(HostType, utf8), Tag);
make_pool_name(PoolType, HostType, Tag) when is_binary(HostType) ->
    binary_to_atom(<<"mongoose_wpool$", (atom_to_binary(PoolType, utf8))/binary, $$,
                     HostType/binary, $$, (atom_to_binary(Tag, utf8))/binary>>, utf8).

make_pool_name(#mongoose_wpool{atom_name = undefined, name = {PoolType, HostType, Tag}}) ->
    make_pool_name(PoolType, HostType, Tag);
make_pool_name(#mongoose_wpool{atom_name = AtomName}) ->
    AtomName.

-spec call_start_callback(pool_type(), list()) -> term().
call_start_callback(PoolType, Args) ->
    call_callback(start, PoolType, Args).

-spec call_callback(callback_fun(), pool_type(), list()) -> term().
call_callback(CallbackFun, PoolType, Args) ->
    try
        CallbackModule = make_callback_module_name(PoolType),
        erlang:apply(CallbackModule, CallbackFun, Args)
    catch E:R:ST ->
          ?LOG_ERROR(#{what => pool_callback_failed,
                       pool_type => PoolType, callback_function => CallbackFun,
                       error => E, reason => R, stacktrace => ST}),
          {error, {callback_crashed, CallbackFun, E, R, ST}}
    end.

-spec make_callback_module_name(pool_type()) -> module().
make_callback_module_name(PoolType) ->
    Name = "mongoose_wpool_" ++ atom_to_list(PoolType),
    list_to_atom(Name).

-spec default_opts(pool_type()) -> conn_opts().
default_opts(PoolType) ->
    Mod = make_callback_module_name(PoolType),
    case erlang:function_exported(Mod, default_opts, 0) of
        true -> Mod:default_opts();
        false -> []
    end.

-spec expand_pools([pool_tuple_in()], [mongooseim:host_type()]) -> [pool_tuple()].
expand_pools(Pools, HostTypes) ->
    %% First we select only pools for a specific vhost
    HostSpecific = [{PoolType, HostType, Tag} ||
                     {PoolType, HostType, Tag, _, _} <- Pools,
                     is_binary(HostType)],
    %% Then we expand all pools with `host` as HostType parameter but using host specific configs
    %% if they were provided
    F = fun({PoolType, host, Tag, WpoolOpts, ConnOpts}) ->
                [{PoolType, HostType, Tag, WpoolOpts, ConnOpts} ||
                 HostType <- HostTypes,
                 not lists:member({PoolType, HostType, Tag}, HostSpecific)];
           (Other) -> [Other]
        end,
    lists:flatmap(F, Pools).

-spec get_unique_types([pool_tuple_in()]) -> [pool_type()].
get_unique_types(Pools) ->
    lists:usort([PoolType || {PoolType, _, _, _, _} <- Pools]).

-spec get_pool(pool_type(), host_type_or_global(), tag()) -> pool_record_result().
get_pool(PoolType, HostType, Tag) ->
    case ets:lookup(?MODULE, {PoolType, HostType, Tag}) of
        [] when is_binary(HostType) -> get_pool(PoolType, global, Tag);
        [] -> {error, {pool_not_started, {PoolType, HostType, Tag}}};
        [Pool] -> {ok, Pool}
    end.
