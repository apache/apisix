---
title: limit-conn
keywords:
  - APISIX
  - API 网关
  - Limit Connection
description: limit-conn 插件通过管理并发连接来限制请求速率。超过阈值的请求可能会被延迟或拒绝，以确保 API 使用受控并防止过载。
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/limit-conn" />
</head>

## 描述

`limit-conn` 插件通过并发连接数来限制请求速率。超过阈值的请求将根据配置被延迟或拒绝，从而确保可控的资源使用并防止过载。

## 属性

| 名称        | 类型    | 必选项    | 默认值 | 有效值                      | 描述              |
|------------|---------|----------|-------|----------------------------|------------------|
| conn | integer | 否 | | > 0 | 允许的最大并发请求数。超过配置的限制且低于`conn + burst`的请求将被延迟。如果未配置 `rules`,则为必填项。|
| burst | integer | 否 | | >= 0 | 每秒允许延迟的过多并发请求数。超过限制的请求将被立即拒绝。如果未配置 `rules`,则为必填项。|
| default_conn_delay | number | 是 | | > 0 | 允许超过`conn + burst`的并发请求的处理延迟（秒），可根据`only_use_default_delay`设置动态调整。|
| only_use_default_delay | boolean | 否 | false | | 如果为 false，则根据请求超出`conn`限制的程度按比例延迟请求。拥塞越严重，延迟就越大。例如，当 `conn` 为 `5`、`burst` 为 `3` 且 `default_conn_delay` 为 `1` 时，6 个并发请求将导致 1 秒的延迟，7 个请求将导致 2 秒的延迟，8 个请求将导致 3 秒的延迟，依此类推，直到达到 `conn + burst` 的总限制，超过此限制的请求将被拒绝。如果为 true，则使用 `default_conn_delay` 延迟 `burst` 范围内的所有超额请求。超出 `conn + burst` 的请求将被立即拒绝。例如，当 `conn` 为 `5`、`burst` 为 `3` 且 `default_conn_delay` 为 `1` 时，6、7 或 8 个并发请求都将延迟 1 秒。|
| rules                    | array[object] | 否    |       |                   | 连接限制规则列表。每个规则是一个包含 `conn`、`burst` 和 `key` 的对象。如果配置了此项，则优先于 `conn`、`burst` 和 `key`。 |
| rules.conn               | integer 或 string | 是 |       | > 0 或变量表达式 | 允许的最大并发请求数。可以是静态整数或变量表达式，如 `$http_custom_conn`。 |
| rules.burst              | integer 或 string | 是 |       | >= 0 或变量表达式 | 允许延迟的过多并发请求数。可以是静态整数或变量表达式。 |
| rules.key                | string  | 是     |       |                   | 用于计数请求的键。如果配置的键不存在，则不会执行该规则。`key` 被解释为变量组合，例如：`$http_custom_a $http_custom_b`。 |
| key_type | string | 否 | var | ["var","var_combination"] | key 的类型。如果`key_type` 为 `var`，则 `key` 将被解释为变量。如果 `key_type` 为 `var_combination`，则 `key` 将被解释为变量的组合。 |
| key | string | 否 | remote_addr | | 用于计数请求的 key。如果 `key_type` 为 `var`，则 `key` 将被解释为变量。变量不需要以美元符号（`$`）为前缀。如果 `key_type` 为 `var_combination`，则 `key` 会被解释为变量的组合。所有变量都应该以美元符号 (`$`) 为前缀。例如，要配置 `key` 使用两个请求头 `custom-a` 和 `custom-b` 的组合，则 `key` 应该配置为 `$http_custom_a $http_custom_b`。如果未配置 `rules`，则为必填项。|
| key_ttl | integer | 否 | 3600 | | Redis 键的 TTL（以秒为单位）。当 `policy` 为 `redis` 或 `redis-cluster` 时使用。 |
| rejection_code | integer | 否 | 503 | [200,...,599] | 请求因超出阈值而被拒绝时返回的 HTTP 状态代码。|
| rejection_msg | string | 否 | | 非空 | 请求因超出阈值而被拒绝时返回的响应主体。|
| allow_degradation | boolean | 否 | false | | 如果为 true，则允许 APISIX 在插件或其依赖项不可用时继续处理没有插件的请求。|
| policy | string | 否 | local | ["local","re​​dis","re​​dis-cluster"] | 速率限制计数器的策略。如果是 `local`，则计数器存储在本地内存中。如果是 `redis`，则计数器存储在 Redis 实例上。如果是 `redis-cluster`，则计数器存储在 Redis 集群中。|
| redis_host | string | 否 | | | Redis 节点的地址。当 `policy` 为 `redis` 时必填。 |
| redis_port | integer | 否 | 6379 | [1,...] | 当 `policy` 为 `redis` 时，Redis 节点的端口。 |
| redis_username | string | 否 | | | 如果使用 Redis ACL，则为 Redis 的用户名。如果使用旧式身份验证方法 `requirepass`，则仅配置 `redis_password`。当 `policy` 为 `redis` 时使用。 |
| redis_password | string | 否 | | | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 节点的密码。 |
| redis_ssl | boolean | 否 | false |如果为 true，则在 `policy` 为 `redis` 时使用 SSL 连接到 Redis 集群。|
| redis_ssl_verify | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis` 时验证服务器 SSL 证书。|
| redis_database | integer | 否 | 0 | >= 0 | 当 `policy` 为 `redis` 时，Redis 中的数据库编号。|
| redis_timeout | integer | 否 | 1000 | [1,...] | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 超时值（以毫秒为单位）。 |
| redis_keepalive_timeout | integer | 否 | 10000 | ≥ 1000 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，与 `redis` 或 `redis-cluster` 的空闲连接超时时间，单位为毫秒。|
| redis_keepalive_pool | integer | 否 | 100 | ≥ 1 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，与 `redis` 或 `redis-cluster` 的连接池最大连接数。|
| redis_cluster_nodes | array[string] | 否 | | | 具有至少两个地址的 Redis 群集节点列表。当 policy 为 redis-cluster 时必填。 |
| redis_cluster_name | string | 否 | | | Redis 集群的名称。当 `policy` 为 `redis-cluster` 时必须使用。|
| redis_cluster_ssl | boolean | 否 | false | | 如果为 `true`，当 `policy` 为 `redis-cluster`时，使用 SSL 连接 Redis 集群。|
| redis_cluster_ssl_verify | boolean | 否 | false | | 如果为 `true`，当 `policy` 为 `redis-cluster` 时，验证服务器 SSL 证书。  |

## 示例

以下示例演示了如何在不同场景中配置 `limit-conn`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 通过远程地址应用速率限制

以下示例演示如何使用 `limit-conn` 通过 `remote_addr` 限制请求速率，并附带示例连接和突发阈值。

使用 `limit-conn` 插件创建路由，以允许 2 个并发请求和 1 个过多的并发请求。此外：

* 配置插件，允许超过 `conn + burst` 的并发请求有 0.1 秒的处理延迟。
* 将密钥类型设置为 `vars`，以将 `key` 解释为变量。
* 根据请求的 `remote_address` 计算速率限制计数。
* 将 `policy` 设置为 `local`，以使用内存中的本地计数器。
* 将 `rejected_code` 自定义为 `429`。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "conn": 2,
        "burst": 1,
        "default_conn_delay": 0.1,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "local",
        "rejected_code": 429
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

向路由发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

您应该会看到类似以下内容的响应，其中超过阈值的请求被拒绝：

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

### 通过远程地址和消费者名称应用速率限制

以下示例演示如何使用 `limit-conn` 通过变量组合 `remote_addr` 和 `consumer_name` 对请求进行速率限制。

创建消费者 `john`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

创建第二个消费者 `jane`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jane"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jane/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jane-key"
      }
    }
  }'
```

创建一个带有 `key-auth` 和 `limit-conn` 插件的路由，并在 `limit-conn` 插件中指定使用变量组合作为速率限制 key：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "limit-conn": {
        "conn": 2,
        "burst": 1,
        "default_conn_delay": 0.1,
        "rejected_code": 429,
        "key_type": "var_combination",
        "key": "$remote_addr $consumer_name"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

作为消费者 `john` 发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "apikey: john-key"'
```

您应该会看到类似以下内容的响应，其中超过阈值的请求被拒绝：

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

接下来立刻以消费者 `jane` 的身份发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "apikey: jane-key"'
```

您还应该看到类似以下内容的响应，其中过多的请求被拒绝：

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

### 限制 WebSocket 连接速率

以下示例演示了如何使用 `limit-conn` 插件来限制并发 WebSocket 连接的数量。

启动 [上游 WebSocket 服务器](https://hub.docker.com/r/jmalloc/echo-server)：

```shell
docker run -d \
  -p 8080:8080 \
  --name websocket-server \
  --network=apisix-quickstart-net \
  jmalloc/echo-server
```

创建到服务器 WebSocket 端点的路由，并为路由启用 WebSocket。相应地调整 WebSocket 服务器地址。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "ws-route",
  "uri": "/.ws",
  "plugins": {
    "limit-conn": {
      "conn": 2,
      "burst": 1,
      "default_conn_delay": 0.1,
      "key_type": "var",
      "key": "remote_addr",
      "rejected_code": 429
    }
  },
  "enable_websocket": true,
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "websocket-server:8080": 1
    }
  }
}'
```

安装 WebSocket 客户端，例如 [websocat](https://github.com/vi/websocat)，通过以下路由与 WebSocket 服务器建立连接：

```shell
websocat "ws://127.0.0.1:9080/.ws"
```

在终端中发送 `hello` 消息，您应该会看到 WebSocket 服务器回显相同的消息：

```text
Request served by 1cd244052136
hello
hello
```

再打开三个终端会话并运行：

```shell
websocat "ws://127.0.0.1:9080/.ws"
```

由于速率限制的影响，当您尝试与服务器建立 WebSocket 连接时，您应该会看到最后一个终端会话打印 `429 Too Many Requests`。

### 使用 Redis 服务器在 APISIX 节点之间共享配额

以下示例演示了使用 Redis 服务器对多个 APISIX 节点之间的请求进行速率限制，以便不同的 APISIX 节点共享相同的速率限制配额。

在每个 APISIX 实例上，使用以下配置创建路由。相应地调整管理 API、Redis 主机、端口、密码和数据库的地址。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "conn": 1,
        "burst": 1,
        "default_conn_delay": 0.1,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "redis",
        "redis_host": "192.168.xxx.xxx",
        "redis_port": 6379,
        "redis_password": "p@ssw0rd",
        "redis_database": 1
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

向路由发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

您应该会看到类似以下内容的响应，其中超过阈值的请求被拒绝：

```text
Response: 200
Response: 200
Response: 429
Response: 429
Response: 429
```

这表明在不同 APISIX 实例中配置的两个路由共享相同的配额。

### 使用 Redis 集群在 APISIX 节点之间共享配额

您还可以使用 Redis 集群在多个 APISIX 节点之间应用相同的配额，以便不同的 APISIX 节点共享相同的速率限制配额。

确保您的 Redis 实例在 [集群模式](https://redis.io/docs/management/scaling/#create-and-use-a-redis-cluster) 下运行。`limit-conn` 插件配置至少需要两个节点。

在每个 APISIX 实例上，使用以下配置创建一个路由。相应地调整管理 API 的地址、Redis 集群节点、密码、集群名称和 SSL 验证。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "conn": 1,
        "burst": 1,
        "default_conn_delay": 0.1,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "redis-cluster",
        "redis_cluster_nodes": [
          "192.168.xxx.xxx:6379",
          "192.168.xxx.xxx:16379"
        ],
        "redis_password": "p@ssw0rd",
        "redis_cluster_name": "redis-cluster-1",
        "redis_cluster_ssl": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

向路由发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

您应该会看到类似以下内容的响应，其中超过阈值的请求被拒绝：

```text
Response: 200
Response: 200
Response: 429
Response: 429
Response: 429
```

这表明在不同的 APISIX 实例中配置的两条路由共享相同的配额。
