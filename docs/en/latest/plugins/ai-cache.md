---
title: ai-cache
keywords:
  - APISIX
  - AI Gateway
  - ai-cache
  - cache
description: This document contains information about the Apache APISIX ai-cache plugin.
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

## Description

The `ai-cache` plugin caches non-streaming `openai-chat` responses in Redis,
keyed by the request fingerprint. A subsequent identical request returns the
cached response without re-invoking the upstream LLM, dropping latency and
cost.

This is the **Phase 1 / PR-1** surface: exact-match L1 cache only,
`openai-chat` protocol only, Redis backends only. Subsequent PRs add the full
cache-key whitelist, consumer/var scoping, the bypass header, and Prometheus
metrics. See [apache/apisix#13290](https://github.com/apache/apisix/issues/13290)
for the road map.

## Attributes

| Name                       | Type             | Required | Default       | Valid values             | Description                                                                          |
| -------------------------- | ---------------- | -------- | ------------- | ------------------------ | ------------------------------------------------------------------------------------ |
| exact                      | object           | False    | `{ttl: 3600}` |                          | Exact-match L1 cache configuration.                                                  |
| exact.ttl                  | integer          | False    | 3600          | [1, 2592000]             | Cache TTL in seconds.                                                                |
| policy                     | string           | True     | "redis"       | "redis", "redis-cluster" | Redis backend topology.                                                              |
| redis_host                 | string           | True\*   |               |                          | Required when `policy = "redis"`.                                                    |
| redis_port                 | integer          | False    | 6379          |                          |                                                                                      |
| redis_username             | string           | False    |               |                          |                                                                                      |
| redis_password             | string           | False    |               |                          | Stored encrypted. Supports the APISIX secret reference syntax (e.g. `$secret://…`).  |
| redis_database             | integer          | False    | 0             | [0, …]                   |                                                                                      |
| redis_timeout              | integer          | False    | 1000          | [1, …]                   | Milliseconds.                                                                        |
| redis_ssl                  | boolean          | False    | false         |                          |                                                                                      |
| redis_ssl_verify           | boolean          | False    | false         |                          |                                                                                      |
| redis_keepalive_timeout    | integer          | False    | 10000         | [1000, …]                | Milliseconds.                                                                        |
| redis_keepalive_pool       | integer          | False    | 100           | [1, …]                   |                                                                                      |
| redis_cluster_nodes        | array of string  | True\*   |               |                          | Required when `policy = "redis-cluster"`.                                            |
| redis_cluster_name         | string           | True\*   |               |                          | Required when `policy = "redis-cluster"`.                                            |
| redis_cluster_ssl          | boolean          | False    | false         |                          |                                                                                      |
| redis_cluster_ssl_verify   | boolean          | False    | false         |                          |                                                                                      |

`*` = required by the `dependencies.policy` clause when the named policy is selected.

## Response headers

| Header               | Values                                | Set when                                                                  |
| -------------------- | ------------------------------------- | ------------------------------------------------------------------------- |
| `X-AI-Cache-Status`  | `HIT`, `MISS`, `SKIP-STREAM`          | Always, when `ai-cache` runs the cache gate.                              |

## Example

This config enables a shared exact-match cache for `openai-chat` requests
proxied through `ai-proxy-multi`:

```yaml
plugins:
  ai-cache:
    exact: { ttl: 3600 }
    policy: redis
    redis_host: redis.internal
    redis_password: $secret://vault/kv/redis#password
```

## Caveats

The PR-1 cache key is computed from the **client-sent request body**:
`(model, messages)` only. This has two consequences operators must know:

1. Operator-side overrides applied by `ai-proxy` / `ai-proxy-multi`
   (e.g. `instances[*].options.model`) are **not** reflected in the cache
   key yet. A route that overrides the model post-cache will return the same
   cached entry for distinct effective models. **Flush Redis before relying
   on cache correctness on any route with such overrides.** A subsequent PR
   in this series fixes this by hashing the effective post-override body.
2. Output-shaping fields such as `temperature`, `top_p`, `seed`, `tools`,
   `response_format`, and `stop` are not yet in the key. Different settings
   on those fields will share a cache slot. A subsequent PR expands the key
   whitelist.

The cache is skipped (never written) when:

- The request is streaming (`stream: true`); response header is `SKIP-STREAM`.
- The upstream returns a non-2xx status.
- The upstream response body is not valid JSON.
- The upstream response body exceeds 1 MiB.
- Redis is unreachable; the plugin logs a warning and the upstream serves
  the response normally. `ai-cache` never converts an upstream-reachable
  request into a 5xx.

Not in the cache key by design: `user`, `metadata`, request id, customer API
key, auth headers, custom client headers.

## Disable

To remove `ai-cache` from a route, send a route update without the plugin in
the `plugins` block.
