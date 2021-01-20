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

# [English](../health-check.md)

## Upstream的健康检查

APISIX的健康检查使用[lua-resty-healthcheck](https://github.com/Kong/lua-resty-healthcheck)实现，你可以在upstream中使用它。

注意只有在 upstream 被请求时才会开始健康检查。
如果一个 upstream 被配置但没有被请求，那么就不会有健康检查。

下面是一个检查检查的例子：

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

监控检查的配置内容在`checks`中，`checks`包含两个类型：`active` 和 `passive`，详情如下

* `active`: 要启动探活健康检查，需要在upstream配置中的 `checks.active` 添加如下配置项。

    * `active.timeout`: 主动健康检查 socket 超时时间（秒为单位），支持小数点。比如 `1.01` 代表 `1010` 毫秒，`2` 代表 `2000` 毫秒。

    * `active.http_path`: 用于发现upstream节点健康可用的HTTP GET请求路径。
    * `active.host`: 用于发现upstream节点健康可用的HTTP请求主机名。
    * `active.port`: 用于发现upstream节点健康可用的自定义主机端口（可选），配置此项会覆盖 `upstream` 节点中的端口。

    `healthy`的阀值字段：
    * `active.healthy.interval`: 健康的目标节点的健康检查间隔时间（以秒为单位），最小值为1。
    * `active.healthy.successes`: 确定目标是否健康的成功次数，最小值为1。

    `unhealthy`的阀值字段：
    * `active.unhealthy.interval`: 针对不健康目标节点的健康检查之间的间隔（以秒为单位），最小值为1。
    * `active.unhealthy.http_failures`: 确定目标节点不健康的http请求失败次数，最小值为1。
    * `active.req_headers`: 其他请求标头。数组格式，可以填写多个标题。

* `passive`: 要启用被动健康检查，需要在upstream配置中的 `checks.passive` 添加如下配置项。

    `healthy`的阀值字段：
    * `passive.healthy.http_statuses`: 如果当前HTTP响应状态码是其中任何一个，则将upstream节点设置为 `healthy` 状态。否则，请忽略此请求。
    * `passive.healthy.successes`: 如果upstream节点被检测成功（由 `passive.healthy.http_statuses` 定义）的次数超过 `successes` 次，则将该节点设置为 `healthy` 状态。

    `unhealthy`的阀值字段：
    * `passive.unhealthy.http_statuses`: 如果当前HTTP响应状态码是其中任何一个，则将upstream节点设置为 `unhealthy` 状态。否则，请忽略此请求。
    * `passive.unhealthy.tcp_failures`: 如果TCP通讯失败次数超过 `tcp_failures` 次，则将upstream节点设置为 `unhealthy` 状态。
    * `passive.unhealthy.timeouts`: 如果被动健康检查超时次数超过 `timeouts` 次，则将upstream节点设置为 `unhealthy` 状态。
    * `passive.unhealthy.http_failures`: 如果被动健康检查的HTTP请求失败（由 `passive.unhealthy.http_statuses` 定义）的次数超过 `http_failures`次，则将upstream节点设置为 `unhealthy` 状态。

健康检查信息可以通过 [控制接口](./control_api.md) 中的 `GET /v1/healthcheck` 接口得到。
