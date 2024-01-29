---
title: limit-req
keywords:
  - APISIX
  - API 网关
  - Limit Request
  - limit-req
description: limit-req 插件使用漏桶算法限制对用户服务的请求速率。
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

`limit-req` 插件使用[漏桶算法](https://baike.baidu.com/item/%E6%BC%8F%E6%A1%B6%E7%AE%97%E6%B3%95/8455361)限制单个客户端对服务的请求速率。

## 属性

| 名称          | 类型    | 必选项 | 默认值 | 有效值                                                                                  | 描述                                                                                                                                              |
| ------------- | ------- | ------ | ------ | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| rate          | integer | 是   |        | rate > 0                                                                                | 指定的请求速率（以秒为单位），请求速率超过 `rate` 但没有超过（`rate` + `burst`）的请求会被延时处理。|
| burst         | integer | 是   |        | burst >= 0                                                                              | 请求速率超过（`rate` + `burst`）的请求会被直接拒绝。|
| key_type      | string  | 否   | "var"  | ["var", "var_combination"]                                                               | 要使用的用户指定 `key` 的类型。              |
| key           | string  | 是   |        | ["remote_addr", "server_addr", "http_x_real_ip", "http_x_forwarded_for", "consumer_name"] | 用来做请求计数的依据，当前接受的 `key` 有：`remote_addr`（客户端 IP 地址），`server_addr`（服务端 IP 地址）, 请求头中的 `X-Forwarded-For` 或 `X-Real-IP`，`consumer_name`（Consumer 的 `username`）。 |
| rejected_code | integer | 否   | 503    | [200,...,599]                                                                             | 当超过阈值的请求被拒绝时，返回的 HTTP 状态码。|
| rejected_msg  | string | 否    |        | 非空                                                                                      | 当超过阈值的请求被拒绝时，返回的响应体。|
| nodelay       | boolean | 否   | false  |                                                                                           | 当设置为 `true` 时，请求速率超过 `rate` 但没有超过（`rate` + `burst`）的请求不会加上延迟；当设置为 `false`，则会加上延迟。 |
| allow_degradation | boolean | 否 | false |                                                                                          | 当设置为 `true` 时，如果限速插件功能临时不可用，将会自动允许请求继续。|
| counter_type             | string  | 否                                | shared-dict | shared-dict, redis, redis-cluster | 计数器类型                                                                                                                                                                                                                 |
| redis_host          | string  | 否        |               |                                         | 当使用 `redis` 限速策略时，Redis 服务节点的地址。**当 `counter_type` 属性设置为 `redis` 时必选。**                                                                                                                                               |
| redis_port          | integer | 否        | 6379          | [1,...]                                 | 当使用 `redis` 限速策略时，Redis 服务节点的端口。                                                                                                                                                                                      |
| redis_username      | string  | 否        |               |                                         | 若使用 Redis ACL 进行身份验证（适用于 Redis 版本 >=6.0），则需要提供 Redis 用户名。若使用 Redis legacy 方式 `requirepass` 进行身份验证，则只需将密码配置在 `redis_password`。当 `counter_type` 设置为 `redis` 时使用。                                                        |
| redis_password      | string  | 否        |               |                                         | 当使用 `redis`  或者 `redis-cluster`  限速策略时，Redis 服务节点的密码。                                                                                                                                                                 |
| redis_ssl           | boolean | 否        | false         |                                         | 当使用 `redis` 限速策略时，如果设置为 true，则使用 SSL 连接到 `redis`                                                                                                                                                                      |
| redis_ssl_verify    | boolean | 否        | false         |                                         | 当使用 `redis` 限速策略时，如果设置为 true，则验证服务器 SSL 证书的有效性，具体请参考 [tcpsock:sslhandshake](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake).                                                                       |
| redis_database      | integer | 否        | 0             | redis_database >= 0                     | 当使用 `redis` 限速策略时，Redis 服务节点中使用的 `database`，并且只针对非 Redis 集群模式（单实例模式或者提供单入口的 Redis 公有云服务）生效。                                                                                                                           |
| redis_timeout       | integer | 否        | 1000          | [1,...]                                 | 当 `counter_type` 设置为 `redis` 或 `redis-cluster` 时，Redis 服务节点的超时时间（以毫秒为单位）。                                                                                                                                             |
| redis_cluster_nodes | array   | 否        |               |                                         | 当使用 `redis-cluster` 限速策略时，Redis 集群服务节点的地址列表（至少需要两个地址）。**当 `counter_type` 属性设置为 `redis-cluster` 时必选。**                                                                                                                 |
| redis_cluster_name  | string  | 否        |               |                                         | 当使用 `redis-cluster` 限速策略时，Redis 集群服务节点的名称。**当 `counter_type` 设置为 `redis-cluster` 时必选。**                                                                                                                               |
| redis_cluster_ssl  | boolean  | 否        |     false    |                                         | 当使用 `redis-cluster` 限速策略时，如果设置为 true，则使用 SSL 连接到 `redis-cluster`                                                                                                                                                      |
| redis_cluster_ssl_verify  | boolean  | 否        |     false        |                                         | 当使用 `redis-cluster` 限速策略时，如果设置为 true，则验证服务器 SSL 证书的有效性                                                                                                                                                                |

## 启用插件

### 在 Route 或 Service 上启用插件

以下示例展示了如何在指定路由上启用 `limit-req` 插件，并设置 `key_type` 的值为 `var`：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "limit-req": {
            "rate": 1,
            "burst": 2,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

上述示例表示，APISIX 将客户端的 IP 地址作为限制请求速率的条件，当请求速率小于 3 次每秒（`rate`）时，请求正常；当请求速率大于 3 次每秒（`rate`），小于 5 次每秒（`rate + burst`）时，将会对超出部分的请求进行延迟处理；当请求速率大于 5 次每秒（`rate + burst`）时，超出规定数量的请求将返回 HTTP 状态码 `503`。

你也可以设置 `key_type` 的值为 `var_combination`：

```json
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "limit-req": {
            "rate": 1,
            "burst": 2,
            "rejected_code": 503,
            "key_type": "var_combination",
            "key": "$consumer_name $remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:9001": 1
        }
    }
}
```

**测试插件**

通过以下命令发送请求：

```shell
curl -i http://127.0.0.1:9080/index.html
```

当请求速率超出限制时，返回如下包含 503 HTTP 状态码的响应头，插件生效：

```html
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
Server: APISIX web server

<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

同时，如果你设置了 `rejected_msg` 属性的值为 `"Requests are too frequent, please try again later."`，当请求速率超出限制时，返回如下包含 `503` HTTP 状态码的响应体：

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
Server: APISIX web server

{"error_msg":"Requests are too frequent, please try again later."}
```

### 在 Consumer 上启用插件

在 [Consumer](../terminology/consumer.md) 上启用 `limit-req` 插件需要与认证插件一起配合使用，以 [`key-auth`](./key-auth.md) 授权插件为例。

首先，将 `limit-req` 插件绑定到 Consumer 上：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "consumer_jack",
    "plugins": {
        "key-auth": {
            "key": "auth-jack"
        },
        "limit-req": {
            "rate": 1,
            "burst": 1,
            "rejected_code": 403,
            "key": "consumer_name"
        }
    }
}'
```

然后，在指定路由上启用并配置 `key-auth` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "key-auth": {
            "key": "auth-jack"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

**测试插件**

通过以下命令发送请求：

```shell
curl -i http://127.0.0.1:9080/index.html -H 'apikey: auth-jack'
```

当请求速率未超过 `rate + burst` 的值时，返回 `200` HTTP 状态码，说明请求成功，插件生效：

```shell
HTTP/1.1 200 OK
```

当请求速率超过 `rate + burst` 的值时，返回 `403` HTTP 状态码，说明请求被阻止，插件生效：

```shell
HTTP/1.1 403 Forbidden
...
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

你也可以通过以下命令移除 Consumer 上的 `limit-req` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "consumer_jack",
    "plugins": {
        "key-auth": {
            "key": "auth-jack"
        }
    }
}'
```
