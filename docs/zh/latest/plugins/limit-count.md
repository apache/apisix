---
title: limit-count
keywords:
  - APISIX
  - API 网关
  - Limit Count
  - 速率限制
description: 本文介绍了 Apache APISIX limit-count 插件的相关操作，你可以使用此插件限制客户端在指定的时间范围内对服务的总请求数。
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

`limit-count` 插件使用固定时间窗口算法，主要用于限制**单个客户端**在指定的时间范围内对服务的总请求数，并且会在 HTTP 响应头中返回剩余可以请求的个数。该插件原理与 [GitHub API 的速率限制](https://docs.github.com/en/rest/reference/rate-limit)类似。

## 属性

| 名称                | 类型    | 必选项      | 默认值        | 有效值                                   | 描述                                                                                                                                                                                                                                 |
| ------------------- | ------- | ---------- | ------------- | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| count               | integer | 是        |                | count > 0                               | 每个客户端在指定时间窗口内的总请求数量阈值。|
| time_window         | integer | 是        |                | time_window > 0                         | 时间窗口的大小（以秒为单位）。超过该属性定义的时间，则会重新开始计数。|
| key_type            | string | 否         |  "var"         | ["var", "var_combination", "constant"] | key 的类型。 |
| key                 | string  | 否        |  "remote_addr" |                                        | 用来做请求计数的依据。如果 `key_type` 为 `constant`，那么 key 会被当作常量；如果 `key_type` 为 `var`，那么 key 会被当作变量；如果 `key_type` 为 `var_combination`，那么 key 会被当作变量组合，如 `$remote_addr $consumer_name`，插件会同时受 `$remote_addr` 和 `$consumer_name` 两个变量的约束；如果 `key` 的值为空，`$remote_addr` 会被作为默认 `key`。 |
| rejected_code       | integer | 否        | 503            | [200,...,599]                          | 当请求超过阈值被拒绝时，返回的 HTTP 状态码。|
| rejected_msg        | string  | 否        |                | 非空                                   | 当请求超过阈值被拒绝时，返回的响应体。|
| policy              | string  | 否        | "local"        | ["local", "redis", "redis-cluster"]    | 用于检索和增加限制计数的策略。当设置为 `local` 时，计数器被以内存方式保存在节点本地；当设置为 `redis` 时，计数器保存在 Redis 服务节点上，从而可以跨节点共享结果，通常用它来完成全局限速；当设置为 `redis-cluster` 时，使用 Redis 集群而不是单个实例。|
| allow_degradation   | boolean | 否        | false          |                                         | 当插件功能临时不可用时（例如 Redis 超时），当设置为 `true` 时，则表示可以允许插件降级并进行继续请求的操作。 |
| show_limit_quota_header | boolean | 否    | true          |                                          | 当设置为 `true` 时，在响应头中显示 `X-RateLimit-Limit`（限制的总请求数）和 `X-RateLimit-Remaining`（剩余还可以发送的请求数）字段。 |
| group               | string | 否         |               | 非空                                    | 配置相同 group 的路由将共享相同的限流计数器。请勿使用先前使用过的值进行配置，插件将报错。 |
| redis_host          | string  | 否        |               |                                         | 当使用 `redis` 限速策略时，Redis 服务节点的地址。**当 `policy` 属性设置为 `redis` 时必选。**|
| redis_port          | integer | 否        | 6379          | [1,...]                                 | 当使用 `redis` 限速策略时，Redis 服务节点的端口。|
| redis_username      | string  | 否        |               |                                         | 若使用 Redis ACL 进行身份验证（适用于 Redis 版本 >=6.0），则需要提供 Redis 用户名。若使用 Redis legacy 方式 `requirepass` 进行身份验证，则只需将密码配置在 `redis_password`。当 `policy` 设置为 `redis` 时使用。|
| redis_password      | string  | 否        |               |                                         | 当使用 `redis`  或者 `redis-cluster`  限速策略时，Redis 服务节点的密码。|
| redis_ssl           | boolean | 否        | false         |                                         | 当使用 `redis` 限速策略时，如果设置为 true，则使用 SSL 连接到 `redis` |
| redis_ssl_verify    | boolean | 否        | false         |                                         | 当使用 `redis` 限速策略时，如果设置为 true，则验证服务器 SSL 证书的有效性，具体请参考 [tcpsock:sslhandshake](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake). |
| redis_database      | integer | 否        | 0             | redis_database >= 0                     | 当使用 `redis` 限速策略时，Redis 服务节点中使用的 `database`，并且只针对非 Redis 集群模式（单实例模式或者提供单入口的 Redis 公有云服务）生效。|
| redis_timeout       | integer | 否        | 1000          | [1,...]                                 | 当 `policy` 设置为 `redis` 或 `redis-cluster` 时，Redis 服务节点的超时时间（以毫秒为单位）。|
| redis_cluster_nodes | array   | 否        |               |                                         | 当使用 `redis-cluster` 限速策略时，Redis 集群服务节点的地址列表（至少需要两个地址）。**当 `policy` 属性设置为 `redis-cluster` 时必选。**|
| redis_cluster_name  | string  | 否        |               |                                         | 当使用 `redis-cluster` 限速策略时，Redis 集群服务节点的名称。**当 `policy` 设置为 `redis-cluster` 时必选。**|
| redis_cluster_ssl  | boolean  | 否        |     false    |                                         | 当使用 `redis-cluster` 限速策略时，如果设置为 true，则使用 SSL 连接到 `redis-cluster` |
| redis_cluster_ssl_verify  | boolean  | 否        |     false        |                                         | 当使用 `redis-cluster` 限速策略时，如果设置为 true，则验证服务器 SSL 证书的有效性 |

## 启用插件

以下示例展示了如何在指定路由上启用 `limit-count` 插件，并设置 `key_type` 为 `"var"`：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
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
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
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
}'
```

支持在多个路由间共享同一个限流计数器。首先通过以下命令创建一个服务：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/services/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "limit-count": {
            "count": 1,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "group": "services_1#1640140620"
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

然后为路由配置 `service_id` 为 `1` ，不同路由将共享同一个计数器：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "service_id": "1",
    "uri": "/hello"
}'
```

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/2 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "service_id": "1",
    "uri": "/hello2"
}'
```

通过将 `key_type` 设置为 `"constant"`，你也可以在所有请求间共享同一个限流计数器：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/services/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "limit-count": {
            "count": 1,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "key_type": "constant",
            "group": "services_1#1640140621"
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

以上配置表示：当多个路由中 `limit-count` 插件的 `group` 属性均配置为 `services_1#1640140620` 时，访问这些路由的请求将会共享同一个计数器，即使这些请求来自于不同的 IP 地址。

:::note 注意

同一个 `group` 里面的 `limit-count` 的配置必须保持一致。如果修改配置，需要同时更新对应的 `group` 的值。

:::

如果你需要一个集群级别的流量控制，我们可以借助 Redis 服务器来完成。不同的 APISIX 节点之间将共享流量限速结果，实现集群流量限速。

以下示例展示了如何在指定路由上启用 `redis` 策略：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "policy": "redis",
            "redis_host": "127.0.0.1",
            "redis_port": 6379,
            "redis_password": "password",
            "redis_database": 1,
            "redis_timeout": 1001
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

你也可以使用 `redis-cluster` 策略：

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "policy": "redis-cluster",
            "redis_cluster_nodes": [
                "127.0.0.1:5000",
                "127.0.0.1:5001"
            ],
            "redis_password": "password",
            "redis_cluster_name": "redis-cluster-1"
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

在上文提到的配置中，其限制了 60 秒内请求只能访问 2 次，可通过如下 `curl` 命令测试请求访问：

```shell
curl -i http://127.0.0.1:9080/index.html
```

在执行测试命令的前两次都会正常访问。其中响应头中包含了 `X-RateLimit-Limit` 和 `X-RateLimit-Remaining` 和 `X-RateLimit-Reset` 字段，分别代表限制的总请求数和剩余还可以发送的请求数以及计数器剩余重置的秒数：

```shell
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 58
Server: APISIX web server
```

当第三次进行测试访问时，会收到包含 `503` HTTP 状态码的响应头，目前在拒绝的情况下，也会返回相关的头，表示插件生效：

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 58
Server: APISIX web server
```

如果你设置了属性 `rejected_msg` 的值为 `"Requests are too frequent, please try again later."`，当第三次访问时，就会收到如下带有 `error_msg` 返回信息的响应体：

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 58
Server: APISIX web server

{"error_msg":"Requests are too frequent, please try again later."}
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
