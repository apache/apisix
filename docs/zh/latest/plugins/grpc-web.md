---
title: grpc-web
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

`grpc-web` 插件是一个代理插件，用于转换 [gRPC Web](https://github.com/grpc/grpc-web) 客户端到 `gRPC Server` 的请求。

gRPC Web Client -> APISIX -> gRPC server

## 如何开启

启用 `gRPC Web` 代理插件，路由必须使用 `前缀匹配` 模式（例如：`/*` 或 `/grpc/example/*`），
因为 `gRPC Web` 客户端会在 URI 中传递 `proto` 中声明的`包名称`、`服务接口名称`、`方法名称`等信息（例如：`/path/a6.RouteService/Insert`）,
使用 `绝对匹配` 时将无法命中插件和提取 `proto` 信息。

```bash
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## 测试插件

- 请求方式仅支持 `POST` 和 `OPTIONS`，参考：[CORS support](https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support) 。
- 内容类型支持 `application/grpc-web`、`application/grpc-web-text`、`application/grpc-web+proto`、`application/grpc-web-text+proto`，参考：[Protocol differences vs gRPC over HTTP2](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md#protocol-differences-vs-grpc-over-http2) 。
- 客户端部署，参考：[gRPC-Web Client Runtime Library](https://www.npmjs.com/package/grpc-web) 或 [Apache APISIX gRPC Web 测试框架](https://github.com/apache/apisix/tree/master/t/plugin/grpc-web) 。
- 完成 `gRPC Web` 客户端部署后，即可通过 `浏览器` 或 `node` 向 `APISIX` 发起 `gRPC Web` 代理请求。

## 禁用插件

只需删除插件配置中 `grpc-web` 的JSON配置即可。 APISIX 插件是热加载的，所以不需要重启 APISIX。

```bash
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
