---
title: graphql-proxy-cache
keywords:
  - Apache APISIX
  - API 网关
  - GraphQL
  - Proxy Cache
description: graphql-proxy-cache 插件缓存 GraphQL 查询的响应，支持磁盘和内存两种缓存策略，对包含 mutation 操作的请求自动绕过缓存。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/graphql-proxy-cache" />
</head>

## 描述

`graphql-proxy-cache` 插件为 GraphQL 查询响应提供缓存能力，支持磁盘和内存两种缓存策略，适用于 `GET` 和 `POST` 请求。

缓存键由插件配置版本、路由/服务/Host 标识符以及 GraphQL 请求体共同生成：

```
key = md5(conf_version + host + route_id + service_id + identity + body)
```

包含 `mutation` 操作的请求永远不会被缓存，始终直接透传到上游。

本插件复用 [`proxy-cache`](./proxy-cache.md) 插件的缓存基础设施。启用本插件前，需要先在 `config.yaml` 中配置缓存区域。

## 属性

| 名称               | 类型    | 必选项 | 默认值         | 有效值                 | 描述                                                                                                                                                                                                                     |
|--------------------|---------|--------|----------------|------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| cache_strategy     | string  | 否     | disk           | ["disk", "memory"]     | 缓存策略。`disk` 使用 NGINX 原生 `proxy_cache` 将响应缓存到磁盘；`memory` 使用共享内存字典缓存响应。                                                                                                                     |
| cache_zone         | string  | 否     | disk_cache_one |                        | 使用的缓存区域，值必须与[静态配置](#静态配置)中定义的某个区域名称一致。使用磁盘策略时应指定磁盘缓存区域，使用内存策略时应指定内存缓存区域。                                                                              |
| cache_ttl          | integer | 否     | 300            | >= 1                   | 内存策略的缓存生存时间（TTL），单位为秒。对于磁盘策略，TTL 由上游响应的 `Expires` 或 `Cache-Control` 头控制；若两者均不存在，则使用 `config.yaml` 中配置的 `cache_ttl`。                                                  |
| consumer_isolation | boolean | 否     | true           |                        | 为 `true` 时，按已认证身份对缓存进行分区。当请求解析为 APISIX 消费者（`ctx.consumer_name`）或携带 remote user（`ctx.var.remote_user`）时，身份会作为前缀加入有效缓存键，使每个消费者拥有独立的缓存命名空间。若希望不同消费者共享缓存，可设置为 `false`。 |
| cache_set_cookie   | boolean | 否     | false          |                        | 为 `true` 时，缓存包含 `Set-Cookie` 响应头的响应。仅对内存策略有效——磁盘策略由 NGINX 原生处理，始终不缓存带 `Set-Cookie` 的响应。仅当上游的 `Set-Cookie` 与具体用户无关时才启用。                                       |

## 静态配置

`graphql-proxy-cache` 插件复用 `config.yaml` 中定义的 `proxy_cache` 缓存区域。启用本插件前，需要至少配置一个缓存区域：

```yaml title="config.yaml"
apisix:
  proxy_cache:
    cache_ttl: 10s   # 磁盘缓存时若 Expires/Cache-Control 均不存在时使用的默认 TTL
    zones:
      - name: disk_cache_one
        memory_size: 50m
        disk_size: 1G
        disk_path: /tmp/disk_cache_one
        cache_levels: 1:2
      - name: memory_cache
        memory_size: 50m
```

修改后重新加载 APISIX 以使配置生效。

## 示例

以下示例演示了如何为不同场景配置 `graphql-proxy-cache`。

:::note

您可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 缓存 GraphQL 查询

以下示例演示如何在路由上启用 `graphql-proxy-cache`，使用默认的磁盘缓存策略：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "plugins": {
    "graphql-proxy-cache": {}
  },
  "upstream": {
    "nodes": {
      "127.0.0.1:8080": 1
    },
    "type": "roundrobin"
  },
  "uri": "/graphql"
}'
```

发送 GraphQL `POST` 请求：

```shell
curl http://127.0.0.1:9080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "query { persons { name } }"}'
```

首次请求会产生缓存未命中：

```text
HTTP/1.1 200 OK
Apisix-Cache-Status: MISS
APISIX-Cache-Key: <cache-key>
```

再次发送相同请求则会命中缓存：

```text
HTTP/1.1 200 OK
Apisix-Cache-Status: HIT
APISIX-Cache-Key: <cache-key>
```

### 对 Mutation 操作绕过缓存

`graphql-proxy-cache` 对包含 `mutation` 操作的 GraphQL 请求自动绕过缓存：

```shell
curl http://127.0.0.1:9080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { addPerson(name: \"Alice\") { id } }"}'
```

响应中包含 `Apisix-Cache-Status: BYPASS`，请求直接转发到上游：

```text
HTTP/1.1 200 OK
Apisix-Cache-Status: BYPASS
```

### 使用内存缓存

以下示例启用内存缓存策略，TTL 设置为 60 秒：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "plugins": {
    "graphql-proxy-cache": {
      "cache_strategy": "memory",
      "cache_zone": "memory_cache",
      "cache_ttl": 60
    }
  },
  "upstream": {
    "nodes": {
      "127.0.0.1:8080": 1
    },
    "type": "roundrobin"
  },
  "uri": "/graphql"
}'
```

### 清除缓存

本插件提供 `PURGE` 接口用于缓存失效：

```
PURGE /apisix/plugin/graphql-proxy-cache/:strategy/:route_id/:cache_key
```

其中：

- `:strategy` — `disk` 或 `memory`
- `:route_id` — 路由 ID
- `:cache_key` — 响应头 `APISIX-Cache-Key` 返回的值

首先使用 [`public-api`](./public-api.md) 插件创建一个路由来暴露清除接口：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/graphql-cache-purge \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "plugins": {
    "public-api": {}
  },
  "uri": "/apisix/plugin/graphql-proxy-cache/*"
}'
```

然后使用之前响应中的缓存键发送清除请求：

```shell
curl http://127.0.0.1:9080/apisix/plugin/graphql-proxy-cache/disk/1/<cache-key> \
  -X PURGE
```

清除成功返回 HTTP `200`，缓存条目不存在则返回 HTTP `404`。

## 禁用插件

从路由配置中移除 `graphql-proxy-cache` 插件即可禁用：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/graphql",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:8080": 1
    }
  }
}'
```
