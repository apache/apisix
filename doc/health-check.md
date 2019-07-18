
## Health Checks for Upstream

Health Check of APISIX is based on [lua-resty-healthcheck](https://github.com/Kong/lua-resty-healthcheck),
you can use it for upstream.

The following is a example of health check:
```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -d '
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
         "nodes": {
            "127.0.0.1:1980": 1,
            "127.0.0.1:1970": 1
        }
        "type": "roundrobin",
        "checks": {
            "active": {
                "http_path": "/status",
                "host": "foo.com",
                "healthy": {
                    "interval": 2,
                    "successes": 1
                },
                "unhealthy": {
                    "interval": 1,
                    "http_failures": 2
                }
            }
        }
    }
}'
```

The configures in `checks` are belong to health check, the type of `checks` is
 one of the two: `active` or `passive`.

You need to specify the check point:
* `http_path`: The HTTP GET request path used to detect if the upstream is healthy.
* `host`: The HTTP request host used to detect if the upstream is healthy.

The threshold fields of `health` are:
* `interval`: Interval between health checks for healthy targets (in seconds), the minimum is 1.
* `successes`: The number of success times to determine the target is healthy, the minimum is 1.

The threshold fields of  `unhealthy` are:
* `interval`: Interval between health checks for unhealthy targets (in seconds), the minimum is 1.
* `http_failures`: The number of http failures times to determine the target is unhealthy, the minimum is 1.
