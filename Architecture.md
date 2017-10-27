# Architecture

This document describes some high level design concepts.

## Supervision

`faktory_worker_ex` tries to be a proper OTP app with complete supervision trees.

Workers (actually `Manager`s in code) are all watched by a supervisor as are any
connection pools. Any given worker is linked to a connection and whatever process
is actually executing the job. So if either die, so will the worker and the
supervisor should bring it back up.

## Connection

The actually connections to the Faktory server use the [Connection](https://hexdocs.pm/connection/Connection.html) library which aids
in error handling and reconnecting. If that fails, it should bring down whatever
processes and the supervisors will take over.

## Lost jobs?

No job should ever be lost due to Faktory's ack'ing semantics, and if they are
it's Faktory's fault, not `faktory_worker_ex`'s... ;)

At worst, a job will be processed more than one due to a process crashing before
issuing the ack.

## Memory bloat?

Every job is executed in a completely new Elixir/Erlang process which dies
when the job is finished. The only long running processes are the workers which
just serve to fetch jobs and spawn processes to execute them.

It's kind of like the Resque model, but many Elixir/Erlang processes per Unix
process.
