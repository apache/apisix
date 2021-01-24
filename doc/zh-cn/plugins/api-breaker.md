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

- [English](../../plugins/api-breaker.md)

# 目录

- [**定义**](#定义)
- [**属性列表**](#属性列表)
- [**启用方式**](#启用方式)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 定义

该插件实现 API 熔断功能，帮助我们保护上游业务服务。

> 关于熔断超时逻辑

由代码逻辑自动按**触发不健康状态**的次数递增运算：

每当上游服务返回`unhealthy.http_statuses`配置中的状态码(比如：500)，达到`unhealthy.failures`次时(比如：3 次)，认为上游服务处于不健康状态。

第一次触发不健康状态，**熔断 2 秒**。

然后，2 秒过后重新开始转发请求到上游服务，如果继续返回`unhealthy.http_statuses`状态码，记数再次达到`unhealthy.failures`次时，**熔断 4 秒**（倍数方式）。

依次类推，2, 4, 8, 16, 32, 64, ..., 256, 最大到 300。 300 是 `max_breaker_sec` 的最大值，允许自定义修改。

在不健康状态时，当转发请求到上游服务并返回`healthy.http_statuses`配置中的状态码(比如：200)，达到`healthy.successes`次时(比如：3 次)，认为上游服务恢复健康状态。

## 属性列表

| 名称                    | 类型           | 必选项 | 默认值     | 有效值          | 描述                             |
| ----------------------- | -------------- | ------ | ---------- | --------------- | -------------------------------- |
| break_response_code | integer        | 必须   | 无         | [200, ..., 600] | 不健康返回错误码                 |
| max_breaker_sec     | integer        | 可选   | 300        | >=60            | 最大熔断持续时间                 |
| unhealthy.http_statuses | array[integer] | 可选   | {500}      | [500, ..., 599] | 不健康时候的状态码               |
| unhealthy.failures      | integer        | 可选   | 1          | >=1             | 触发不健康状态的连续错误请求次数 |
| healthy.http_statuses   | array[integer] | 可选   | {200, 206} | [200, ..., 499] | 健康时候的状态码                 |
| healthy.successes       | integer        | 可选   | 1          | >=1             | 触发健康状态的连续正常请求次数   |

## 启用方式

这是一个示例，在指定的路由上启用`api-breaker`插件。
应答 500 或 503 连续 3 次，触发熔断。应答 200 连续 1 次，恢复健康。

```shell
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
    "uri": "/hello",
    "host": "127.0.0.1"
}'
```

## 测试插件

使用上游的配置，如果你的上流服务返回 500，连续 3 次。客户端将会收到 502（break_response_code）应答。

```shell
$ curl -i "http://127.0.0.1:9080/get"
HTTP/1.1 502 Bad Gateway
Content-Type: application/octet-stream
Connection: keep-alive
Server: APISIX/1.5

... ...
```

## 禁用插件

当想禁用`api-breaker`插件时，非常简单，只需要在插件配置中删除相应的 json 配置，无需重启服务，即可立即生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

`api-breaker` 插件现在已被禁用，它也适用于其他插件。
