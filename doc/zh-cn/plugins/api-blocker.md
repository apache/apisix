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

- [English](../../plugins/api-blocker.md)

# 目录

- [**定义**](#定义)
- [**属性列表**](#属性列表)
- [**启用方式**](#启用方式)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 定义

该插件实现API熔断功能，帮助我们保护上游业务服务。

## 属性列表

| 名称                    | 类型           | 必选项 | 默认值     | 有效值          | 描述                             |
| ----------------------- | -------------- | ------ | ---------- | --------------- | -------------------------------- |
| unhealthy_response_code | integer        | 必须   | 无         | [200, ..., 600] | 不健康返回错误码                 |
| unhealthy.http_statuses | array[integer] | 必须   | {500}      | [500, ..., 599] | 不健康时候的状态码               |
| unhealthy.failures      | integer        | 必须   | 1          | >=1             | 触发不健康状态的连续错误请求次数 |
| healthy.http_statuses   | array[integer] | 必须   | {200, 206} | [200, ..., 499] | 健康时候的状态码                 |
| successes.successes     | integer        | 必须   | 1          | >=1             | 触发健康状态的连续正常请求次数   |

## 启用方式

这是一个示例，在指定的路由上启用`api-breaker`插件：

```shell
curl "http://127.0.0.1:9080/apisix/admin/routes/5" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
   {
      "plugins": {
          "api-breaker": {
              "unhealthy_response_code": 502,
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
     "uri": "/get",
      "host": "127.0.0.1",
      "upstream_id": 50
  }'
```

## 测试插件

```shell
$ curl -i -X POST "http://127.0.0.1:9080/get?list=1,b,c"
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 0
Connection: keep-alive
Server: APISIX/1.5
Server: openresty/1.17.8.2
Date: Tue, 29 Sep 2020 05:00:02 GMT

... ...
```

## 禁用插件

当想禁用`api-breaker`插件时，非常简单，只需要在插件配置中删除相应的 json 配置，无需重启服务，即可立即生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/*",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

 `api-breaker` 插件现在已被禁用，它也适用于其他插件。
