%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ.
%%
%%   The Initial Developers of the Original Code are LShift Ltd,
%%   Cohesive Financial Technologies LLC, and Rabbit Technologies Ltd.
%%
%%   Portions created before 22-Nov-2008 00:00:00 GMT by LShift Ltd,
%%   Cohesive Financial Technologies LLC, or Rabbit Technologies Ltd
%%   are Copyright (C) 2007-2008 LShift Ltd, Cohesive Financial
%%   Technologies LLC, and Rabbit Technologies Ltd.
%%
%%   Portions created by LShift Ltd are Copyright (C) 2007-2010 LShift
%%   Ltd. Portions created by Cohesive Financial Technologies LLC are
%%   Copyright (C) 2007-2010 Cohesive Financial Technologies
%%   LLC. Portions created by Rabbit Technologies Ltd are Copyright
%%   (C) 2007-2010 Rabbit Technologies Ltd.
%%
%%   All Rights Reserved.
%%
%%   Contributor(s): ______________________________________.
%%

-module(worker_pool_worker).

-behaviour(gen_server2).

-export([start_link/1, submit/1, submit/2, submit_async/1, submit_async/2, run/1]).

-export([set_maximum_since_use/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(start_link/1 :: (any()) -> {'ok', pid()} | 'ignore' | {'error', any()}).
-spec(submit/2 :: (pid(), fun (() -> A) | {atom(), atom(), [any()]}) -> A).
-spec(submit_async/2 ::
      (pid(), fun (() -> any()) | {atom(), atom(), [any()]}) -> 'ok').
-spec(run/1 :: (fun (() -> A)) -> A;
               ({atom(), atom(), [any()]}) -> any()).
-spec(set_maximum_since_use/2 :: (pid(), non_neg_integer()) -> 'ok').

-endif.

%%----------------------------------------------------------------------------

-define(HIBERNATE_AFTER_MIN, 1000).
-define(DESIRED_HIBERNATE, 10000).

-record(state, { 
    % self data
    id, server,

    % functions
    init, main, % pre, post,

    % custom data used by functions
    data
}).

%%----------------------------------------------------------------------------

start_link(Options) ->
    gen_server2:start_link(?MODULE, Options, [{timeout, infinity}]).

submit(Pid) ->
    gen_server2:call(Pid, submit, infinity).

submit(Pid, Fun) ->
    gen_server2:call(Pid, {submit, Fun}, infinity).

submit_async(Pid) ->
    gen_server2:cast(Pid, submit_async).

submit_async(Pid, Fun) ->
    gen_server2:cast(Pid, {submit_async, Fun}).

set_maximum_since_use(Pid, Age) ->
    gen_server2:pcast(Pid, 8, {set_maximum_since_use, Age}).

run({M, F, A}) ->
    apply(M, F, A);
run(Fun) ->
    Fun().

%%----------------------------------------------------------------------------

init(Options) ->
    ok = file_handle_cache:register_callback(?MODULE, set_maximum_since_use,
                                             [self()]),

    WId = proplists:get_value(worker_id, Options),
    Server = proplists:get_value(name, Options),
    WorkerName = list_to_atom(atom_to_list(Server) ++ "_worker"),

    ok = worker_pool:idle(Server, WId),
    put(WorkerName, true),

    Init = proplists:get_value(init, Options),
    % Pre  = proplists:get_value(pre, Options),
    % Post = proplists:get_value(post, Options),
    Main = proplists:get_value(main, Options),

    Data = case Init of 
        undefined -> 
            undefined;
        _ -> 
            Init(Options)
    end,

    {ok, #state{id = WId, server = Server, init = Init, main = Main, data = Data%,pre = Pre, post = Post
        }, hibernate,
     {backoff, ?HIBERNATE_AFTER_MIN, ?HIBERNATE_AFTER_MIN, ?DESIRED_HIBERNATE}}.

handle_call(submit, From, #state{server=Server, id=WId, main=Fun, data = Data} = State) ->
    Data1 = do_run(From, Fun, [Data]),
    ok = worker_pool:idle(Server, WId),
    {noreply, State#state{data = Data1}, hibernate};

handle_call({submit, Fun}, From, #state{server=Server, id=WId} = State) ->
    Result = run(Fun),
    gen_server2:reply(From, Result),
    ok = worker_pool:idle(Server, WId),
    {noreply, State, hibernate};

handle_call(Msg, _From, State) ->
    {stop, {unexpected_call, Msg}, State}.

handle_cast(submit_async, #state{server=Server, id=WId, main = Fun, data = Data} = State) ->
    Data1 = do_run_async(Fun, [Data]),
    ok = worker_pool:idle(Server, WId),
    {noreply, State#state{data = Data1}, hibernate};

handle_cast({submit_async, Fun}, #state{server=Server, id=WId} = State) ->
    run(Fun),
    ok = worker_pool:idle(Server, WId),
    {noreply, State, hibernate};

handle_cast({set_maximum_since_use, Age}, State) ->
    ok = file_handle_cache:set_maximum_since_use(Age),
    {noreply, State, hibernate};

handle_cast(Msg, State) ->
    {stop, {unexpected_cast, Msg}, State}.

handle_info(Msg, State) ->
    {stop, {unexpected_info, Msg}, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, State) ->
    State.

do_run(From, Fun, Data) ->
    F = fun() -> Fun(Data) end,
    case run(F) of
        {ReplyData, NewData} ->
            gen_server2:reply(From, ReplyData),
            NewData;
        Any ->
            gen_server2:reply(From, Any),
            Data
    end.
    
do_run_async(Fun, Data) ->
    F = fun() -> Fun(Data) end,
    case run(F) of
        {_ReplyData, NewData} ->
            NewData;
        _ ->
            Data
    end.