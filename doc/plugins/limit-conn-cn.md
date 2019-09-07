[English](limit-conn.md)
# limit-conn

Apisix 的限制并发请求（或并发连接）插件。

### Parameters

* `conn`: is the maximum number of concurrent requests allowed. Requests exceeding this ratio (and below `conn` + `burst`) will get delayed to conform to this threshold.
* `burst`: is the number of excessive concurrent requests (or connections) allowed to be delayed.
* `default_conn_delay`: is the default processing latency of a typical connection (or request).
* `key`: is the user specified key to limit the concurrency level.

    For example, one can use the host name (or server zone) as the key so that we limit concurrency per host name. Otherwise, we can also use the client address as the key so that we can avoid a single client from flooding our service with too many parallel connections or requests.

    Now accept those as key: "remote_addr"(client's IP), "server_addr"(server's IP), "X-Forwarded-For/X-Real-IP" in request header.

* `rejected_code`: The HTTP status code returned when the request exceeds the threshold is rejected. The default is 503.

#### enable plugin

Here's an example, enable the limit-conn plugin on the specified route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

#### test plugin

上面启用的插件的参数表示只允许一个并发请求。 当收到多个并发请求时，将直接返回 503 拒绝请求。

```shell
curl -i http://127.0.0.1:9080/index.html?sleep=20 &

curl -i http://127.0.0.1:9080/index.html?sleep=20
<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

这就表示 limit-conn 插件生效了。

#### 移除插件

当你想去掉 limit-conn 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

现在就已经移除了 limit-conn 插件了。其他插件的开启和移除也是同样的方法。

