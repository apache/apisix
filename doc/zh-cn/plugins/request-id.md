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

[English](../plugins/request-id.md)

# 目录

- [**名称**](#名称)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)
- [**示例**](#示例)


## 名称

`request-id` 插件通过 APISIX 为每一个请求代理添加唯一 ID（UUID），以用于追踪 API 请求。该插件在 `header_name` 已经在请求中存在时不会为请求添加新的 ID

## 属性

| 名称                | 类型    | 必选项   | 默认值         | 有效值 | 描述                           |
| ------------------- | ------- | -------- | -------------- | ------ | ------------------------------ |
| header_name         | string  | 可选 | "X-Request-Id" |        | Request ID header name         |
| include_in_response | boolean | 可选 | false          |        | 是否需要在返回头中包含该唯一ID |

## 如何启用

创建一条路由并在该路由上启用 `request-id` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
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
}
```

## 测试插件

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
```

## 禁用插件

在路由 `plugins` 配置块中删除 `request-id 配置，即可禁用该插件，无需重启 APISIX。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
}
```
