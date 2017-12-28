# faktory_worker_ex changes

0.4.0
-----------
* The `:retries` option was renamed to `:retry`.
* Handle non-exception based errors (`{:EXIT, pid, :killed}`).
* More tests and test specific "callbacks" to aid in testing.

0.3.1
-----------
* Update protocol to handle `$-1\r\n`

0.3.0
-----------
* Configure with Mix Config and callback.
* Independently configurable logger.
* Connection pooling for workers.

0.2.1
-----------
* Start having a changelog.
