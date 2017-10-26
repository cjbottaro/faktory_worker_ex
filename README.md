# Faktory Worker Ex

Elixir worker for [Faktory](https://github.com/contribsys/faktory).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `faktory_worker_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:faktory_worker_ex, "~> 0.1.0"}
  ]
end
```

## Configuration

Configuration is done with modules and supports both compile-time and runtime
configuration (at the same time).

There are two types of configuration:
 * client (for pushing messages onto the queues)
 * worker (for reading/processing the queues)

```elixir
defmodule MyClientConfig do
  use Faktory.Configuration, :client

  host "localhost"
  port 7419
  pool 10
end

defmodule MyWorkerConfig do
  use Faktory.Configuration, :worker

  host "localhost"
  port 7419
  concurrency 20
  queues ["default"]
end
```

All the configuration options are optional and default to the above.

Now you need to make `faktory_worker_ex` aware of the configs. This is done
in the normal Mix Config files (ex: `config/config.exs`).

```elixir
use Mix.Config

config :faktory_worker_ex,
  client_config: MyClientConfig,
  worker_config: MyWorkerConfig
```

Dynamic runtime configuration will be covered in the hexdocs.

## Define a job module

Very similar to Sidekiq...

```elixir
defmodule FunWork do
  use Faktory.Job

  faktory_options queue: "default", retries: 25, backtrace: 0

  def perform(x, y) do
    IO.puts "#{x} is a fun number! ... #{y} is not... :("
  end
end
```

`faktory_options` are optional and default to the above.

Now fire up iex...

```
iex(1)> FunWork.perform_async([5, 6])
```

Notice that you have to pass a list to `perform_async/1`... that's just because
of how `Kernel.apply/3` works. No (un)splatting in Elixir... :/

## Starting the worker

`mix faktory`

You should see logging output and the above job being processed.

## What's missing?

* Authentication
* TLS
* Responding to the terminate signal (from the Faktory server)
* Middleware
* Tests
* Full documentation

## Issues / Questions

Hit me up on Github Issues.
