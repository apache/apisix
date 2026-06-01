---
title: graphql-proxy-cache
keywords:
  - Apache APISIX
  - API Gateway
  - GraphQL
  - Proxy Cache
description: The graphql-proxy-cache Plugin caches GraphQL query responses on disk or in memory, bypassing the cache for mutation operations.
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

## Description

The `graphql-proxy-cache` Plugin provides caching for GraphQL query responses. It supports both disk-based and memory-based caching strategies for `GET` and `POST` requests.

The cache key is derived from the plugin configuration version, route/service/host identifiers, and the GraphQL query body:

```
key = md5(conf_version + host + route_id + service_id + identity + body)
```

Requests containing `mutation` operations are never cached — they always bypass the cache and reach the upstream directly.

The Plugin reuses the caching infrastructure of the [`proxy-cache`](./proxy-cache.md) Plugin. Cache zones must be configured in `config.yaml` before enabling this Plugin.

## Attributes

| Name               | Type    | Required | Default        | Valid values        | Description                                                                                                                                                                                                                                                                                                  |
|--------------------|---------|----------|----------------|---------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| cache_strategy     | string  | False    | disk           | ["disk", "memory"]  | Caching strategy. Use `disk` to cache responses on disk (via NGINX's native `proxy_cache`), or `memory` to cache in a shared memory dictionary.                                                                                                                                                              |
| cache_zone         | string  | False    | disk_cache_one |                     | Cache zone to use. The value must match one of the zones defined in the [static configurations](#static-configurations). Use a disk zone with the `disk` strategy and a memory zone with the `memory` strategy.                                                                                               |
| cache_ttl          | integer | False    | 300            | >= 1                | Cache time to live (TTL) in seconds for the `memory` strategy. For the `disk` strategy, TTL is controlled by the upstream `Expires` or `Cache-Control` response headers; if neither is present, the `cache_ttl` configured in `config.yaml` is used.                                                        |
| consumer_isolation | boolean | False    | true           |                     | If `true`, partition the cache by authenticated identity. When the request resolves to an APISIX consumer (`ctx.consumer_name`) or carries a remote user (`ctx.var.remote_user`), the identity is prepended to the effective cache key so each consumer gets its own cache namespace. Set to `false` if you want different consumers to share cached responses. |
| cache_set_cookie   | boolean | False    | false          |                     | If `true`, cache responses that include a `Set-Cookie` header. Only valid for the `memory` strategy — the `disk` strategy never caches responses with `Set-Cookie` (NGINX enforces this). Enable only when the upstream's `Set-Cookie` is not user-specific.                                                  |

## Static Configurations

The `graphql-proxy-cache` Plugin reuses the `proxy_cache` zones defined in `config.yaml`. Configure at least one cache zone before enabling this Plugin:

```yaml title="config.yaml"
apisix:
  proxy_cache:
    cache_ttl: 10s   # default TTL for disk cache when Expires/Cache-Control are absent
    zones:
      - name: disk_cache_one
        memory_size: 50m
        disk_size: 1G
        disk_path: /tmp/disk_cache_one
        cache_levels: 1:2
      - name: memory_cache
        memory_size: 50m
```

Reload APISIX for changes to take effect.

## Examples

The examples below demonstrate how you can configure `graphql-proxy-cache` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save it to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Cache GraphQL Queries

The following example shows how to enable `graphql-proxy-cache` on a route with the default disk strategy:

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

Send a GraphQL `POST` request:

```shell
curl http://127.0.0.1:9080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "query { persons { name } }"}'
```

The first request results in a cache miss:

```text
HTTP/1.1 200 OK
Apisix-Cache-Status: MISS
APISIX-Cache-Key: <cache-key>
```

Sending the same request again returns a cache hit:

```text
HTTP/1.1 200 OK
Apisix-Cache-Status: HIT
APISIX-Cache-Key: <cache-key>
```

### Bypass Cache for Mutation Operations

`graphql-proxy-cache` automatically bypasses the cache for GraphQL requests containing `mutation` operations:

```shell
curl http://127.0.0.1:9080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { addPerson(name: \"Alice\") { id } }"}'
```

The response includes `Apisix-Cache-Status: BYPASS`, and the request is forwarded directly to the upstream:

```text
HTTP/1.1 200 OK
Apisix-Cache-Status: BYPASS
```

### Use In-Memory Cache

The following example enables the `memory` strategy with a 60-second TTL:

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

### Purge Cached Responses

The Plugin exposes a `PURGE` endpoint for cache invalidation:

```
PURGE /apisix/plugin/graphql-proxy-cache/:strategy/:route_id/:cache_key
```

Where:

- `:strategy` — `disk` or `memory`
- `:route_id` — the ID of the route
- `:cache_key` — the value returned in the `APISIX-Cache-Key` response header

To expose the purge endpoint, create a route using the [`public-api`](./public-api.md) Plugin:

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

Then send a purge request using the cache key from a previous response:

```shell
curl http://127.0.0.1:9080/apisix/plugin/graphql-proxy-cache/disk/1/<cache-key> \
  -X PURGE
```

A successful purge returns HTTP `200`. If the cache entry does not exist, HTTP `404` is returned.

## Disable Plugin

To disable the `graphql-proxy-cache` Plugin, remove it from the route configuration:

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
