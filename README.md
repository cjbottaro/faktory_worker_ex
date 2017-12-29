# Faktory Worker Ex

Elixir worker for Faktory ([blog](http://www.mikeperham.com/2017/10/24/introducing-faktory/)) ([github](https://github.com/contribsys/faktory)).

## Installation

[faktory_worker_ex](https://hex.pm/packages/faktory_worker_ex) is available on
[hex.pm](https://hex.pm).


## Configuration

All configuration is optional with sane defaults and will connect to a
Faktory server on `localhost:7419`.

See the
[hexdocs](https://hexdocs.pm/faktory_worker_ex/Faktory.Configuration.html)
for more on configuration.

## Define a job module

Very similar to Sidekiq...

```elixir
defmodule FunWork do
  use Faktory.Job

  faktory_options queue: "default", retry: 25, backtrace: 0

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

## Running a Faktory server

To run this readme's example, you need to run a Faktory server.

Easiest way is with Docker:
```
docker run --rm -it -p 7419:7419 -p 7420:7420 contribsys/faktory:latest -b 0.0.0.0:7419
```

You should be able to go to [http://localhost:7420](http://localhost:7420) and see the web ui.

## What's missing?

* Responding to the terminate signal (from the Faktory server)
* Tests

## Issues / Questions

Hit me up on Github Issues.
