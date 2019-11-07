<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
-->


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
        "retries": 2,
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
                },
                "req_headers": ["User-Agent: curl/7.29.0"]
            },
            "passive": {
                "healthy": {
                    "http_statuses": [200, 201],
                    "successes": 3
                },
                "unhealthy": {
                    "http_statuses": [500],
                    "http_failures": 3,
                    "tcp_failures": 3
                }
            }
        }
    }
}'
```

The configures in `checks` are belong to health check, the type of `checks`
contains: `active` or `passive`.

* `active`: To enable active health checks, you need to specify the configuration items under `checks.active` in the Upstream object configuration.

    * `active.http_path`: The HTTP GET request path used to detect if the upstream is healthy.
    * `active.host`: The HTTP request host used to detect if the upstream is healthy.

    The threshold fields of `healthy` are:
    * `active.healthy.interval`: Interval between health checks for healthy targets (in seconds), the minimum is 1.
    * `active.healthy.successes`: The number of success times to determine the target is healthy, the minimum is 1.

    The threshold fields of  `unhealthy` are:
    * `active.unhealthy.interval`: Interval between health checks for unhealthy targets (in seconds), the minimum is 1.
    * `active.unhealthy.http_failures`: The number of http failures times to determine the target is unhealthy, the minimum is 1.
    * `active.req_headers`: Additional request header.

* `passive`: To enable passive health checks, you need to specify the configuration items under `checks.passive` in the Upstream object configuration.

    The threshold fields of `healthy` are:
    * `passive.healthy.http_statuses`: If the current response code is equal to any of these, set the upstream node to the `healthy` state. Otherwise ignore this request.
    * `passive.healthy.successes`: Number of successes in proxied traffic (as defined by `passive.healthy.http_statuses`) to consider a target healthy, as observed by passive health checks.

    The threshold fields of `unhealthy` are:
    * `passive.unhealthy.http_statuses`: If the current response code is equal to any of these, set the upstream node to the `unhealthy` state. Otherwise ignore this request.
    * `passive.unhealthy.tcp_failures`: Number of TCP failures in proxied traffic to consider a target unhealthy, as observed by passive health checks.
    * `passive.unhealthy.timeouts`: Number of timeouts in proxied traffic to consider a target unhealthy, as observed by passive health checks.
    * `passive.unhealthy.http_failures`: Number of HTTP failures in proxied traffic (as defined by `passive.unhealthy.http_statuses`) to consider a target unhealthy, as observed by passive health checks.
