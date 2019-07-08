# Architecture

This document describes some high level design concepts.

## Workers are GenStage pipelines

The following diagram shows all the stages involved in a `Faktory.Worker`.

```
              +---------+                         +--------+
              |         |                         |        |
     +--------| fetcher |<-------+          +-----| worker |<----+
     |        |         |        |          |     |        |     |
     |        +---------+        |          |     +--------+     |
     v                           |          |                    |
+---------+                  +---+---+      |     +--------+     |    +----------+
|         |                  |       |      |     |        |     |    |          |
| faktory |                  | queue |<-----+-----| worker |<----+----| reporter |
|         |                  |       |      |     |        |     |    |          |
+---------+                  +---+---+      |     +--------+     |    +----------+
     ^                           |          |                    |
     |        +---------+        |          |     +--------+     |
     |        |         |        |          |     |        |     |
     +--------| fetcher |<-------+          +-----| worker |<----+
              |         |                         |        |
              +---------+                         +--------+
```

1. The fetcher stages ask the Faktory server for jobs.
1. The queue stage gets the jobs from the fetcher stages and passes them along to the worker stages.
1. The worker stages run the jobs and emit statuses to the reporter stage.
1. The reporter stage writes the status to logs and sends an ACK or FAIL back to the Faktory server.

The number of jobs that can be processed concurrently is equal to the number of worker stages, which is set by the `concurrency` option.

I have no idea why the queue stage is necessary when there are multiple fetchers. It has something to do with how demand works that I don't understand. If all the worker stages subscribe to all the fetcher stages, then something messes up with demand and jobs don't flow through the pipeline in real time.

## Worker Connections

These are the stages (or processes) that make connections to the Faktory server:
1. Fetcher stages (for fetching jobs)
1. Reporter stage (for acking or failing jobs)
1. Heartbeat process (periodically pings Faktory server and listens for `quiet` and `termnate` messages)

Note that `concurrency` (what defines how many worker stages there) has no bearing on number of connections to the Faktory server.

## Scaling

It's possible to scale reporters using `reporter_count` option, but I don't see why or how they would ever become bottlenecks unless your job latency is less than the time it takes to talk to the Faktory server. And if that's the case, you shouldn't be using async jobs.

Still, scaling out reporters is implemented (for fun and learning).

## Connection

Connections to the Faktory server use the [Connection](https://hexdocs.pm/connection/Connection.html) library which aids in error handling and reconnecting.

Network errors cause retries with exponential backoff for fetching, acking, and failing jobs.

There is no retry logic for pushing (enqueing) jobs.

## Lost jobs?

No job should ever be lost due to Faktory's acking semantics, and if they are
it's Faktory's fault, not `faktory_worker_ex`'s... ;)

At worst, a job will be processed more than once due to a process crashing before issuing the ack.

## Memory bloat?

Fetcher stages, worker stages, and reporter stages are all long running processes, but each job is executed in its own process.

It's like the Resque model, but efficient because of BEAM processes vs Unix processes.