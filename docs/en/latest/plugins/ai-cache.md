---
title: ai-cache
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-cache
  - AI
  - LLM
description: The ai-cache Plugin caches LLM responses and serves them on identical requests, reducing upstream cost and latency.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-cache" />
</head>

## Description

The `ai-cache` Plugin caches responses from LLM services and serves them directly when an identical request arrives again, reducing upstream token cost and response latency. It is used together with the [`ai-proxy`](./ai-proxy.md) or [`ai-proxy-multi`](./ai-proxy-multi.md) Plugin.

The Plugin computes a SHA-256 cache key from the request and looks it up in Redis before the request is forwarded upstream. On a **hit**, the cached response is returned directly and the upstream is never contacted. On a **miss**, the request is proxied normally and a successful JSON response is written to the cache for subsequent requests.

This release implements an **exact-match cache** for the `openai-chat` protocol. All `openai-chat`-compatible providers (for example Azure OpenAI, DeepSeek, OpenRouter, Together, vLLM, Ollama) are cached transparently because they share the protocol.

The cache key is a SHA-256 over the **entire request body** (every field that can change the completion is hashed, so a parameter the Plugin has never heard of still scopes the key and can never silently cross-cache), with `temperature` and `top_p` quantised to milli-units so float-parse noise does not shatter the cache. A small set of fields that do not affect the completion is excluded — `stream` (streaming is never cached), and the caller/bookkeeping fields `user`, `stream_options`, `store`, and `metadata` — so semantically identical requests from different callers share one entry. The key is additionally scoped by the **picked upstream instance**, the **protocol**, and the **route**, because APISIX resolves the upstream per route: the same body on two routes may target different upstreams and must not collide.

:::note

The cache key is derived from the **effective** request — that is, the request after `ai-proxy`/`ai-proxy-multi` instance overrides (such as an `options.model` override) have been applied. Two requests that differ only in an operator-applied override therefore resolve to different cache keys, and an override cannot cause cross-caching between distinct upstream requests.

:::

## Attributes

| Name                       | Type            | Required                              | Default | Valid values         | Description                                                                                          |
|----------------------------|-----------------|---------------------------------------|---------|----------------------|------------------------------------------------------------------------------------------------------|
| exact.ttl                  | integer         | False                                 | 3600    | 1 to 2592000         | Time-to-live in seconds for a cached response.                                                       |
| policy                     | string          | True                                  | redis   | redis, redis-cluster | Backend used to store cached responses.                                                              |
| redis_host                 | string          | True when `policy` is `redis`         |         |                      | Address of the Redis node.                                                                           |
| redis_port                 | integer         | False                                 | 6379    | greater than 0       | Port of the Redis node.                                                                              |
| redis_username             | string          | False                                 |         |                      | Username for Redis authentication (Redis ACL), used when `policy` is `redis`.                        |
| redis_password             | string          | False                                 |         |                      | Password for Redis authentication.                                                                   |
| redis_database             | integer         | False                                 | 0       | greater than or equal to 0 | Redis database to use when `policy` is `redis`.                                                |
| redis_timeout              | integer         | False                                 | 1000    | greater than 0       | Redis connection/read/write timeout in milliseconds.                                                 |
| redis_ssl                  | boolean         | False                                 | false   |                      | If true, use SSL to connect to the Redis node, used when `policy` is `redis`.                        |
| redis_ssl_verify           | boolean         | False                                 | false   |                      | If true, verify the Redis node SSL certificate, used when `policy` is `redis`.                       |
| redis_keepalive_timeout    | integer         | False                                 | 10000   | greater than or equal to 1000 | Idle time in milliseconds before a pooled Redis connection is closed.                       |
| redis_keepalive_pool       | integer         | False                                 | 100     | greater than 0       | Maximum number of connections in the Redis connection pool.                                          |
| redis_cluster_nodes        | array[string]   | True when `policy` is `redis-cluster` |         |                      | List of Redis cluster node addresses, used when `policy` is `redis-cluster`.                         |
| redis_cluster_name         | string          | True when `policy` is `redis-cluster` |         |                      | Name of the Redis cluster, used when `policy` is `redis-cluster`.                                    |
| redis_cluster_ssl          | boolean         | False                                 | false   |                      | If true, use SSL to connect to the Redis cluster.                                                    |
| redis_cluster_ssl_verify   | boolean         | False                                 | false   |                      | If true, verify the Redis cluster SSL certificate.                                                   |

## Response headers

| Header             | Values                       | Description                                              |
|--------------------|------------------------------|----------------------------------------------------------|
| X-AI-Cache-Status  | `HIT`, `MISS`, `SKIP-STREAM` | Whether the response was served from cache, fetched from upstream, or skipped because it was a streaming request. |

## What is not cached

The Plugin never caches:

- **Streaming requests** (`stream: true`) — these are passed through and marked `X-AI-Cache-Status: SKIP-STREAM`.
- **Non-2xx responses.**
- **Non-JSON response bodies.**
- **Responses larger than 1 MiB.**

The Plugin is **fail-open**: if Redis is unreachable or returns a corrupt entry, the request is treated as a miss and served from the upstream — `ai-cache` never turns a reachable upstream request into a `5xx`.

## Example usage

First, ensure Redis is running and reachable from APISIX.

Create a Route with `ai-proxy-multi` (or `ai-proxy`) and `ai-cache`. The example below caches `openai-chat` completions for one hour in a single Redis node:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/chat",
    "plugins": {
      "ai-cache": {
        "exact": { "ttl": 3600 },
        "policy": "redis",
        "redis_host": "127.0.0.1"
      },
      "ai-proxy-multi": {
        "instances": [
          {
            "name": "openai",
            "provider": "openai",
            "weight": 1,
            "auth": { "header": { "Authorization": "Bearer '"$OPENAI_API_KEY"'" } },
            "options": { "model": "gpt-4o" }
          }
        ]
      }
    }
  }'
```

Send the same request twice:

```shell
curl "http://127.0.0.1:9080/chat" -i -X POST \
  -H "Content-Type: application/json" \
  -d '{ "messages": [ { "role": "user", "content": "What is APISIX?" } ] }'
```

The first response carries `X-AI-Cache-Status: MISS` and is fetched from the LLM. The second identical request returns `X-AI-Cache-Status: HIT` and is served from Redis without contacting the upstream.
