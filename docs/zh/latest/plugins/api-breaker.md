---
title: api-breaker
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

## 简介

启用该插件后，网关将根据配置判断上游是否异常，若异常，则直接返回预设的错误码，且在一定时间内不再访问上游。

## 参数

|        参数名称         |    类型    | 必选  | 默认值 | 使用范围  |                                        描述                                        |
| :---------------------: | :--------: | :---: | :----: | :-------: | :--------------------------------------------------------------------------------: |
|   break_response_code   |   整数型   |  是   |        | 200 ~ 599 |                           上游不健康时，将返回该状态码。                           |
|     max_breaker_sec     |   整数型   |  否   |  300   |   >=60    |                                 最大熔断持续时间。                                 |
| unhealthy.http_statuses | 整数型数组 |  否   | [500]  | 500 ~ 599 | 当健康检查的探针返回值是状态码列表的某一个值时，代表不健康状态是由代理流量产生的。 |
|   unhealthy.failures    |   整数型   |  否   |   3    |    >=1    |    代理流量中 HTTP 失败的次数。如果达到此值，则认为上游服务目标节点是不健康的。    |
|  healthy.http_statuses  | 整数型数组 |  否   | [200]  | 200 ~ 499 |               HTTP 状态码列表，当探针在健康检查中返回时，视为健康。                |
|    healthy.successes    |   整数型   |  否   |   3    |    >=1    |            健康检查成功次数，若达到此值，表示上游服务目标节点是健康的。            |

## 使用 AdminAPI 启用插件

首先，创建路由并绑定该插件，以下配置表示：当在一个时间窗口内，上游返回 500 或 503 状态码超过 3 次，则标记上游不健康，触发熔断；当上游返回 200 状态码超过 1 次，则标记上游健康。

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
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
      "httpbin.org:80": 1
    }
  }
}
'
```

## 使用 AdminAPI 禁用插件

如果希望禁用插件，只需更新路由配置，从 plugins 字段移除该插件即可：

```bash
$ curl -X PUT http://127.0.0.1:9080/apisix/admin/routes/1 -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -d '
{
  "methods": ["GET"],
  "uri": "/get",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
'
```
