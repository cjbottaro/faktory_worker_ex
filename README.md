# Faktory Worker Ex

Elixir worker for Faktory ([blog](http://www.mikeperham.com/2017/10/24/introducing-faktory/)) ([github](https://github.com/contribsys/faktory)).

This is an Elixir library, so you should be reading the documentation
on Hexdocs [here](https://hexdocs.pm/faktory_worker_ex) instead of Github.

## Quickstart

```elixir
def deps do
  [
    {:faktory_worker_ex, "~> 1.0"}
  ]
end
```

```elixir
defmodule GreetJob do
  use Faktory.Job
  require Logger

  def perform(name) do
    Logger.info("Hello, #{name}!")
  end

  def perform(greeting, name) do
    Logger.info("#{greeting}, #{name}!")
  end
end

# Notice the argument is a list that must have the same arity as one of the perform functions.
GreetJob.perform_async(["Genevieve"])
GreetJob.perform_async(["Sup", "my dude"])
```

```plain
$ mix faktory

19:02:23.128 [info]  Hello, Genevieve!

19:02:23.128 [info]  Sup, my dude!
```

## Connection options

By default, both client and worker connections will connect to `localhost:7419`.
You can change that via configuration.

```elixir
import Config

config :faktory_worker_ex, Faktory.Connection,
  host: "faktory.foo.com",
  port: 8000
```

## Configuration

This library is massively configurable. It was meant to be used in large
umbrella applications and with multiple Faktory servers.

Most modules let you `use` them to make specific and individually configurable
modules.

There is a hierarchy to configuration. Arguments to `start_link` override all,
`Config` overrides `use` arguments (for runtime configuration via `runtime.exs`),
and specific modules override the base modules.

```elixir
import Config

config :faktory_worker_ex, Faktory.Client, host: "foo",
  
defmodule MyClient do
  use Faktory.Client, host: "bar"
end

# Connect to "foo"
{:ok, client} = Faktory.Client.start_link()

# Connect to "bar"
{:ok, client} = Faktory.Client.start_link(host: "bar")

# Connect to "bar"
MyClient.start_link()

# Connect to "baz"
MyClient.start_link(host: "baz")
```

All the configuration options are deep merged according to the hierarchy rules.

## Running a Faktory server

To run the quickstart example, you need to run a Faktory server.

Easiest way is with Docker:
```
docker run --rm -p 7419:7419 -p 7420:7420 contribsys/faktory:latest -b :7419 -w :7420
```

You should be able to go to [http://localhost:7420](http://localhost:7420) and see the web ui.

## Using with multiple Faktory servers

```elixir
import Config

config :my_app, FooClient,
  host: "foo.faktory.myapp.com"

config :my_app, BarClient,
  host: "bar.faktory.myapp.com"

config :my_app, FooWorker,
  host: "foo.faktory.myapp.com"

config :my_app, BarWorker,
  host: "bar.faktory.myapp.com"

defmodule FooClient do
  use Faktory.Client
end

defmodule BarClient do
  use Faktory.Client
end

defmodule FooWorker do
  use Faktory.Worker
end

defmodule BarWorker do
  use Faktory.Worker
end

defmodule FooJob do
  use Faktory.Job, client: FooClient
  def perform(), do: nil
end

defmodule BarJob do
  use Faktory.Job, client: BarClient
  def perform(), do: nil
end

FooJob.perform_async([]) # Enqueues job to Faktory server at foo.faktory.myapp.com
BarJob.perform_async([]) # Enqueues job to Faktory server at bar.faktory.myapp.com
```

## Starting individual workers

You can do this on the command line.
```
mix faktory --only FooWorker,BarWorker
mix faktory --only FooWorker --only BarWorker

mix faktory --except FooWorker,BarWorker
mix faktory --except FooWorker --except BarWorker
```

Or you can tell a worker to start (or not start) via `Config`.
```elixir
import Config

# Will start regardless of `mix faktory`
config :my_app, FooWorker, start: true

# Will not start regardless of `mix faktory`
config :my_app, BarWorker, start: false
```

## Features

* Middleware
* Connection pooling (for clients)
* Support for multiple Faktory servers
* Supports 100% of Faktory features
* Comprehensive documentation
* Comprehensive supervision tree
* Decent integration tests

## Issues / Questions

[https://github.com/cjbottaro/faktory_worker_ex/issues](https://github.com/cjbottaro/faktory_worker_ex/issues)
