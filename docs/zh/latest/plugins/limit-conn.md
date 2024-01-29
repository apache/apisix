---
title: limit-conn
keywords:
  - APISIX
  - API 网关
  - Limit Connection
description: 本文介绍了 Apache APISIX limit-conn 插件的相关操作，你可以使用此插件限制客户端对服务的并发请求数。
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

`limit-conn` 插件用于限制客户端对单个服务的并发请求数。当客户端对路由的并发请求数达到限制时，可以返回自定义的状态码和响应信息。

## 属性

| 名称               | 类型    | 必选项                              | 默认值 | 有效值                      | 描述                                                                                                                                                                                                                    |
| ------------------ | ------- |----------------------------------| ------ | -------------------------- |-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| conn               | integer | 是                                |        | conn > 0                   | 允许的最大并发请求数。超过 `conn` 的限制、但是低于 `conn` + `burst` 的请求，将被延迟处理。                                                                                                                                                            |
| burst              | integer | 是                                |        | burst >= 0                 | 每秒允许被延迟处理的额外并发请求数。                                                                                                                                                                                                    |
| default_conn_delay | number  | 是                                |        | default_conn_delay > 0     | 默认的典型连接（或请求）的处理延迟时间。                                                                                                                                                                                                  |
| only_use_default_delay | boolean | 否                                | false | [true,false]               | 延迟时间的严格模式。当设置为 `true` 时，将会严格按照设置的 `default_conn_delay` 时间来进行延迟处理。                                                                                                                                                     |
| key_type           | string | 否                                |  "var" | ["var", "var_combination"] | `key` 的类型。                                                                                                                                                                                                            |
| key                | string | 是                                |        |                            | 用来做请求计数的依据。如果 `key_type` 为 `"var"`，那么 `key` 会被当作变量名称，如 `remote_addr` 和 `consumer_name`；如果 `key_type` 为 `"var_combination"`，那么 `key` 会当作变量组合，如 `$remote_addr $consumer_name`；如果 `key` 的值为空，`$remote_addr` 会被作为默认 `key`。 |
| rejected_code      | string  | 否                                | 503    | [200,...,599]              | 当请求数超过 `conn` + `burst` 阈值时，返回的 HTTP 状态码。                                                                                                                                                                             |
| rejected_msg       | string | 否                                |        | 非空                       | 当请求数超过 `conn` + `burst` 阈值时，返回的信息。                                                                                                                                                                                    |
| allow_degradation  | boolean | 否                                | false  |                            | 当设置为 `true` 时，启用插件降级并自动允许请求继续。                                                                                                                                                                                        |
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

以下示例展示了如何在指定路由上启用 `limit-conn` 插件，并设置 `key_type` 为 `"var"`：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
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

你也可以设置 `key_type` 为 `"var_combination"`：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "rejected_code": 503,
            "key_type": "var_combination",
            "key": "$consumer_name $remote_addr"
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

## 测试插件

按上述配置启用插件后，在这条路由资源上，APISIX 将只允许一个连接；当有更多连接进入时，APISIX 会直接返回 `503` HTTP 状态码，拒绝连接。

```shell
curl -i http://127.0.0.1:9080/index.html?sleep=20 &

curl -i http://127.0.0.1:9080/index.html?sleep=20
```

```shell
<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
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

## 应用场景示例

### 限制 WebSocket 连接的并发数

Apache APISIX 支持 WebSocket 代理，我们可以使用 `limit-conn` 插件限制 WebSocket 连接的并发数。

1. 创建路由并启用 WebSocket 代理和 `limit-conn` 插件。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
    {
        "uri": "/ws",
        "enable_websocket": true,
        "plugins": {
            "limit-conn": {
                "conn": 1,
                "burst": 0,
                "default_conn_delay": 0.1,
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

    上述路由在 `/ws` 上开启了 WebSocket 代理，并限制了 WebSocket 连接并发数为 `1`。

    当 WebSocket 连接并发数超过 `1` 时，APISIX 将会拒绝请求，并返回 HTTP 状态码 `503`。

2. 发起 WebSocket 请求，返回 `101` HTTP 状态码表示连接建立成功。

    ```shell
    curl --include \
        --no-buffer \
        --header "Connection: Upgrade" \
        --header "Upgrade: websocket" \
        --header "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" \
        --header "Sec-WebSocket-Version: 13" \
        --http1.1 \
        http://127.0.0.1:9080/ws
    ```

    ```shell
    HTTP/1.1 101 Switching Protocols
    ```

3. 在另一个终端中再次发起 WebSocket 请求，返回 `503` HTTP 状态码表示请求将被拒绝。

    ```shell
    HTTP/1.1 503 Service Temporarily Unavailable
    ···
    <html>
    <head><title>503 Service Temporarily Unavailable</title></head>
    <body>
    <center><h1>503 Service Temporarily Unavailable</h1></center>
    <hr><center>openresty</center>
    </body>
    </html>
    ```
