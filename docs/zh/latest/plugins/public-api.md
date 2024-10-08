---
title: public-api
keywords:
  - APISIX
  - API 网关
  - Public API
description: 本文介绍了 public-api 的相关操作，你可以使用 public-api 插件保护你需要暴露的 API 的端点。
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

`public-api` 插件可用于通过创建路由的方式暴露用户自定义的 API。

你可以通过在路由中添加 `public-api` 插件，来保护**自定义插件为了实现特定功能**而暴露的 API。例如，你可以使用 [batch-requests](./batch-requests.md) 插件创建一个公共 API 端点 `/apisix/batch-requests` 用于在一个请求中组合多个 API 请求。

:::note 注意

默认情况下，在自定义插件中添加的公共 API 不对外暴露的，你需要手动配置一个路由并启用 `public-api` 插件。

:::

## 属性

| 名称  | 类型   | 必选项    | 默认值   | 描述                                                        |
|------|--------|----------|---------|------------------------------------------------------------|
| uri  | string | 否       | ""      | 公共 API 的 URI。在设置路由时，使用此属性来配置初始的公共 API URI。 |

## 启用插件

`public-api` 插件需要与授权插件一起配合使用，以下示例分别用到了 [batch-requests](./batch-requests.md) 插件和 [`key-auth`](./key-auth.md)

### 基本用法

首先，你需要启用并配置 `batch-requests` 插件，详细使用方法请参考 [batch-requests](./batch-requests.md) 插件文档。

然后，使用以下命令在指定路由上启用并配置 `public-api` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
      "uri": "/apisix/batch-requests",
      "plugins": {
        "public-api": {}
    }
}'
```

**测试插件**

向配置的 URI 发出访问请求，会返回一个包含多个 API 请求结果的的响应：

```shell
curl --location --request POST 'http://127.0.0.1:9080/apisix/batch-requests' \
--header 'Content-Type: application/json' \
--data '{
    "headers": {
        "Content-Type": "application/json",
        "admin-jwt":"xxxx"
    },
    "timeout": 500,
    "pipeline": [
        {
            "method": "POST",
            "path": "/community.GiftSrv/GetGifts",
            "body": "test"
        },
        {
            "method": "POST",
            "path": "/community.GiftSrv/GetGifts",
            "body": "test2"
        }
    ]
}'
```

```shell
[
  {
    "status": 200,
    "reason": "OK",
    "body": "{\"ret\":500,\"msg\":\"error\",\"game_info\":null,\"gift\":[],\"to_gets\":0,\"get_all_msg\":\"\"}",
    "headers": {
      "Connection": "keep-alive",
      "Date": "Sat, 11 Apr 2020 17:53:20 GMT",
      "Content-Type": "application/json",
      "Content-Length": "81",
      "Server": "APISIX web server"
    }
  },
  {
    "status": 200,
    "reason": "OK",
    "body": "{\"ret\":500,\"msg\":\"error\",\"game_info\":null,\"gift\":[],\"to_gets\":0,\"get_all_msg\":\"\"}",
    "headers": {
      "Connection": "keep-alive",
      "Date": "Sat, 11 Apr 2020 17:53:20 GMT",
      "Content-Type": "application/json",
      "Content-Length": "81",
      "Server": "APISIX web server"
    }
  }
]
```

### 使用自定义 URI

首先，你需要启用并配置 `batch-requests` 插件，详细使用方法请参考 [batch-requests](./batch-requests.md) 插件文档。

然后，你可以使用一个自定义的 URI 来暴露 API：

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
      "uri": "/batch-requests-gifs",
      "plugins": {
        "public-api": {
            "uri": "/apisix/batch-requests"
        }
    }
}'
```

**测试插件**

向自定义的 URI 发出访问请求，如果返回一个包含多个 API 请求结果的响应，则代表插件生效：

```shell
curl --location --request POST 'http://127.0.0.1:9080/batch-requests-gifs' \
--header 'Content-Type: application/json' \
--data '{...}'
```

### 确保 Route 安全

你可以配合使用 `key-auth` 插件来添加认证，从而确保路由的安全：

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r2' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/batch-requests-gifs",
    "plugins": {
        "public-api": {},
        "key-auth": {}
    }
}'
```

**测试插件**

通过上述命令启用插件并添加认证后，只有经过认证的请求才能访问。

发出访问请求并指定 `apikey`，如果返回 `200` HTTP 状态码，则说明请求被允许：

```shell
curl --location --request POST 'http://127.0.0.1:9080/batch-requests-gifs' \
    -H "apikey: test-apikey"
    -H 'Content-Type: application/json' \
    --data '{...}'
```

```shell
HTTP/1.1 200 OK
```

发出访问请求，如果返回 `401` HTTP 状态码，则说明请求被阻止，插件生效：

```shell
curl --location --request POST 'http://127.0.0.1:9080/batch-requests-gifs' \
    -H 'Content-Type: application/json' \
    --data '{...}'
```

```shell
HTTP/1.1 401 Unauthorized
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
