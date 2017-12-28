Faktory.flush
{:ok, _} = PidMap.start_link
{:ok, _} = Stack.start_link
{:ok, _} = TestJidPidMap.start_link
Faktory.Configuration.fetch_all(:worker) |> Enum.each(fn config ->
  {:ok, _} = Faktory.Supervisor.Workers.start_link(config)
end)
ExUnit.start()
