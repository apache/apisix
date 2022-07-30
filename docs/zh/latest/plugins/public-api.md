---
title: public-api
keywords:
  - APISIX
  - API 网关
  - Public API
  - public-api
description: public-api 插件用于通过一个通用的 HTTP API 路由暴露一个 API 端点。
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

`public-api` 插件用于通过一个通用的 HTTP API 路由暴露一个 API 端点。

当你使用自定义插件时，你可以使用 `public-api` 插件为特定功能定义一个固定的公共 API。例如，你可以使用 [`jwt-auth`](./jwt-auth.md) 插件创建一个公共 API 端点 `/apisix/plugin/jwt/sign` 用于 JWT 认证。

默认情况下，在自定义插件中添加的公共 API 是不公开的，用户需要手动配置一个路由并在上面启用 `public-api` 插件。

## 属性

| 名称  | 类型   | 必选项    | 默认值   | 描述                                                        |
|------|--------|----------|---------|------------------------------------------------------------|
| uri  | string | 否       | ""      | 公共 API 的 URI。在设置路由时，使用此属性来配置初始的公共 API URI。 |

## 启用插件

除了 `public-api` 插件，下面的例子也使用了 [`jwt-auth`](./jwt-auth.md) 和 [`key-auth`](./key-auth.md) 插件，详细使用方法请参考它们对应的文档。

### 基本用法

以下示例展示了如何在指定路由上启用并配置 `public-api` 插件：

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/apisix/plugin/jwt/sign",
    "plugins": {
        "public-api": {}
    }
}'
```

**测试插件**

向配置的 URI 发出访问请求，如果返回一个包含 JWT Token 的响应，则代表插件生效：

```shell
curl 'http://127.0.0.1:9080/apisix/plugin/jwt/sign?key=user-key'
```

```shell
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NTkyNTQzNzEsImtleSI6InVzZXIta2V5In0.q6i2VD3YChRjrfDHWw3wG36Y30OOH4Z1jl5N24KhfGw
```

### 使用自定义 URI

你可以使用一个自定义的 URI 来暴露 API：

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/gen_token",
    "plugins": {
        "public-api": {
            "uri": "/apisix/plugin/jwt/sign"
        }
    }
}'
```

**测试插件**

向自定义的 URI 发出访问请求，如果返回一个包含 JWT Token 的响应，则代表插件生效：

```shell
curl 'http://127.0.0.1:9080/gen_token?key=user-key'
```

```shell
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NTkyNTQzNzEsImtleSI6InVzZXIta2V5In0.q6i2VD3YChRjrfDHWw3wG36Y30OOH4Z1jl5N24KhfGw
```

### 确保 Route 安全

你可以使用 `key-auth` 插件来添加认证，从而确保路由的安全：

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/gen_token",
    "plugins": {
        "public-api": {
            "uri": "/apisix/plugin/jwt/sign"
        },
        "key-auth": {}
    }
}'
```

**测试插件**

通过上述命令启用插件并添加认证后，只有经过认证的请求才能访问。

发出访问请求并指定 `apikey`，如果返回 `200` HTTP 状态码，则说明请求被允许：

```shell
curl -i 'http://127.0.0.1:9080/gen_token?key=user-key'
    -H "apikey: test-apikey"
```

```shell
HTTP/1.1 200 OK
```

发出访问请求，如果返回 `401` HTTP 状态码，则说明请求被阻止，插件生效：

```shell
curl -i 'http://127.0.0.1:9080/gen_token?key=user-key'
```

```shell
HTTP/1.1 401 UNAUTHORIZED
```

## 禁用插件

当你需要禁用该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
