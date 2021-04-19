defmodule ConnectionPool do
  use GenServer

  @defaults [
    size: 10,
    timeout: 5_000,
  ]

  def defaults, do: @defaults

  def config do
    config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    Keyword.merge(@defaults, config)
  end

  @doc false
  def debug(pool) do
    GenServer.call(pool, :debug)
  end

  def checkout(pool, opts \\ [], f \\ nil)

  def checkout(pool, opts, nil) when is_list(opts) do
    GenServer.call(pool, {:checkout, opts}, :infinity)
  end

  def checkout(pool, f, opts) when is_function(f) and (is_nil(opts) or is_list(opts)) do
    transaction(pool, f, opts || [])
  end

  def checkout(pool, opts, f) when is_function(f) and is_list(opts) do
    transaction(pool, f, opts)
  end

  defp transaction(pool, f, opts) do
    with {:ok, conn} <- checkout(pool, opts, nil) do
      try do
        f.(conn)
      after
        checkin(pool, conn)
      end
    end
  end

  def checkin(pool, name) do
    GenServer.call(pool, {:checkin, name})
  end

  def start_link(module, config \\ [], opts \\ [])

  def start_link({module, arg}, config, opts) when is_atom(module) do
    if function_exported?(module, :child_spec, 1) do
      Keyword.put(config, :start, module.child_spec(arg).start)
      |> start_link(opts)
    else
      {:error, "#{inspect module} must define child_spec/1"}
    end
  end

  def start_link(module, config, opts) when is_atom(module) do
    start_link({module, []}, config, opts)
  end

  def start_link(config, opts, []) when is_list(config) and is_list(opts) do
    config = Keyword.merge(config(), config)
    GenServer.start_link(__MODULE__, config, opts)
  end

  def init(config) do
    config = Map.new(config)

    {module, _, _} = config.start.(nil)

    names = Enum.map(1..config.size, fn _ ->
      id = :crypto.strong_rand_bytes(7) |> Base.encode16(case: :lower)
      {:global, {module, id}}
    end)

    state = %{
      config: config,
      module: module,
      checked_in: names,
      checked_out: %{},
      started: MapSet.new(),
      waiting: :ordsets.new(),
    }

    {:ok, state}
  end

  def handle_call(:debug, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:checkout, opts}, {pid, _ref} = from, state) do
    %{checked_in: checked_in, checked_out: checked_out} = state

    if not Map.has_key?(checked_out, pid) do
      Process.monitor(pid)
    end

    if checked_in == [] do
      {:noreply, add_waiter(from, opts, state)}
    else
      {name, state} = check_out(pid, state)
      case ensure_started(name, state) do
        {:ok, state} -> {:reply, {:ok, name}, state}
        error -> {:reply, error, check_in(name, pid, state)}
      end
    end
  end

  def handle_call({:checkin, name}, {pid, _ref}, state) do
    %{checked_out: checked_out} = state

    if name in (checked_out[pid] || []) do
      state = check_in(name, pid, state)
      {:reply, :ok, reply_to_waiter(name, state)}
    else
      {:reply, {:error, "not checked out"}, state}
    end
  end

  def handle_info({:checkout_timeout, from}, state) do
    %{waiting: waiting} = state

    # Sorry you got timed out.
    :ok = GenServer.reply(from, {:error, :timeout})

    # Proactively remove them from the waiters. Not sure how to do this the most
    # efficiently.
    waiting = Enum.reject(waiting, fn {_time, waiter, _timer} -> waiter == from end)

    {:noreply, %{state | waiting: waiting}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    %{checked_out: checked_out} = state

    # Seems better to go through our own internal API rather than try to optimize.
    state = Enum.reduce(checked_out[pid] || [], state, fn name, state ->
      check_in(name, pid, state)
    end)

    {:noreply, state}
  end

  # No error checking; must be done upstream.
  defp check_out(pid, state) do
    %{checked_in: checked_in, checked_out: checked_out} = state

    [name | checked_in] = checked_in
    checked_out = Map.update(checked_out, pid, MapSet.new([name]), &MapSet.put(&1, name))

    {name, %{state | checked_in: checked_in, checked_out: checked_out}}
  end

  # No error checking; must be upstream.
  defp check_in(name, pid, state) do
    %{checked_in: checked_in, checked_out: checked_out} = state

    checked_in = [name | checked_in]
    checked_out = if MapSet.size(checked_out[pid]) == 1 do
      Map.delete(checked_out, pid)
    else
      Map.update!(checked_out, pid, &MapSet.delete(&1, name))
    end

    %{state | checked_in: checked_in, checked_out: checked_out}
  end

  defp ensure_started(name, state) do
    %{started: started, module: module, config: config} = state

    if name in started do
      {:ok, state}
    else
      DynamicSupervisor.start_child(__MODULE__, %{
        id: {__MODULE__, module}, # I don't think ids need to be unique with DynamicSupervisor.
        start: config.start.(name)
      })
      |> case do
        {:ok, _pid} -> {:ok, %{state | started: MapSet.put(started, name)}}
        error -> error
      end
    end
  end

  defp add_waiter(from, opts, state) do
    %{config: config, waiting: waiting} = state

    timer = case opts[:timeout] || config.timeout do
      :infinity -> nil
      n -> Process.send_after(self(), {:checkout_timeout, from}, n)
    end

    waiting = :ordsets.add_element({monotonic_time(), from, timer}, waiting)

    %{state | waiting: waiting}
  end

  defp reply_to_waiter(name, state) do
    reply_to_waiter(name, state.waiting, state)
  end

  # No waiters, or all our waiters already timed out.
  defp reply_to_waiter(_name, [], state) do
    %{state | waiting: :ordsets.new()}
  end

  # The waiter specified timeout: :inifinity, thus they have no timer.
  defp reply_to_waiter(name, [{_time, from, nil} | waiting], state) do
    {pid, _ref} = from
    {^name, state} = check_out(pid, state)
    :ok = GenServer.reply(from, {:ok, name})
    %{state | waiting: waiting}
  end

  # Waiter has a timer, but it might have expired already.
  defp reply_to_waiter(name, [{_time, from, timer} | waiting], state) do
    case Process.cancel_timer(timer) do
      n when is_integer(n) ->
        {pid, _ref} = from
        {^name, state} = check_out(pid, state)
        :ok = GenServer.reply(from, {:ok, name})
        %{state | waiting: waiting}

      false -> reply_to_waiter(name, waiting, state)
    end
  end

  defp monotonic_time do
    System.monotonic_time(:microsecond)
  end

end
