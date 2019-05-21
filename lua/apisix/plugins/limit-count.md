# limit-count

* `conn` is the maximum number of concurrent requests allowed. Requests exceeding this ratio (and below `conn` + `burst`)
will get delayed to conform to this threshold.
* `burst` is the number of excessive concurrent requests (or connections) allowed to be delayed.
* `rejected_code` is the response code when the current request was rejected.
* `key` is the user specified key to limit the concurrency level.`

Here is an example of binding to route:

```json
 {
     "uri": "/hello",
     "plugin_config": {
         "limit-count": {
             "count": 100,
             "time_window": 600,
             "rejected_code": 503,
             "key": "remote_addr"
         }
     }
 }
```
