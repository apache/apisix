---
title: graphql-limit-count
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - graphql-limit-count
  - 限流
  - GraphQL
description: graphql-limit-count 插件使用固定窗口算法，基于 GraphQL 查询 AST 深度对请求速率进行限制，采用与 limit-count 插件相同的计数机制。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/graphql-limit-count" />
</head>

## 描述

`graphql-limit-count` 插件使用固定窗口算法对 GraphQL 请求进行速率限制。与每个请求消耗固定计数 1 的 [limit-count](./limit-count.md) 不同，本插件以 **GraphQL 查询 AST 的深度**作为每次请求的消耗代价，对嵌套层级更深、处理代价更高的查询施加更严格的限制。

仅支持 `POST` 方法。插件支持两种内容类型：

- `application/json`：请求体必须包含 `query` 字段，值为 GraphQL 查询字符串。
- `application/graphql`：请求体为以 `query` 开头的原始 GraphQL 查询。

响应中可能包含以下限流相关的响应头：

- `X-RateLimit-Limit`：总配额
- `X-RateLimit-Remaining`：剩余配额
- `X-RateLimit-Reset`：计数器重置的剩余秒数

## 属性

本插件与 [limit-count](./limit-count.md) 插件共享相同的 Schema，完整属性参考请见该页面。关键属性如下所示。

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| count | integer or string | 否 | | > 0 | 时间窗口内允许的最大累计查询 AST 深度。当未配置 `rules` 时必填。 |
| time_window | integer or string | 否 | | > 0 | 限流时间窗口（秒）。当未配置 `rules` 时必填。 |
| key_type | string | 否 | var | ["var", "var_combination", "constant"] | key 的类型。`var` 将 `key` 解释为 NGINX 变量；`var_combination` 将多个变量组合；`constant` 将 `key` 作为固定值。 |
| key | string | 否 | remote_addr | | 用于计数的 key。 |
| rejected_code | integer | 否 | 503 | [200,...,599] | 请求超出配额时返回的 HTTP 状态码。 |
| rejected_msg | string | 否 | | 非空 | 请求被拒绝时返回的响应体。 |
| policy | string | 否 | local | ["local", "redis", "redis-cluster"] | 限流计数器的存储策略。`local` 使用当前 APISIX 节点内存；`redis` 和 `redis-cluster` 在多个实例间共享计数器。 |
| allow_degradation | boolean | 否 | false | | 为 true 时，插件或依赖不可用时 APISIX 仍继续处理请求。 |
| show_limit_quota_header | boolean | 否 | true | | 为 true 时，在响应中包含 `X-RateLimit-Limit` 和 `X-RateLimit-Remaining` 响应头。 |
| group | string | 否 | | 非空 | Group ID，用于在多个路由之间共享同一个限流计数器。 |
| redis_host | string | 否 | | | Redis 节点地址。`policy` 为 `redis` 时必填。 |
| redis_port | integer | 否 | 6379 | [1,...] | Redis 节点端口。`policy` 为 `redis` 时使用。 |
| redis_username | string | 否 | | | Redis ACL 认证用户名。`policy` 为 `redis` 时使用。 |
| redis_password | string | 否 | | | Redis 节点密码。`policy` 为 `redis` 或 `redis-cluster` 时使用。 |
| redis_ssl | boolean | 否 | false | | 为 true 时使用 SSL 连接 Redis。`policy` 为 `redis` 时使用。 |
| redis_ssl_verify | boolean | 否 | false | | 为 true 时验证 Redis 服务端 SSL 证书。`policy` 为 `redis` 时使用。 |
| redis_database | integer | 否 | 0 | >= 0 | Redis 数据库编号。`policy` 为 `redis` 时使用。 |
| redis_timeout | integer | 否 | 1000 | [1,...] | Redis 超时时间（毫秒）。`policy` 为 `redis` 或 `redis-cluster` 时使用。 |
| redis_cluster_nodes | array[string] | 否 | | | Redis 集群节点地址列表。`policy` 为 `redis-cluster` 时必填。 |
| redis_cluster_name | string | 否 | | | Redis 集群名称。`policy` 为 `redis-cluster` 时必填。 |
| redis_cluster_ssl | boolean | 否 | false | | 为 true 时使用 SSL 连接 Redis 集群。`policy` 为 `redis-cluster` 时使用。 |
| redis_cluster_ssl_verify | boolean | 否 | false | | 为 true 时验证 Redis 集群服务端 SSL 证书。`policy` 为 `redis-cluster` 时使用。 |

## 示例

以下示例演示了如何在不同场景中配置 `graphql-limit-count` 插件。

:::note

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 按客户端 IP 对查询深度限流

以下示例演示如何按客户端 IP 地址对 GraphQL 请求按累计查询 AST 深度进行限流。浅层查询（如 `{ foo { bar } }`，深度 2）消耗 2 个配额，深层嵌套查询（如 `{ foo { bar { baz { id } } } }`，深度 4）消耗 4 个配额。

创建一个路由，配置 `graphql-limit-count`，允许每个客户端 IP 每分钟累计查询深度为 10：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "graphql-limit-count-route",
    "uri": "/graphql",
    "plugins": {
      "graphql-limit-count": {
        "count": 10,
        "time_window": 60,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "local"
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

发送一个深度为 4 的 GraphQL 查询：

```shell
curl -i "http://127.0.0.1:9080/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { foo { bar { baz { id } } } }"}'
```

您将收到 `HTTP/1.1 200 OK` 响应，响应头如下：

```text
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 6
```

深度 4 的查询消耗了 10 个配额中的 4 个。时间窗口内配额耗尽后，将收到 `HTTP/1.1 429 Too Many Requests` 响应。

### 使用 Redis 在多个 APISIX 节点间共享配额

以下示例演示如何使用 Redis 后端计数器，在多个 APISIX 实例之间共享限流配额。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "graphql-limit-count-route",
    "uri": "/graphql",
    "plugins": {
      "graphql-limit-count": {
        "count": 100,
        "time_window": 60,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "redis",
        "redis_host": "127.0.0.1",
        "redis_port": 6379
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

发送请求验证：

```shell
curl -i "http://127.0.0.1:9080/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { foo { bar } }"}'
```

您将收到 `HTTP/1.1 200 OK` 响应。所有连接到同一 Redis 实例的 APISIX 节点将共享同一个限流计数器。
