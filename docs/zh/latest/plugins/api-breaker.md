---
title: api-breaker
keywords:
  - Apache APISIX
  - API 网关
  - API Breaker
description: 本文介绍了 Apache APISIX api-breaker 插件的相关操作，你可以使用此插件的 API 熔断机制来保护上游业务服务。
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

## 描述

`api-breaker` 插件实现了 API 熔断功能，从而帮助我们保护上游业务服务。

该插件支持两种熔断策略：

- **按错误次数熔断（`unhealthy-count`）**：当连续失败次数达到阈值时触发熔断
- **按错误比例熔断（`unhealthy-ratio`）**：当在滑动时间窗口内的错误率达到阈值时触发熔断

:::note 注意

**按错误次数熔断（`unhealthy-count`）**：

当上游服务返回 `unhealthy.http_statuses` 配置中的状态码（默认为 `500`），并达到 `unhealthy.failures` 预设次数时（默认为 3 次），则认为上游服务处于不健康状态。

第一次触发不健康状态时，熔断 2 秒。超过熔断时间后，将重新开始转发请求到上游服务，如果继续返回 `unhealthy.http_statuses` 状态码，记数再次达到 `unhealthy.failures` 预设次数时，熔断 4 秒。依次类推（2，4，8，16，……），直到达到预设的 `max_breaker_sec`值。

当上游服务处于不健康状态时，如果转发请求到上游服务并返回 `healthy.http_statuses` 配置中的状态码（默认为 `200`），并达到 `healthy.successes` 次时，则认为上游服务恢复至健康状态。

**按错误比例熔断（`unhealthy-ratio`）**：

该策略基于滑动时间窗口统计错误率。当在 `sliding_window_size` 时间窗口内，请求总数达到 `min_request_threshold` 且错误率超过 `error_ratio` 时，熔断器进入开启状态，持续 `max_breaker_sec` 秒。

熔断器有三种状态：

- **关闭（CLOSED）**：正常转发请求
- **开启（OPEN）**：直接返回熔断响应，不转发请求
- **半开启（HALF_OPEN）**：允许少量请求通过以测试服务是否恢复

:::

## 属性

| 名称                   | 类型          | 必选项 | 默认值            | 有效值                                                                                                                                                                                                                                                                           | 描述                                                                                   |
| ---------------------- | ------------- | ------ | ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| break_response_code    | integer       | 是     |                   | [200, ..., 599]                                                                                                                                                                                                                                                                  | 当上游服务处于不健康状态时返回的 HTTP 错误码。                                         |
| break_response_body    | string        | 否     |                   |                                                                                                                                                                                                                                                                                  | 当上游服务处于不健康状态时返回的 HTTP 响应体信息。                                     |
| break_response_headers | array[object] | 否     |                   | [{"key":"header_name","value":"can contain Nginx$var"}] | 当上游服务处于不健康状态时返回的 HTTP 响应头信息。该字段仅在配置了 `break_response_body` 属性时生效，并能够以 `$var` 的格式包含 APISIX 变量，比如`{"key":"X-Client-Addr","value":"$remote_addr:$remote_port"}`。 |                                                                                        |
| max_breaker_sec        | integer       | 否     | 300               | >=3                                                                                                                                                                                                                                                                              | 上游服务熔断的最大持续时间，以秒为单位。适用于两种熔断策略。                           |
| policy                 | string        | 否     | "unhealthy-count" | ["unhealthy-count", "unhealthy-ratio"]                                                                                                                                                                                                                                           | 熔断策略。`unhealthy-count` 为按错误次数熔断，`unhealthy-ratio` 为按错误比例熔断。 |

### 按错误次数熔断（policy = "unhealthy-count"）

| 名称                    | 类型           | 必选项 | 默认值 | 有效值          | 描述                                               |
| ----------------------- | -------------- | ------ | ------ | --------------- | -------------------------------------------------- |
| unhealthy.http_statuses | array[integer] | 否     | [500]  | [500, ..., 599] | 上游服务处于不健康状态时的 HTTP 状态码。           |
| unhealthy.failures      | integer        | 否     | 3      | >=1             | 上游服务在一定时间内触发不健康状态的异常请求次数。 |
| healthy.http_statuses   | array[integer] | 否     | [200]  | [200, ..., 499] | 上游服务处于健康状态时的 HTTP 状态码。             |
| healthy.successes       | integer        | 否     | 3      | >=1             | 上游服务触发健康状态的连续正常请求次数。           |

### 按错误比例熔断（policy = "unhealthy-ratio"）

| 名称                                                   | 类型           | 必选项 | 默认值 | 有效值          | 描述                                                                                     |
| ------------------------------------------------------ | -------------- | ------ | ------ | --------------- | ---------------------------------------------------------------------------------------- |
| unhealthy.http_statuses                                | array[integer] | 否     | [500]  | [500, ..., 599] | 上游服务处于不健康状态时的 HTTP 状态码。                                                 |
| unhealthy.error_ratio                                  | number         | 否     | 0.5    | [0, 1]          | 触发熔断的错误率阈值。例如 0.5 表示错误率达到 50% 时触发熔断。                           |
| unhealthy.min_request_threshold                        | integer        | 否     | 10     | >=1             | 在滑动时间窗口内触发熔断所需的最小请求数。只有请求数达到此阈值时才会评估错误率。         |
| unhealthy.sliding_window_size                          | integer        | 否     | 300    | [10, 3600]      | 滑动时间窗口大小，以秒为单位。用于统计错误率的时间范围。                                 |
| unhealthy.half_open_max_calls | integer        | 否     | 3      | [1, 20]         | 在半开启状态下允许通过的请求数量。用于测试服务是否恢复正常。                             |
| healthy.http_statuses                                  | array[integer] | 否     | [200]  | [200, ..., 499] | 上游服务处于健康状态时的 HTTP 状态码。                                                   |
| healthy.successes                                      | integer        | 否     | 3      | >=1             | 上游服务触发健康状态的连续正常请求次数。                                                 |
| healthy.success_ratio                                  | number         | 否     | 0.6    | [0, 1]          | 在半开启状态下，成功率达到此阈值时熔断器关闭。例如 0.6 表示成功率达到 60% 时关闭熔断器。 |

## 启用插件

### 按错误次数熔断示例

以下示例展示了如何在指定路由上启用 `api-breaker` 插件的按错误次数熔断策略，该路由配置表示在一定时间内返回 `500` 或 `503` 状态码达到 3 次后触发熔断，返回 `200` 状态码 1 次后恢复健康：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "api-breaker": {
            "break_response_code": 502,
            "policy": "unhealthy-count",
            "unhealthy": {
                "http_statuses": [500, 503],
                "failures": 3
            },
            "healthy": {
                "http_statuses": [200],
                "successes": 1
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "uri": "/hello"
}'
```

### 按错误比例熔断示例

以下示例展示了如何启用按错误比例熔断策略。该配置表示在 5 分钟的滑动时间窗口内，当请求数达到 10 次且错误率超过 50% 时触发熔断：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/2" \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "api-breaker": {
            "break_response_code": 503,
            "break_response_body": "Service temporarily unavailable due to high error rate",
            "break_response_headers": [
                {"key": "X-Circuit-Breaker", "value": "open"},
                {"key": "Retry-After", "value": "60"}
            ],
            "policy": "unhealthy-ratio",
            "max_breaker_sec": 60,
            "unhealthy": {
                "http_statuses": [500, 502, 503, 504],
                "error_ratio": 0.5,
                "min_request_threshold": 10,
                "sliding_window_size": 300,
                "half_open_max_calls": 3
            },
            "healthy": {
                "http_statuses": [200, 201, 202],
                "successes": 3
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "uri": "/api"
}'
```

## 测试插件

按上述配置启用插件后，使用 `curl` 命令请求该路由：

```shell
curl -i -X POST "http://127.0.0.1:9080/hello"
```

如果上游服务在一定时间内返回 `500` 状态码达到 3 次，客户端将会收到 `502 Bad Gateway` 的应答：

```shell
HTTP/1.1 502 Bad Gateway
...
<html>
<head><title>502 Bad Gateway</title></head>
<body>
<center><h1>502 Bad Gateway</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

## 删除插件

当你需要禁用该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
