---
title: request-id
keywords:
  - APISIX
  - API 网关
  - Request ID
description: 本文介绍了 Apache APISIX request-id 插件的相关操作，你可以使用此插件为每个请求代理添加 unique ID 来追踪 API 请求。
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

`request-id` 插件通过 APISIX 为每一个请求代理添加 unique ID 用于追踪 API 请求。

:::note 注意

如果请求已经配置了 `header_name` 属性的请求头，该插件将不会为请求添加 unique ID。

:::

## 属性

| 名称                | 类型    | 必选项   | 默认值         | 有效值 | 描述                           |
| ------------------- | ------- | -------- | -------------- | ------ | ------------------------------ |
| header_name         | string  | 否 | "X-Request-Id" |                       | unique ID 的请求头的名称。         |
| include_in_response | boolean | 否 | true          |                       | 当设置为 `true` 时，将 unique ID 加入返回头。 |
| algorithm           | string  | 否 | "uuid"         | ["uuid", "nanoid", "range_id"] | 指定的 unique ID 生成算法。 |
| range_id.char_set      | string | 否 | "abcdefghijklmnopqrstuvwxyzABCDEFGHIGKLMNOPQRSTUVWXYZ0123456789| 字符串长度最小为 6 | range_id 算法的字符集 |
| range_id.length    | integer | 否 | 16             | 最小值为 6 | range_id 算法的 id 长度 |

## 启用插件

以下示例展示了如何在指定路由上启用 `request-id` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "request-id": {
            "include_in_response": true
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## 测试插件

按上述配置启用插件后，APISIX 将为你的每个请求创建一个 unique ID。

使用 `curl` 命令请求该路由：

```shell
curl -i http://127.0.0.1:9080/hello
```

返回的 HTTP 响应头中如果带有 `200` 状态码，且每次返回不同的 `X-Request-Id`，则表示插件生效：

```shell
HTTP/1.1 200 OK
X-Request-Id: fe32076a-d0a5-49a6-a361-6c244c1df956
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/get",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
