A description of RabbitMQ's worker pool can be found here: [http://www.lshift.net/blog/2010/03/29/on-the-limits-of-concurrency-worker-pools-in-erlang](http://www.lshift.net/blog/2010/03/29/on-the-limits-of-concurrency-worker-pools-in-erlang)

Limitation to RabbitMQ's worker pool are as follows:

* only one can be created within the running application
* you have to supply the pool with the function you want to run each time you invoke it

This fork allows you to:

* Run several worker pools (each independently named, if needed)
* Make a worker pool execute a specified function every time it's invoked
    * If such a function requires initialization of certain parameters or somesuch, you can supply an init function that will be called once the worker pool has been started

Hence, there a new function, worker_pool_sup:start_link/1, that can accept the following optional parameters:

* `{name, Name}`  
  `Name = atom()`

  specify a new name for this worker_pool
* `{init, Init}`  
  `Init = function(), arity: 1`

  specify a function to be run at the time of worker pool's initialization. May return a result, which will be stored and passed onto main function (if any is specified)
* `{main, Main}`  
  `Main = function(), arity: 1`

  specify a function to be run when a worker is invoked with no arguments. The function will be passed he result of init function.

**Example 1. Original-style invocation**

    Pid = case worker_pool_sup:start_link(erlang:system_info(schedulers)*8) of
              {ok, P} -> P;
              {error, {already_started, P2}} -> P2
    end,
    Result = worker_pool:submit(fun() -> do_smth() end),
    worker_pool:submit_async(fun() -> do_smth() end),
    %% etc


**Example 2. Starting several pools**

    Pid1 = case worker_pool_sup:start_link([{name, pool_1}]) of
              {ok, P1} -> P1;
              {error, {already_started, P2}} -> P2
    end,
    Result = worker_pool:submit(Pid1, fun() -> do_smth() end),
    worker_pool:submit_async(Pid1, fun() -> do_smth() end),

    Pid3 = case worker_pool_sup:start_link([{name, pool_2}]) of
              {ok, P4} -> P4;
              {error, {already_started, P5}} -> P5
    end,
    Result2 = worker_pool:submit(Pid3, fun() -> do_smth() end),
    worker_pool:submit_async(Pid3, fun() -> do_smth() end),
    %% etc


    %% etc



**Example 3. An init function**

    %% Note, Init will be passed all options specified in call to 
    %% worker_pool_sup:start_link/1
    Init = fun(Options) -> os:cmd(["echo \"", lists:flatten(Options), "\""]) end,
    Pid = case worker_pool_sup:start_link([{init, Init}]) of
              {ok, P1} -> P1;
              {error, {already_started, P2}} -> P2
    end,
    Result = worker_pool:submit(Pid, fun() -> do_smth() end),
    worker_pool:submit_async(Pid, fun() -> do_smth() end),
    %% etc

**Example 4. A function associated with worker_pool**

    %% result of init function will be stored and passed onto main function
    Init = fun(Options) -> do_smth_and_return_result() end,
    Main = fun(Options) -> do_smth() end,
    Pid = case worker_pool_sup:start_link([{init, Init}, {main, Main}]) of
              {ok, P1} -> P1;
              {error, {already_started, P2}} -> P2
    end,
    %% no need to supply a function, since there's already
    %% a function associated with this worker_pool
    Result = worker_pool:submit(Pid),
    worker_pool:submit_async(Pid),
    %% etc

