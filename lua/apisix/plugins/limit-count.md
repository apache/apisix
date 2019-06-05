# limit-count
[中文](limit-count-cn.md)

### Parameters
* `count`：指定时间窗口内的请求数量阈值
* `time_window`：时间窗口的大小（以秒为单位），超过这个时间就会重置
* `rejected_code`：当请求超过阈值被拒绝时，返回的 HTTP 状态码，默认是 503
* `key`：是用来做请求计数的依据，当前只接受终端 IP 做为 key，即 "remote_addr"

### example
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
