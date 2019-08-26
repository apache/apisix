[中文](limit-conn-cn.md)
# limit-conn

Limiting request concurrency (or concurrent connections) plugin for Apisix.

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

The parameters of the plugin enabled above indicate that only one concurrent request is allowed. When more than one concurrent request is received, will return `503` directly.

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

This means that the limit request concurrency plugin is in effect.

#### disable plugin

When you want to disable the limit-conn plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

The limit-conn plugin has been disabled now. It works for other plugins.
