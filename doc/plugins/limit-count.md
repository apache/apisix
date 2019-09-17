[中文](limit-count-cn.md)
# limit-count

### Parameters
* `count`: is the specified number of requests threshold.
* `time_window`: is the time window in seconds before the request count is reset.
* `rejected_code`: The HTTP status code returned when the request exceeds the threshold is rejected. The default is 503.
* `key`: is the user specified key to limit the rate, now accept those as key: "remote_addr"(client's IP), "server_addr"(server's IP), "X-Forwarded-For/X-Real-IP" in request header.

### example

#### enable plugin
Here's an example, enable the limit count plugin on the specified route:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
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

You can open dashboard with a browser: `http://127.0.0.1:9080/apisix/dashboard/`, to complete the above operation through the web interface, first add a route:
![](../images/plugin/limit-count-1.png)

Then add limit-count plugin:
![](../images/plugin/limit-count-2.png)

#### test plugin
The above configuration limits access to only 2 times in 60 seconds. The first two visits will be normally:
```shell
curl -i http://127.0.0.1:9080/index.html
```

The response header contains `X-RateLimit-Limit` and `X-RateLimit-Remaining`,
 which mean the total number of requests and the remaining number of requests that can be sent:
```
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
Server: APISIX web server
```

When you visit for the third time, you will receive a response with the 503 HTTP code:
```
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
Server: APISIX web server

<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

This means that the limit count plugin is in effect.

#### disable plugin
When you want to disable the limit count plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:
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

The limit count plugin has been disabled now. It works for other plugins.
