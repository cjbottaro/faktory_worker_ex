defmodule Test.Worker.Middleware do
  use Faktory.Worker, port: 7421, queues: "middleware", middleware: Middleware.WorseMath
end
