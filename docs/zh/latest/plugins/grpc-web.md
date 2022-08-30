---
title: grpc-web
keywords:
  - APISIX
  - Plugin
  - gRPC Web
  - grpc-web
description: 本文介绍了关于 Apache APISIX `grpc-web` 插件的基本信息及使用方法。
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

`grpc-web` 插件是一个代理插件，可以处理从 JavaScript 客户端到 gRPC Service 的 [gRPC Web](https://github.com/grpc/grpc-web) 请求。

## 启用插件

你可以通过如下命令在指定路由上启用 `gRPC-web` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri":"/grpc/web/*",
    "plugins":{
        "grpc-web":{}
    },
    "upstream":{
        "scheme":"grpc",
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    }
}'
```

:::info IMPORTANT

在使用 `gRPC Web` 代理插件时，路由必须使用**前缀匹配**模式（例如：`/*` 或 `/grpc/example/*`），因为 `gRPC Web` 客户端会在 URI 中传递 `proto` 中声明的**包名称**、**服务接口名称**、**方法名称**等信息（例如：`/path/a6.RouteService/Insert`）。

因此，在使用**绝对匹配**时将无法命中插件和提取 `proto` 信息。

:::

## 测试插件

请参考 [gRPC-Web Client Runtime Library](https://www.npmjs.com/package/grpc-web) 或 [Apache APISIX gRPC Web Test Framework](https://github.com/apache/apisix/tree/master/t/plugin/grpc-web) 了解如何配置你的 Web 客户端。

运行 gRPC Web 客户端后，你可以从浏览器或通过 Node.js 向 APISIX 发出请求。

:::note

请求方式仅支持 `POST` 和 `OPTIONS`，详细信息请参考：[CORS support](https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support) 。

内容类型支持 `application/grpc-web`、`application/grpc-web-text`、`application/grpc-web+proto`、`application/grpc-web-text+proto`，详细信息请参考：[Protocol differences vs gRPC over HTTP2](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md#protocol-differences-vs-grpc-over-http2) 。

:::

## 禁用插件

当你需要禁用 `grpc-web` 插件时，可以通过如下命令删除相应的 `JSON` 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri":"/grpc/web/*",
    "plugins":{},
    "upstream":{
        "scheme":"grpc",
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    }
}'
```
