{:ok, _} = PidMap.start_link
{:ok, _} = Stack.start_link
{:ok, _} = Faktory.Supervisor.Workers.start_link
ExUnit.start()
