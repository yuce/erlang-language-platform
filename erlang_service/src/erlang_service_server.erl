%%==============================================================================
%% The server responsible for co-ordinating work
%%==============================================================================
-module(erlang_service_server).

%%==============================================================================
%% Behaviours
%%==============================================================================
-behaviour(gen_server).

%%==============================================================================
%% Exports
%%==============================================================================

-export([start_link/0]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).

%% API
-export([ get_docs/2, ct_info/1, elp_lint/3
]).

%%==============================================================================
%% Includes
%%==============================================================================

%%==============================================================================
%% Macros
%%==============================================================================
-define(SERVER, ?MODULE).

%%==============================================================================
%% Type Definitions
%%==============================================================================
-type state() :: #{io := erlang:group_leader()}.

%%==============================================================================
%% API
%%==============================================================================
-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, noargs, []).

get_docs(Data, DocOrigin) ->
    gen_server:cast(?SERVER, {get_docs, Data, DocOrigin}).

ct_info(Data) ->
    gen_server:cast(?SERVER, {ct_info, Data}).

elp_lint(Data, PostProcess, Deterministic) ->
    gen_server:cast(?SERVER, {elp_lint, Data, PostProcess, Deterministic}).

%%==============================================================================
%% gen_server callbacks
%%==============================================================================
-spec init(noargs) -> {ok, state()}.
init(noargs) ->
    State = #{io => erlang:group_leader()},
    {ok, State}.

-spec handle_call(any(), any(), state()) -> {reply, any(), state()}.
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast({get_docs, Data, DocOrigin}, State) ->
    spawn_link(fun() ->
        {Id, FileName} = binary_to_term(Data),
        try
            Result = erlang_service_edoc:run_get_docs(FileName, DocOrigin),
            gen_server:cast(?SERVER, {result, Id, Result})
        catch
            Class:Reason:StackTrace ->
                Formatted = erl_error:format_exception(Class, Reason, StackTrace),
                ExceptionData = unicode:characters_to_binary(Formatted),
                gen_server:cast(?SERVER, {exception, Id, ExceptionData})
        end
            end),
    {noreply, State};
handle_cast({ct_info, Data}, State) ->
    spawn_link(fun() ->
        {Id, Module, Filename, CompileOptions, ShouldRequestGroups} = binary_to_term(Data),
        try
            Result = erlang_service:ct_info(Module, Filename, CompileOptions, ShouldRequestGroups),
            gen_server:cast(?SERVER, {result, Id, Result})
        catch
            Class:Reason:StackTrace ->
                Formatted = erl_error:format_exception(Class, Reason, StackTrace),
                ExceptionData = unicode:characters_to_binary(Formatted),
                gen_server:cast(?SERVER, {exception, Id, ExceptionData})
        end
    end),
    {noreply, State};
handle_cast({elp_lint, Data, PostProcess, Deterministic}, State) ->
    spawn_link(fun() ->
        {Id, FileName, Options} = binary_to_term(Data),
        try
            Result = erlang_service:run_elp_lint(FileName, Options, PostProcess, Deterministic),
            gen_server:cast(?SERVER, {result, Id, Result})
        catch
            Class:Reason:StackTrace ->
                Formatted = erl_error:format_exception(Class, Reason, StackTrace),
                ExceptionData = unicode:characters_to_binary(Formatted),
                gen_server:cast(?SERVER, {exception, Id, ExceptionData})
        end
    end),
    {noreply, State};
handle_cast({result, Id, Result}, #{io := IO} = State) ->
    reply(Id, Result, IO),
    {noreply, State};
handle_cast({exception, Id, ExceptionData}, #{io := IO} = State) ->
    reply_exception(Id, ExceptionData, IO),
    {noreply, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(_Request, State) ->
    {noreply, State}.

%%==============================================================================
%% Internal Functions
%%==============================================================================
reply(Id, Segments, Device) ->
    %% Use file:write/2 since it writes bytes
    BinId = integer_to_binary(Id),
    Size = integer_to_binary(length(Segments)),
    Data = [encode_segment(Segment) || Segment <- Segments],
    file:write(Device, [<<"REPLY ">>, BinId, $\s, Size, $\n | Data]),
    ok.

reply_exception(Id, Data, Device) ->
    %% Use file:write/2 since it writes bytes
    Size = integer_to_binary(byte_size(Data)),
    BinId = integer_to_binary(Id),
    file:write(Device, [<<"EXCEPTION ">>, BinId, $\s, Size, $\n | Data]),
    ok.

encode_segment({Tag, Data}) ->
    Size = integer_to_binary(byte_size(Data)),
    [Tag, $\s, Size, $\n | Data].