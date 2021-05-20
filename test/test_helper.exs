{:ok, _pid} = Test.Client.start_link()
{:ok, _pid} = Test.Worker.Default.start_link(start: true)
{:ok, _pid} = Test.Worker.Middleware.start_link(start: true)

ExUnit.configure(exclude: [pending: true])
ExUnit.start()
