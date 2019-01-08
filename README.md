# Faktory Worker Ex

Elixir worker for Faktory ([blog](http://www.mikeperham.com/2017/10/24/introducing-faktory/)) ([github](https://github.com/contribsys/faktory)).

## Installation

The package can be installed by adding `faktory_worker_ex` to your list of dependencies in `mix.exs`:
```elixir
def deps do
  [
    {:faktory_worker_ex, "~> 0.0"}
  ]
end
```

## Quickstart

```elixir
# For enqueuing jobs
defmodule MyFaktoryClient do
  use Faktory.Client, otp_app: :my_cool_app
end

# For processing jobs
defmodule MyFaktoryWorker do
  use Faktory.Worker, otp_app: :my_cool_app
end

# You must add them to your app's supervision tree
defmodule MyCoolApp.Application do
  use Application

  def start(_type, _args) do
    children = [MyFaktoryClient, MyFaktoryWorker]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

defmodule MyGreeterJob do
  use Faktory.Job

  def perform(greeting, name) do
    IO.puts("#{greeting}, #{name}!!")
  end
end

# List argument must match the arity of MyGreeterJob.perform
MyGreeterJob.perform_async(["Hello", "Genevieve"])
```

## Starting the worker

`mix faktory`

You should see logging output and the above job being processed.

`mix faktory -h`

To see command line options that can override in-app configuration.

`iex -S mix faktory`

If you want to debug your jobs using `IEx.pry`.

## Configuration

Compile-time config is done with `Mix.Config`.

Run-time config is done with environment variables and/or an `init/1` callback.

See documentation on:
* [Client](https://hexdocs.pm/faktory_worker_ex/Faktory.Client.html)
* [Worker](https://hexdocs.pm/faktory_worker_ex/Faktory.Worker.html)

## Running a Faktory server

To run this readme's example, you need to run a Faktory server.

Easiest way is with Docker:
```
docker run --rm -p 7419:7419 -p 7420:7420 contribsys/faktory:latest -b :7419 -w :7420
```

You should be able to go to [http://localhost:7420](http://localhost:7420) and see the web ui.

## Features

* Middleware
* Connection pooling (for clients)
* Support for multiple Faktory servers
* Faktory server authentication and TLS support
* Comprehensive documentation
* Comprehensive supervision tree
* Decent integration tests

## Missing features

* Responding to `quiet` and `terminate`
* Running without `mix` (e.g. a Distillery release)

## Issues / Questions

[https://github.com/cjbottaro/faktory_worker_ex/issues](https://github.com/cjbottaro/faktory_worker_ex/issues)
