# faktory_worker_ex changes

0.5.0
-----------
* (breaking) Simplified middleware; no longer pass the `chain` arg.

0.4.0
-----------
* Faktory 0.6.x support @acj @valo
* Authentication support @acj
* TLS support @acj
* The `:retries` option was renamed to `:retry` @valo
* Handle non-exception based errors (`{:EXIT, pid, :killed}`) @valo
* More tests and test specific "callbacks" to aid in testing.
* Update protocol to handle `$-1\r\n` @valo

0.3.0
-----------
* Configure with Mix Config and callback.
* Independently configurable logger.
* Connection pooling for workers.

0.2.1
-----------
* Start having a changelog.
