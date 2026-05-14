---
title: graphql-limit-count
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - graphql-limit-count
  - 限流
  - GraphQL
description: graphql-limit-count 插件通过在指定时间窗口内累计 GraphQL 查询 AST 深度来限制请求速率，采用与 limit-count 相同的计数机制。
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

`graphql-limit-count` 插件使用固定窗口算法对 GraphQL 请求进行速率限制。与每次请求消耗固定计数 1 的 `limit-count` 不同，本插件以 **GraphQL 查询 AST 的深度**作为消耗代价，从而对嵌套层级更深、处理代价更高的查询施加更严格的限制。

仅支持 `POST` 方法。请求体必须使用 `application/json`（含 `query` 字段）或 `application/graphql` 内容类型。

响应中可能包含以下限流相关的响应头：

- `X-RateLimit-Limit`：总配额
- `X-RateLimit-Remaining`：剩余配额
- `X-RateLimit-Reset`：计数器重置的剩余秒数

## 属性

本插件与 [limit-count](./limit-count.md) 插件共享相同的 Schema，`limit-count` 的所有属性均适用。

| 名称                    | 类型              | 必填 | 默认值        | 有效值                                 | 描述                                                                                               |
| ----------------------- | ----------------- | ---- | ------------- | -------------------------------------- | -------------------------------------------------------------------------------------------------- |
| count                   | integer or string | 否   |               | > 0                                    | 时间窗口内允许的最大 GraphQL 查询深度累计值。当未配置 `rules` 时必填。                             |
| time_window             | integer or string | 否   |               | > 0                                    | 限流计数对应的时间窗口（秒）。当未配置 `rules` 时必填。                                            |
| key_type                | string            | 否   | var           | ["var","var_combination","constant"]   | key 的类型。                                                                                       |
| key                     | string            | 否   | remote_addr   |                                        | 用于计数的 key。                                                                                   |
| rejected_code           | integer           | 否   | 503           | [200,...,599]                          | 请求被拒绝时返回的 HTTP 状态码。                                                                   |
| rejected_msg            | string            | 否   |               | 非空                                   | 请求被拒绝时返回的响应体。                                                                         |
| policy                  | string            | 否   | local         | ["local","redis","redis-cluster"]      | 限流计数器的存储策略。                                                                             |
| allow_degradation       | boolean           | 否   | false         |                                        | 为 true 时，插件或依赖不可用时 APISIX 仍继续处理请求。                                            |
| show_limit_quota_header | boolean           | 否   | true          |                                        | 为 true 时，在响应中包含限流相关的响应头。                                                         |
| group                   | string            | 否   |               | 非空                                   | 用于在多个路由之间共享限流计数器的 Group ID。                                                     |
| redis_host              | string            | 否   |               |                                        | Redis 节点地址。`policy` 为 `redis` 时必填。                                                      |
| redis_port              | integer           | 否   | 6379          | [1,...]                                | `policy` 为 `redis` 时 Redis 节点的端口。                                                        |
| redis_username          | string            | 否   |               |                                        | 使用 Redis ACL 认证时的用户名。`policy` 为 `redis` 时使用。                                      |
| redis_password          | string            | 否   |               |                                        | `policy` 为 `redis` 或 `redis-cluster` 时 Redis 节点的密码。                                     |
| redis_ssl               | boolean           | 否   | false         |                                        | 为 true 时，`policy` 为 `redis` 时使用 SSL 连接 Redis。                                          |
| redis_ssl_verify        | boolean           | 否   | false         |                                        | 为 true 时，验证 `policy` 为 `redis` 时服务端的 SSL 证书。                                       |
| redis_database          | integer           | 否   | 0             | >= 0                                   | `policy` 为 `redis` 时使用的 Redis 数据库编号。                                                  |
| redis_timeout           | integer           | 否   | 1000          | [1,...]                                | `policy` 为 `redis` 或 `redis-cluster` 时的 Redis 超时时间（毫秒）。                             |
| redis_cluster_nodes     | array[string]     | 否   |               |                                        | Redis 集群节点列表。`policy` 为 `redis-cluster` 时必填。                                         |
| redis_cluster_name      | string            | 否   |               |                                        | Redis 集群名称。`policy` 为 `redis-cluster` 时必填。                                             |
| redis_cluster_ssl       | boolean           | 否   | false         |                                        | 为 true 时，`policy` 为 `redis-cluster` 时使用 SSL 连接 Redis 集群。                             |
| redis_cluster_ssl_verify| boolean           | 否   | false         |                                        | 为 true 时，验证 `policy` 为 `redis-cluster` 时服务端的 SSL 证书。                               |

## 示例

以下示例演示了如何在不同场景下配置 `graphql-limit-count` 插件。

:::note

您可以用以下命令从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 基于 GraphQL 查询深度限流（本地策略）

以下示例演示如何使用内存计数器对 GraphQL 请求按查询深度进行速率限制。

创建带有 `graphql-limit-count` 的路由：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/graphql",
  "plugins": {
    "graphql-limit-count": {
      "count": 10,
      "time_window": 60,
      "rejected_code": 429,
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

发送 GraphQL `POST` 请求：

```shell
curl -i http://127.0.0.1:9080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "query { foo { bar { baz } } }"}'
```

响应中将包含 `X-RateLimit-Remaining`，显示剩余配额。此查询的 AST 深度为 3，因此本次请求消耗 10 中的 3 个配额。

### 基于 GraphQL 查询深度限流（Redis 策略）

以下示例演示如何使用 Redis 后端计数器，在多个 APISIX 节点之间共享状态。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/graphql",
  "plugins": {
    "graphql-limit-count": {
      "count": 100,
      "time_window": 60,
      "rejected_code": 429,
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
