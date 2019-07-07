# faktory_worker_ex changes

## 0.8.0
-----------
* Use GenStage instead of BlockingQueue. (PR [#36](https://github.com/cjbottaro/faktory_worker_ex/pull/36))
* Find the right job module when jobtype doesn't match module name. (PR [#35](https://github.com/cjbottaro/faktory_worker_ex/pull/35))
* Graceful shutdown on SIGTERM. (PR [#41](https://github.com/cjbottaro/faktory_worker_ex/pull/41))
* Use Jason instead of Poison.


## 0.7.1
-----------
* Fix `mix faktory` not respecting CLI args.

## 0.7.0
-----------
* The great simplication refactor; everything done in this version is to reduce conceptual complexity and make the code easier to read and understand.
* Changed to a queue based architecture (reduces number of connections to Faktory server).
* No more Genservers, the components of a worker (producer, consumers, reporter) are all supervised tasks. Jobs are also run in tasks (spawned by the consumers).
* Removed `retryable_ex`; workers will retry when fetching, acking, and failing jobs, but all else is up to the user now.

## 0.6.0
-----------
* (breaking) Configuration simplified (again); see readme.
* Can override `jobtype` for enqueuing to workers in other languages.
* Simplified supervision; removed all custom supervisor modules.
* Workers no longer use connection pool; each processor has dedicated (linked) connection.
* Simplify plain vs tls socket connections with the `socket` package.
* Protocol now retries with the `retryable_ex` package.
* Faktory 0.9.3

## 0.5.0
-----------
* (breaking) Simplified middleware; no longer pass the `chain` arg.
* (breaking) Completely rewrote configuration system. See `Faktory.Configuration`.
* (breaking) Removed `set/1` and `set/2` in favor of passing `options` to `perform_async/2`.
* (breaking) `perform_async/2` argument order reversed (`options` is 2nd arg now).
* Can enqueue to different Faktory servers via `perform_async/2`.

## 0.4.0
-----------
* Faktory 0.6.x support @acj @valo
* Authentication support @acj
* TLS support @acj
* The `:retries` option was renamed to `:retry` @valo
* Handle non-exception based errors (`{:EXIT, pid, :killed}`) @valo
* More tests and test specific "callbacks" to aid in testing.
* Update protocol to handle `$-1\r\n` @valo

## 0.3.0
-----------
* Configure with Mix Config and callback.
* Independently configurable logger.
* Connection pooling for workers.

## 0.2.1
-----------
* Start having a changelog.
