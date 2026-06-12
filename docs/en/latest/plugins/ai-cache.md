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

The `ai-cache` Plugin caches responses from LLM services and serves them directly when an identical request arrives again, reducing upstream token cost and response latency. It is used together with the [`ai-proxy`](./ai-proxy.md) Plugin.

The Plugin computes a SHA-256 cache key from the request and looks it up in Redis before the request is forwarded upstream. On a **hit**, the cached response is returned directly and the upstream is never contacted. On a **miss**, the request is proxied normally and a successful JSON response is written to the cache for subsequent requests.

This release implements an **exact-match cache** for the `openai-chat` protocol. All `openai-chat`-compatible providers (for example Azure OpenAI, DeepSeek, OpenRouter, Together, vLLM, Ollama) are cached transparently because they share the protocol.

### Cache key

The cache key is a SHA-256 over the **entire request body as received from the client**: every field that can change the completion is hashed, so a parameter the Plugin has never heard of still scopes the key and can never silently cross-cache. `temperature` and `top_p` are quantised to milli-units so float-parse noise (`0.2` vs `0.2000001`) does not shatter the cache. The only excluded body field is `stream`, because streaming requests are never cached.

The key is additionally scoped by the **matched configuration's identity and version** (the route/service/plugin configuration id and its modification index). Any configuration change — including an in-place edit to an `ai-proxy` `options.model` override — changes the version and makes previously cached entries unreachable, so a configuration edit can never serve a stale response cached under the old configuration.

:::note

Because the key is derived from the request as received (not from the request after per-instance overrides are applied), routes using [`ai-proxy-multi`](./ai-proxy-multi.md) — where different instances may apply different overrides to the same client request — **bypass caching entirely** in this release. Multi-instance caching semantics are planned as a follow-up.

:::

## Attributes

| Name                       | Type            | Required                              | Default | Valid values         | Description                                                                                          |
|----------------------------|-----------------|---------------------------------------|---------|----------------------|------------------------------------------------------------------------------------------------------|
| exact.ttl                  | integer         | False                                 | 3600    | 1 to 2592000         | Time-to-live in seconds for a cached response.                                                       |
| policy                     | string          | True                                  | redis   | redis                | Backend used to store cached responses.                                                              |
| redis_host                 | string          | True when `policy` is `redis`         |         |                      | Address of the Redis node.                                                                           |
| redis_port                 | integer         | False                                 | 6379    | greater than 0       | Port of the Redis node.                                                                              |
| redis_username             | string          | False                                 |         |                      | Username for Redis authentication (Redis ACL).                                                       |
| redis_password             | string          | False                                 |         |                      | Password for Redis authentication.                                                                   |
| redis_database             | integer         | False                                 | 0       | greater than or equal to 0 | Redis database to use.                                                                         |
| redis_timeout              | integer         | False                                 | 1000    | greater than 0       | Redis connection/read/write timeout in milliseconds.                                                 |
| redis_ssl                  | boolean         | False                                 | false   |                      | If true, use SSL to connect to the Redis node.                                                       |
| redis_ssl_verify           | boolean         | False                                 | false   |                      | If true, verify the Redis node SSL certificate.                                                      |
| redis_keepalive_timeout    | integer         | False                                 | 10000   | greater than or equal to 1000 | Idle time in milliseconds before a pooled Redis connection is closed.                       |
| redis_keepalive_pool       | integer         | False                                 | 100     | greater than 0       | Maximum number of connections in the Redis connection pool.                                          |

## Response headers

| Header             | Values                       | Description                                              |
|--------------------|------------------------------|----------------------------------------------------------|
| X-AI-Cache-Status  | `HIT`, `MISS`, `SKIP-STREAM` | Whether the response was served from cache, fetched from upstream, or skipped because it was a streaming request. The header is absent when caching is bypassed (for example on `ai-proxy-multi` routes). |

## What is not cached

The Plugin never caches:

- **Streaming requests** (`stream: true`) — these are passed through and marked `X-AI-Cache-Status: SKIP-STREAM`.
- **Requests on `ai-proxy-multi` routes** — bypassed in this release (see the note above).
- **Non-2xx responses.**
- **Non-JSON response bodies.**
- **Responses larger than 1 MiB.**

The Plugin is **fail-open**: if Redis is unreachable or returns a corrupt entry, the request is treated as a miss and served from the upstream — `ai-cache` never turns a reachable upstream request into a `5xx`.

## Interaction with other plugins

- A cache **hit** is returned from the access phase, so it is still subject to plugins that run earlier, such as authentication, [`ai-rate-limiting`](./ai-rate-limiting.md), and request-side content moderation.
- A cache **hit** does not contact the upstream, so response-side processing that normally runs on proxied responses (for example response content moderation, or `ai-proxy` token accounting) does not run for hits. Avoid combining `ai-cache` with response-moderation plugins until hit-time re-validation is available.
- The cached entry stores the response bytes exactly as the client received them, so replayed responses carry the original `id`, `created`, and `model` values.

## Example usage

First, ensure Redis is running and reachable from APISIX.

Create a Route with `ai-proxy` and `ai-cache`. The example below caches `openai-chat` completions for one hour in a single Redis node:

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
      "ai-proxy": {
        "provider": "openai",
        "auth": { "header": { "Authorization": "Bearer '"$OPENAI_API_KEY"'" } },
        "options": { "model": "gpt-4o" }
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
