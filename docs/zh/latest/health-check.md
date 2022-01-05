---
title: 健康检查
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

## Upstream 的健康检查

Apache APISIX 的健康检查使用 [lua-resty-healthcheck](https://github.com/Kong/lua-resty-healthcheck) 实现。

注意:

* 只有在 `upstream` 被请求时才会开始健康检查，如果 `upstream` 被配置但没有被请求，不会触发启动健康检查。
* 如果没有健康的节点，那么请求会继续发送给上游。
* 如果 `upstream` 中只有一个节点时不会触发启动健康检查，该唯一节点无论是否健康，请求都将转发给上游。
* 主动健康检查是必须的，这样不健康的节点才会恢复。

### 配置说明

| 配置项                                       | 配置类型           | 值类型 | 值选项               | 默认值                                                                                     | 描述                                                                    |
| ----------------------------------------------- | ---------------------- | ------- | -------------------- | --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| upstream.checks.active.type                     | 主动检查           | string  | `http` `https` `tcp` | http                                                                                          | 主动检查的类型。                                                  |
| upstream.checks.active.timeout                  | 主动检查           | integer |                      | 1                                                                                             | 主动检查的超时时间（单位：秒）。                          |
| upstream.checks.active.concurrency              | 主动检查           | integer |                      | 10                                                                                            | 主动检查时同时检查的目标数。                                |
| upstream.checks.active.http_path                | 主动检查           | string  |                      | /                                                                                             | 主动检查的 HTTP 请求路径。                                      |
| upstream.checks.active.host                     | 主动检查           | string  |                      | ${upstream.node.host}                                                                         | 主动检查的 HTTP 请求主机名。                                   |
| upstream.checks.active.port                     | 主动检查           | integer | `1` 至 `65535`      | ${upstream.node.port}                                                                         | 主动检查的 HTTP 请求主机端口。                                |
| upstream.checks.active.https_verify_certificate | 主动检查           | boolean |                      | true                                                                                          | 主动检查使用 HTTPS 类型检查时，是否检查远程主机的SSL证书。 |
| upstream.checks.active.req_headers              | 主动检查           | array   |                      | []                                                                                            | 主动检查使用 HTTP 或 HTTPS类型检查时，设置额外的请求头信息。 |
| upstream.checks.active.healthy.interval         | 主动检查（健康节点） | integer | `>= 1`               | 1                                                                                             | 主动检查（健康节点）检查的间隔时间（单位：秒）     |
| upstream.checks.active.healthy.http_statuses    | 主动检查（健康节点） | array   | `200` 至 `599`      | [200, 302]                                                                                    | 主动检查（健康节点） HTTP 或 HTTPS 类型检查时，健康节点的HTTP状态码。 |
| upstream.checks.active.healthy.successes        | 主动检查（健康节点） | integer | `1` 至 `254`        | 2                                                                                             | 主动检查（健康节点）确定节点健康的次数。              |
| upstream.checks.active.unhealthy.interval       | 主动检查（非健康节点） | integer | `>= 1`               | 1                                                                                             | 主动检查（非健康节点）检查的间隔时间（单位：秒）  |
| upstream.checks.active.unhealthy.http_statuses  | 主动检查（非健康节点） | array   | `200` 至 `599`      | [429, 404, 500, 501, 502, 503, 504, 505]                                                      | 主动检查（非健康节点） HTTP 或 HTTPS 类型检查时，非健康节点的HTTP状态码。 |
| upstream.checks.active.unhealthy.http_failures  | 主动检查（非健康节点） | integer | `1` 至 `254`        | 5                                                                                             | 主动检查（非健康节点）HTTP 或 HTTPS 类型检查时，确定节点非健康的次数。 |
| upstream.checks.active.unhealthy.tcp_failures   | 主动检查（非健康节点） | integer | `1` 至 `254`        | 2                                                                                             | 主动检查（非健康节点）TCP 类型检查时，确定节点非健康的次数。 |
| upstream.checks.active.unhealthy.timeouts       | 主动检查（非健康节点） | integer | `1` 至 `254`        | 3                                                                                             | 主动检查（非健康节点）确定节点非健康的超时次数。  |
| upstream.checks.passive.healthy.http_statuses   | 被动检查（健康节点） | array   | `200` 至 `599`      | [200, 201, 202, 203, 204, 205, 206, 207, 208, 226, 300, 301, 302, 303, 304, 305, 306, 307, 308] | 被动检查（健康节点） HTTP 或 HTTPS 类型检查时，健康节点的HTTP状态码。 |
| upstream.checks.passive.healthy.successes       | 被动检查（健康节点） | integer | `0` 至 `254`        | 5                                                                                             | 被动检查（健康节点）确定节点健康的次数。              |
| upstream.checks.passive.unhealthy.http_statuses | 被动检查（非健康节点） | array   | `200` 至 `599`      | [429, 500, 503]                                                                               | 被动检查（非健康节点） HTTP 或 HTTPS 类型检查时，非健康节点的HTTP状态码。 |
| upstream.checks.passive.unhealthy.tcp_failures  | 被动检查（非健康节点） | integer | `0` 至 `254`        | 2                                                                                             | 被动检查（非健康节点）TCP 类型检查时，确定节点非健康的次数。 |
| upstream.checks.passive.unhealthy.timeouts      | 被动检查（非健康节点） | integer | `0` 至 `254`        | 7                                                                                             | 被动检查（非健康节点）确定节点非健康的超时次数。  |
| upstream.checks.passive.unhealthy.http_failures | 被动检查（非健康节点） | integer | `0` 至 `254`        | 5                                                                                             | 被动检查（非健康节点）HTTP 或 HTTPS 类型检查时，确定节点非健康的次数。 |

### 配置示例：

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

健康检查信息可以通过 [控制接口](./control-api.md) 中的 `GET /v1/healthcheck` 接口得到。
