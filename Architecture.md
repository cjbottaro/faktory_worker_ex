# Architecture

This document describes some high level design concepts.

## Workers are GenStage pipelines

The following diagram shows (almost) all the processes involved in a `Worker`.

```
                                                +----------+                          
                                                |          |                          
                                      +---------|  runner  | <--------+               
                                      |         |          |          |               
                                      |         +----------+          |               
                                      v                               |               
+-------------+         +-------------+         +----------+          +--------------+
|             |         |             |         |          |          |              |
|   faktory   |<--------|   fetcher   |<--------|  runner  | <--------|   reporter   |
|             |         |             |         |          |          |              |
+-------------+         +-------------+         +----------+          +--------------+
                                      ^                               |               
                                      |         +----------+          |               
                                      |         |          |          |               
                                      +---------|  runner  | <--------+               
                                                |          |                          
                                                +----------+                          
```

1. The fetcher asks the Faktory server for jobs.
1. Runners ask the fetcher for jobs to run. They emit a report on the success or failure of a job that has been ran.
1. The reporter takes these reports and sends an ACK or FAIL message back to the Faktory server.

The number of jobs that can be processed concurrently is equal to the number of runners, which is set by the `concurrency` option.

## Worker Connections

A worker only makes 3 connections to the Faktory server, no matter what the concurrency is set to:
1. Fetcher (for fetching jobs)
1. Reporter (for acking or failing jobs)
1. Heartbeat (for sending a required keepalive message every 15 seconds)

## Scaling

It's possible to scale fetchers and reporters using the `fetcher_count` and `reporter_count` options respectively, but I don't see why or how they would ever become bottlenecks unless your job latency is less than the time it takes to talk to the Faktory server. And if that's the case, you shouldn't be using async jobs.

Still, scaling out fetchers and reporters is implemented (for fun and learning).

## Connection

The actually connections to the Faktory server use the [Connection](https://hexdocs.pm/connection/Connection.html) library which aids in error handling and reconnecting.

Network errors cause retries with exponential backoff for fetching, acking, and failing jobs.

There is no retry logic for pushing (enqueing) jobs.

## Lost jobs?

No job should ever be lost due to Faktory's acking semantics, and if they are
it's Faktory's fault, not `faktory_worker_ex`'s... ;)

At worst, a job will be processed more than once due to a process crashing before issuing the ack.

## Memory bloat?

Fetchers, runners, and reporters are all long running processes, but each job is executed in its own process. It's the Resque model, but efficient because of BEAM processes vs Unix processes.
