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

Health Check of Apache APISIX is based on [lua-resty-healthcheck](https://github.com/Kong/lua-resty-healthcheck).

Note:

* We only start the health check when the upstream is hit by a request.
There won't be any health check if an upstream is configured but isn't in used.
* If there is no healthy node can be chosen, we will continue to access the upstream.
* We won't start the health check when the upstream only has one node, as we will access
it whether this unique node is healthy or not.
* Active health check is required so that the unhealthy node can recover.

### Configuration instructions

| Configuration item                              | Configuration type              | Value type | Value option         | Defaults                                                                                      | Description                                                                                                          |
| ----------------------------------------------- | ------------------------------- | ---------- | -------------------- | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| upstream.checks.active.type                     | Active check                    | string     | `http` `https` `tcp` | http                                                                                          | The type of active check.                                                                                            |
| upstream.checks.active.timeout                  | Active check                    | integer    |                      | 1                                                                                             | The timeout period of the active check (unit: second).                                                               |
| upstream.checks.active.concurrency              | Active check                    | integer    |                      | 10                                                                                            | The number of targets to be checked at the same time during the active check.                                        |
| upstream.checks.active.http_path                | Active check                    | string     |                      | /                                                                                             | The HTTP request path that is actively checked.                                                                      |
| upstream.checks.active.host                     | Active check                    | string     |                      | ${upstream.node.host}                                                                         | The hostname of the HTTP request actively checked.                                                                   |
| upstream.checks.active.port                     | Active check                    | integer    | `1` to `65535`       | ${upstream.node.port}                                                                         | The host port of the HTTP request that is actively checked.                                                          |
| upstream.checks.active.https_verify_certificate | Active check                    | boolean    |                      | true                                                                                          | Active check whether to check the SSL certificate of the remote host when HTTPS type checking is used.               |
| upstream.checks.active.req_headers              | Active check                    | array      |                      | []                                                                                            | Active check When using HTTP or HTTPS type checking, set additional request header information.                      |
| upstream.checks.active.healthy.interval         | Active check (healthy node)    | integer    | `>= 1`               | 1                                                                                             | Active check (healthy node) check interval (unit: second)                                                            |
| upstream.checks.active.healthy.http_statuses    | Active check (healthy node)    | array      | `200` to `599`       | [200, 302]                                                                                    | Active check (healthy node) HTTP or HTTPS type check, the HTTP status code of the healthy node.                      |
| upstream.checks.active.healthy.successes        | Active check (healthy node)    | integer    | `1` to `254`         | 2                                                                                             | Active check (healthy node) determine the number of times a node is healthy.                                         |
| upstream.checks.active.unhealthy.interval       | Active check (unhealthy node)  | integer    | `>= 1`               | 1                                                                                             | Active check (unhealthy node) check interval (unit: second)                                                          |
| upstream.checks.active.unhealthy.http_statuses  | Active check (unhealthy node)  | array      | `200` to `599`       | [429, 404, 500, 501, 502, 503, 504, 505]                                                      | Active check (unhealthy node) HTTP or HTTPS type check, the HTTP status code of the non-healthy node.                |
| upstream.checks.active.unhealthy.http_failures  | Active check (unhealthy node)  | integer    | `1` to `254`         | 5                                                                                             | Active check (unhealthy node) HTTP or HTTPS type check, determine the number of times that the node is not healthy.  |
| upstream.checks.active.unhealthy.tcp_failures   | Active check (unhealthy node)  | integer    | `1` to `254`         | 2                                                                                             | Active check (unhealthy node) TCP type check, determine the number of times that the node is not healthy.            |
| upstream.checks.active.unhealthy.timeouts       | Active check (unhealthy node)  | integer    | `1` to `254`         | 3                                                                                             | Active check (unhealthy node) to determine the number of timeouts for unhealthy nodes.                              |
| upstream.checks.passive.healthy.http_statuses   | Passive check (healthy node)   | array      | `200` to `599`       | [200, 201, 202, 203, 204, 205, 206, 207, 208, 226, 300, 301, 302, 303, 304, 305, 306, 307, 308] | Passive check (healthy node) HTTP or HTTPS type check, the HTTP status code of the healthy node.                     |
| upstream.checks.passive.healthy.successes       | Passive check (healthy node)   | integer    | `0` to `254`         | 5                                                                                             | Passive checks (healthy node) determine the number of times a node is healthy.                                       |
| upstream.checks.passive.unhealthy.http_statuses | Passive check (unhealthy node) | array      | `200` to `599`       | [429, 500, 503]                                                                               | Passive check (unhealthy node) HTTP or HTTPS type check, the HTTP status code of the non-healthy node.               |
| upstream.checks.passive.unhealthy.tcp_failures  | Passive check (unhealthy node) | integer    | `0` to `254`         | 2                                                                                             | Passive check (unhealthy node) When TCP type is checked, determine the number of times that the node is not healthy. |
| upstream.checks.passive.unhealthy.timeouts      | Passive check (unhealthy node) | integer    | `0` to `254`         | 7                                                                                             | Passive checks (unhealthy node) determine the number of timeouts for unhealthy nodes.                                |
| upstream.checks.passive.unhealthy.http_failures | Passive check (unhealthy node) | integer    | `0` to `254`         | 5                                                                                             | Passive check (unhealthy node) The number of times that the node is not healthy during HTTP or HTTPS type checking.  |

### Configuration example

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

The health check status can be fetched via `GET /v1/healthcheck` in [Control API](./control-api.md).
