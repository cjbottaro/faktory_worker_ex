# Architecture

This document describes some high level design concepts.

## Supervision

`faktory_worker_ex` tries to be a proper OTP app with complete supervision trees.

Clients use a `poolboy` pool of connections.

Workers are supervised GenServers that are linked to connections.

Heartbeat processes are also supervised.

## Connection

The actually connections to the Faktory server use the [Connection](https://hexdocs.pm/connection/Connection.html) library which aids in error handling and reconnecting. Talking to connections are wrapped with `retryable_ex`. If that fails, the process should die and supervisors will take over.

## Lost jobs?

No job should ever be lost due to Faktory's ack'ing semantics, and if they are
it's Faktory's fault, not `faktory_worker_ex`'s... ;)

At worst, a job will be processed more than one due to a process crashing before
issuing the ack.

## Memory bloat?

Every job is executed in its own BEAM process. Processors and connection pools are the only long running processes.

It's the Resque model, but efficient because of BEAM processes vs Unix processes.
