---
title: Health Check
---

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

Note:

* We only start the health check when the upstream is hit by a request.
There won't be any health check if an upstream is configured but isn't in used.
* If there is no healthy node can be chosen, we will continue to access the upstream.
* We won't start the health check when the upstream only has one node, as we will access
it whether this unique node is healthy or not.
* Active health check is required so that the unhealthy node can recover.

The following is an example of health check:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
        },
        "type": "roundrobin",
        "retries": 2,
        "checks": {
            "active": {
                "timeout": 5,
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
  * `active.type`: The type of active health check, supports `http`, `https`, `tcp`, default: `http`.
  * `active.timeout`: Socket timeout for active checks (in seconds), support decimals. For example `1.01` means `1010` milliseconds, `2` means `2000` milliseconds.
  * `active.concurrency`: Number of targets to check concurrently in active health checks, default: `10`.
  * `active.http_path`: The HTTP GET request path used to detect if the upstream is healthy.
  * `active.host`: The HTTP request host used to detect if the upstream is healthy.
  * `active.port`: The customize health check host port (optional), this will override the port in the `upstream` node.
  * `active.https_verify_certificate`: Whether to check the validity of the SSL certificate of the remote host when performing active health checks using HTTPS. default: `true`.
  * `active.req_headers`: When the active health check sends an HTTP check request, additional request header information, array format, supports setting multiple request headers.

  The threshold fields of `healthy` are:
  * `active.healthy.interval`: Interval between health checks for healthy targets (in seconds), the minimum is 1.
  * `active.healthy.http_statuses`: When using an HTTP request to check the health status of a node, if the response status code matches the set status code, the node is set to the `healthy` status, array format, default: `[200, 302]`.
  * `active.healthy.successes`: The number of success times to determine the target is healthy, the minimum is 1.

  The threshold fields of  `unhealthy` are:
  * `active.unhealthy.interval`: Interval between health checks for unhealthy targets (in seconds), the minimum is 1.
  * `active.unhealthy.http_statuses`: When using an HTTP request to check the health status of a node, if the response status code matches the set status code, the node is set to the `unhealthy` status, array format, default: `[429, 404, 500, 501, 502, 503, 504, 505]`。
  * `active.unhealthy.http_failures`: Determine the number of unhealthy http request failures on the target node, default: `5`.
  * `active.unhealthy.tcp_failures`: Determine the number of unhealthy tcp request failures on the target node, default: `5`.
  * `active.unhealthy.timeouts`: Determine the number of timeout requests for unhealthy target nodes, default: `3`.

* `passive`: To enable passive health checks, you need to specify the configuration items under `checks.passive` in the Upstream object configuration.

  The threshold fields of `healthy` are:
  * `passive.healthy.http_statuses`: If the current response code is equal to any of these, set the upstream node to the `healthy` state. Otherwise ignore this request.
  * `passive.healthy.successes`: Number of successes in proxied traffic (as defined by `passive.healthy.http_statuses`) to consider a target healthy, as observed by passive health checks.

  The threshold fields of `unhealthy` are:
  * `passive.unhealthy.http_statuses`: If the current response code is equal to any of these, set the upstream node to the `unhealthy` state. Otherwise ignore this request.
  * `passive.unhealthy.tcp_failures`: Number of TCP failures in proxied traffic to consider a target unhealthy, as observed by passive health checks.
  * `passive.unhealthy.timeouts`: Number of timeouts in proxied traffic to consider a target unhealthy, as observed by passive health checks.
  * `passive.unhealthy.http_failures`: Number of HTTP failures in proxied traffic (as defined by `passive.unhealthy.http_statuses`) to consider a target unhealthy, as observed by passive health checks.

The health check status can be fetched via `GET /v1/healthcheck` in [control API](./control-api.md).
