# Architecture

This document describes some high level design concepts.

## Workers are queue based

The following diagram shows (almost) all the processes involved in a `Worker`.

![Diagram](http://storage.stochasticbytes.com.s3.amazonaws.com/W5kEiEJr.png)

1. The `Producer` fetches jobs from the Faktory server and enqueues them on the `Job Queue`.
1. Multiple `Consumers` dequeue jobs from the `Job Queue`, process them, and enqueue the results onto the `Report Queue`.
1. The `Reporter` dequeues results and reports a corresponding `ack` or `fail` to the Faktory server.

The number of jobs that can be processed concurrently is equal to the number of `Consumers`, which is set by the `concurrency` option.

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
