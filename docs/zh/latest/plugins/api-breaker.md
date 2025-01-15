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

:::note 注意

关于熔断超时逻辑，由代码逻辑自动按**触发不健康状态**的次数递增运算：

当上游服务返回 `unhealthy.http_statuses` 配置中的状态码（默认为 `500`），并达到 `unhealthy.failures` 预设次数时（默认为 3 次），则认为上游服务处于不健康状态。

第一次触发不健康状态时，熔断 2 秒。超过熔断时间后，将重新开始转发请求到上游服务，如果继续返回 `unhealthy.http_statuses` 状态码，记数再次达到 `unhealthy.failures` 预设次数时，熔断 4 秒。依次类推（2，4，8，16，……），直到达到预设的 `max_breaker_sec`值。

当上游服务处于不健康状态时，如果转发请求到上游服务并返回 `healthy.http_statuses` 配置中的状态码（默认为 `200`），并达到 `healthy.successes` 次时，则认为上游服务恢复至健康状态。

:::

## 属性

| 名称                    | 类型           | 必选项 | 默认值     | 有效值          | 描述                             |
| ----------------------- | -------------- | ------ | ---------- | --------------- | -------------------------------- |
| break_response_code     | integer        | 是   |           | [200, ..., 599] | 当上游服务处于不健康状态时返回的 HTTP 错误码。                 |
| break_response_body     | string         | 否   |           |                 | 当上游服务处于不健康状态时返回的 HTTP 响应体信息。                   |
| break_response_headers  | array[object]  | 否   |           | [{"key":"header_name","value":"can contain Nginx $var"}] | 当上游服务处于不健康状态时返回的 HTTP 响应头信息。该字段仅在配置了 `break_response_body` 属性时生效，并能够以 `$var` 的格式包含 APISIX 变量，比如 `{"key":"X-Client-Addr","value":"$remote_addr:$remote_port"}`。 |
| max_breaker_sec         | integer        | 否   | 300        | >=3             | 上游服务熔断的最大持续时间，以秒为单位。                 |
| unhealthy.http_statuses | array[integer] | 否   | [500]      | [500, ..., 599] | 上游服务处于不健康状态时的 HTTP 状态码。               |
| unhealthy.failures      | integer        | 否   | 3          | >=1             | 上游服务在一定时间内触发不健康状态的异常请求次数。 |
| healthy.http_statuses   | array[integer] | 否   | [200]      | [200, ..., 499] | 上游服务处于健康状态时的 HTTP 状态码。                 |
| healthy.successes       | integer        | 否   | 3          | >=1             | 上游服务触发健康状态的连续正常请求次数。   |

## 启用插件

以下示例展示了如何在指定路由上启用 `api-breaker` 插件，该路由配置表示在一定时间内返回 `500` 或 `503` 状态码达到 3 次后触发熔断，返回 `200` 状态码 1 次后恢复健康：

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
