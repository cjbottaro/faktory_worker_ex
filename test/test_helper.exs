Faktory.put_env(:start_workers, true)

Supervisor.start_link(
  [Test.Client, Test.DefaultWorker, Test.MiddlewareWorker],
  strategy: :one_for_one
)

Faktory.flush
{:ok, _} = PidMap.start_link
{:ok, _} = TestJidPidMap.start_link

Mox.defmock(Faktory.SocketMock, for: Faktory.Socket)

ExUnit.configure(exclude: [pending: true])
ExUnit.start()
