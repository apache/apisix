---
title: ai-cache
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-cache
description: The ai-cache Plugin caches LLM responses in Redis so identical or semantically similar prompts are served from cache, reducing latency and upstream cost.
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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `ai-cache` Plugin caches LLM responses in Redis so identical or semantically similar prompts are served from cache instead of incurring another upstream call. It supports two cache layers: an exact-match layer (`exact`) keyed by a hash of the prompt, and a semantic layer (`semantic`) that compares prompt embeddings via Redis Stack vector search. Either layer can be enabled independently, and a hit on the semantic layer backfills the exact layer so subsequent identical prompts return immediately.

The Plugin should be used together with [ai-proxy](./ai-proxy.md) or [ai-proxy-multi](./ai-proxy-multi.md) on the same Route. The semantic layer requires Redis Stack with the RediSearch module and an embedding provider (OpenAI or Azure OpenAI).

## Plugin Attributes

| Name | Type | Required | Default | Valid values | Description |
| --- | --- | --- | --- | --- | --- |
| `layers` | array[string] | False | `["exact", "semantic"]` | `"exact"`, `"semantic"` | Cache layers to enable, queried in order. |
| `exact.ttl` | integer | False | `3600` | ≥ 1 | Time-to-live in seconds for exact-layer entries. |
| `semantic.similarity_threshold` | number | False | `0.95` | 0–1 | Minimum cosine similarity required for a semantic-layer hit. |
| `semantic.ttl` | integer | False | `86400` | ≥ 1 | Time-to-live in seconds for semantic-layer entries. |
| `semantic.embedding.provider` | string | True (if semantic enabled) | | `"openai"`, `"azure_openai"` | Embedding API provider. |
| `semantic.embedding.endpoint` | string | True (if semantic enabled) | | | HTTPS URL of the embedding API. |
| `semantic.embedding.api_key` | string | True (if semantic enabled) | | | API key for the embedding provider. Stored encrypted. |
| `semantic.embedding.model` | string | False | | | Embedding model name. Uses provider default if omitted. |
| `cache_key.include_consumer` | boolean | False | `false` | | If `true`, partition the cache by consumer name. |
| `cache_key.include_vars` | array[string] | False | `[]` | | Additional `ctx.var` names included in the cache key, for example `["$http_x_tenant_id"]`. |
| `bypass_on` | array[object] | False | | | List of `{header, equals}` rules. If any matches, the request bypasses the cache. |
| `max_cache_body_size` | integer | False | `1048576` | ≥ 1 | Maximum response size in bytes to write to cache. Larger responses pass through but are not cached. |
| `headers.cache_status` | string | False | `"X-AI-Cache-Status"` | | Response header for cache status (`HIT-L1`, `HIT-L2`, `MISS`, `BYPASS`). |
| `headers.cache_age` | string | False | `"X-AI-Cache-Age"` | | Response header for the age in seconds of an exact-layer hit. |
| `headers.cache_similarity` | string | False | `"X-AI-Cache-Similarity"` | | Response header for the similarity score of a semantic-layer hit. |

Redis connection fields (`redis_host`, `redis_port`, `redis_password`, `redis_database`, `redis_timeout`, `redis_ssl`, `redis_ssl_verify`, `redis_username`, `redis_keepalive_timeout`, `redis_keepalive_pool`) follow the shared Redis schema. At minimum, `redis_host` is required.

## Examples

The following examples use OpenAI as the Upstream service provider. Before proceeding, create an [OpenAI account](https://openai.com) and an [API key](https://openai.com/blog/openai-api). You can optionally save the key to an environment variable:

```shell
export OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>
```

If you are working with other LLM providers, please refer to the provider's documentation to obtain an API key.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Cache Identical Prompts with the Exact Layer

The following example demonstrates how to use the `ai-cache` Plugin with the exact layer only, so that identical prompts are returned from cache.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route that uses [ai-proxy](./ai-proxy.md) to proxy to OpenAI and `ai-cache` to cache exact-match prompts:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      },
      "ai-cache": {
        "layers": ["exact"],
        "exact": { "ttl": 3600 },
        "redis_host": "127.0.0.1"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

Create a Route with the `ai-cache` and [ai-proxy](./ai-proxy.md) Plugins configured as such:

```yaml title="adc.yaml"
services:
  - name: ai-cache-service
    routes:
      - name: ai-cache-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
          ai-cache:
            layers:
              - exact
            exact:
              ttl: 3600
            redis_host: 127.0.0.1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
</Tabs>

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "What is the capital of France?" }
    ]
  }'
```

The first request reaches OpenAI and you should receive a response similar to the following:

```text
HTTP/1.1 200 OK
Content-Type: application/json
Server: APISIX/3.16.0
X-AI-Cache-Status: MISS

{
  "id": "chatcmpl-Da7Iqsqz9gc8Mkf07Hn4NCzAH5Ri1",
  "object": "chat.completion",
  "created": 1777500252,
  "model": "gpt-4o-mini-2024-07-18",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The capital of France is Paris.",
        "refusal": null
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 14,
    "completion_tokens": 7,
    "total_tokens": 21
  },
  "system_fingerprint": "fp_d3214ccada"
}
```

Send the same request again:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "What is the capital of France?" }
    ]
  }'
```

The second request returns from cache without contacting OpenAI. The cached response is replayed from Redis, so the body is shorter and does not contain the original `created`, `model`, `usage`, or `system_fingerprint` fields:

```text
HTTP/1.1 200 OK
Content-Type: application/json
Server: APISIX/3.16.0
X-AI-Cache-Status: HIT-L1
X-AI-Cache-Age: 4

{
  "id": "f558665e-3a03-42e3-9aa9-f54c402927c0",
  "object": "chat.completion",
  "choices": [
    {
      "index": 0,
      "message": {
        "content": "The capital of France is Paris.",
        "role": "assistant"
      },
      "finish_reason": "stop"
    }
  ]
}
```

### Cache Paraphrased Prompts with the Semantic Layer

The following example demonstrates how to enable the semantic layer so that prompts with different wording but similar meaning are served from cache.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      },
      "ai-cache": {
        "layers": ["exact", "semantic"],
        "exact": { "ttl": 3600 },
        "semantic": {
          "similarity_threshold": 0.92,
          "ttl": 86400,
          "embedding": {
            "provider": "openai",
            "endpoint": "https://api.openai.com/v1/embeddings",
            "api_key": "'"$OPENAI_API_KEY"'",
            "model": "text-embedding-3-small"
          }
        },
        "redis_host": "127.0.0.1"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: ai-cache-service
    routes:
      - name: ai-cache-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
          ai-cache:
            layers:
              - exact
              - semantic
            exact:
              ttl: 3600
            semantic:
              similarity_threshold: 0.92
              ttl: 86400
              embedding:
                provider: openai
                endpoint: https://api.openai.com/v1/embeddings
                api_key: "${OPENAI_API_KEY}"
                model: text-embedding-3-small
            redis_host: 127.0.0.1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
</Tabs>

Send a first request:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "What is the capital of France?" }
    ]
  }'
```

The first request reaches OpenAI:

```text
HTTP/1.1 200 OK
Content-Type: application/json
Server: APISIX/3.16.0
X-AI-Cache-Status: MISS

{
  "id": "chatcmpl-Da7Iqsqz9gc8Mkf07Hn4NCzAH5Ri1",
  "object": "chat.completion",
  "model": "gpt-4o-mini-2024-07-18",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The capital of France is Paris."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": { "prompt_tokens": 14, "completion_tokens": 7, "total_tokens": 21 }
}
```

Wait a couple of seconds for the semantic-layer write to complete in the background, then send a second request with paraphrased wording:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "capital of France what is?" }
    ]
  }'
```

The semantic layer matches the embedding (cosine similarity above the threshold) and returns the cached response without contacting OpenAI:

```text
HTTP/1.1 200 OK
Content-Type: application/json
Server: APISIX/3.16.0
X-AI-Cache-Status: HIT-L2
X-AI-Cache-Similarity: 0.9720680713654

{
  "id": "40b612a5-1424-4096-b7ec-8537a1ee6fd3",
  "object": "chat.completion",
  "choices": [
    {
      "index": 0,
      "message": {
        "content": "The capital of France is Paris.",
        "role": "assistant"
      },
      "finish_reason": "stop"
    }
  ]
}
```

A semantic-layer hit also backfills the exact layer, so an immediate retry of the same paraphrase returns `X-AI-Cache-Status: HIT-L1`.

### Isolate Cache Entries Per Consumer or Tenant

The following example demonstrates how to namespace cache entries so that one consumer's response is not served to another. Use `cache_key.include_consumer` to partition by consumer name, or `cache_key.include_vars` to include request variables such as a tenant header.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      },
      "ai-cache": {
        "layers": ["exact"],
        "exact": { "ttl": 3600 },
        "cache_key": {
          "include_consumer": true,
          "include_vars": ["$http_x_tenant_id"]
        },
        "redis_host": "127.0.0.1"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: ai-cache-service
    routes:
      - name: ai-cache-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
          ai-cache:
            layers:
              - exact
            exact:
              ttl: 3600
            cache_key:
              include_consumer: true
              include_vars:
                - "$http_x_tenant_id"
            redis_host: 127.0.0.1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
</Tabs>

Two requests with the same prompt but different `X-Tenant-Id` headers each receive `X-AI-Cache-Status: MISS`, because the cache key now includes the tenant identifier.

### Bypass the Cache on a Header

The following example demonstrates how to skip the cache entirely when a request carries a specific header, for example to refresh a cached response or to support staff debugging.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      },
      "ai-cache": {
        "layers": ["exact"],
        "exact": { "ttl": 3600 },
        "bypass_on": [
          { "header": "X-Cache-Bypass", "equals": "1" }
        ],
        "redis_host": "127.0.0.1"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: ai-cache-service
    routes:
      - name: ai-cache-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
          ai-cache:
            layers:
              - exact
            exact:
              ttl: 3600
            bypass_on:
              - header: X-Cache-Bypass
                equals: "1"
            redis_host: 127.0.0.1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
</Tabs>

Send a request with the bypass header:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H "X-Cache-Bypass: 1" \
  -d '{
    "messages": [
      { "role": "user", "content": "What is the capital of France?" }
    ]
  }'
```

The request reaches OpenAI even though a cached entry exists, and the response is not written back to cache. You can confirm the upstream was contacted because the response includes the original `created`, `model`, `usage`, and `system_fingerprint` fields:

```text
HTTP/1.1 200 OK
Content-Type: application/json
Server: APISIX/3.16.0
X-AI-Cache-Status: BYPASS

{
  "id": "chatcmpl-Da7N4E9fA6KoQ7av98hL0zxplPCcD",
  "object": "chat.completion",
  "created": 1777500514,
  "model": "gpt-4o-mini-2024-07-18",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The capital of France is Paris.",
        "refusal": null
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 14,
    "completion_tokens": 7,
    "total_tokens": 21
  },
  "system_fingerprint": "fp_d3214ccada"
}
```

## Caveats

### The semantic-layer write is asynchronous

After a `MISS`, the embedding fetch and Redis vector store happen in a background timer. If you send a paraphrased prompt immediately after the first request, you may see another `MISS` because the entry has not been stored yet. Wait a couple of seconds before sending a paraphrase to verify a semantic hit.

### Similarity is mathematical, not human-judged

Two prompts that look semantically equivalent to a human can score below the configured `similarity_threshold` and therefore miss the cache. Conversely, a small wording change can flip the result. For example, with `similarity_threshold` set to `0.85` and the cache primed with `"What is the capital of France?"`:

| Prompt | Status | Similarity |
|--------|--------|------------|
| `capital of France?` | `HIT-L2` | `0.850` |
| `capital of France what?` | `MISS` | (below threshold) |
| `capital of France what is?` | `HIT-L2` | `0.972` |
| `capital of France what please?` | `HIT-L2` | `0.924` |
| `capital of France what is please tell me?` | `MISS` | (below threshold) |

Lower the threshold to catch more paraphrases at the cost of occasionally serving a cached answer for a genuinely different question. Tune empirically against your traffic.

### Embedding model dimensions are baked into the index

Redis Stack creates the vector index on the first request with a fixed `DIM` matching the embedding vector size (for example `1536` for `text-embedding-3-small`, `3072` for `text-embedding-3-large`). If you switch embedding models, or if the index was created with different-sized vectors during testing, subsequent requests will fail with a size-mismatch error in the APISIX warn log:

```text
ai-cache: L2 search error: Error parsing vector similarity query:
query vector blob size (6144) does not match index's expected size (12).
```

The Plugin degrades to `MISS` so requests still succeed, but the semantic layer effectively stops working. Drop the index to recover; it will be recreated on the next request with the correct dimension:

```shell
docker exec <redis-container> redis-cli FT.DROPINDEX ai-cache-idx DD
docker exec <redis-container> redis-cli --raw KEYS "ai-cache:*" \
  | xargs -r docker exec -i <redis-container> redis-cli DEL
```

### `BYPASS` does not refresh the cache

A request with the bypass header reaches the upstream but its response is not written back. Use it to force a fresh upstream call without invalidating or replacing the existing cached entry.

### The semantic layer requires Redis Stack

The `FT.CREATE` and `FT.SEARCH` commands used by the semantic layer come from the RediSearch module. Vanilla Redis will fail these commands and the layer will silently degrade to `MISS`. Use a Redis Stack image such as `redis/redis-stack:latest`.
