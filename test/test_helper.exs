Faktory.flush
{:ok, _} = PidMap.start_link
{:ok, _} = TestJidPidMap.start_link
{:ok, _} = Faktory.Configuration.modules(:worker)
  |> Faktory.Supervisor.Workers.start_link

ExUnit.start()
