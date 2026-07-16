---
title: ai-cache
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-cache
  - AI
  - LLM
description: The ai-cache Plugin caches LLM responses in Redis and replays them for later requests that resolve to the same prompt, cutting upstream token cost and latency.
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

The `ai-cache` Plugin caches LLM responses and replays them for later requests that resolve to the same prompt, cutting upstream token cost and latency for repetitive workloads (FAQ bots, document Q&A, translation).

This Plugin supports two cache layers:

- **Exact (L1):** A SHA-256 fingerprint of the effective prompt is used as the Redis key. An identical prompt always hits the same entry.
- **Semantic (L2):** When L1 misses, the prompt is embedded into a vector and a nearest-neighbour search retrieves a past response whose embedding is within the configured similarity threshold. L2 is disabled by default; enable it by adding `"semantic"` to `layers`.

The `ai-cache` Plugin must be used with the [`ai-proxy`](./ai-proxy.md) or [`ai-proxy-multi`](./ai-proxy-multi.md) Plugin.

### Streaming

Streaming (SSE) responses are cached and replayed. A streamed response is written to the cache only after it completes — that is, the terminal event for the client protocol is received (`data: [DONE]` for OpenAI, `message_stop` for Anthropic, `response.completed` for OpenAI Responses). A stream that is interrupted (client disconnect, or the `ai-proxy` `max_stream_duration_ms` / `max_response_bytes` limits) is never cached, so partial responses are never served. On a hit, the stored response is replayed as a single `text/event-stream` body with its terminal event intact.

Streaming and non-streaming requests for the same prompt are cached as **separate** entries at both layers, so a streaming client always receives a stream and a non-streaming client always receives a single JSON response. This applies whether streaming is requested by the client (`"stream": true`) or forced by the route via `options.stream`.

Limitations: binary streaming formats without an SSE terminal event (for example Bedrock ConverseStream) are not cached. Replay is immediate (the full stored response is sent at once) rather than re-timed token-by-token.

:::note

By default the cache is isolated per route, so two routes never serve each other's entries even when they see the same protocol, model and messages. Set `cache_key.share_across_routes` to `true` to share one cache space across routes.

Even with `cache_key.share_across_routes` enabled, the cache key identifies the *effective* upstream request — the request `ai-proxy` actually sends after applying the AI instance's `provider`, `options` (model, temperature, and other model parameters) and `override`. Routes that would call the model differently therefore keep separate cache entries, so one route's response is never served for another.

:::

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| exact.ttl | integer | False | 3600 | >= 1 | Time-to-live, in seconds, of an exact-cache entry. |
| cache_key.share_across_routes | boolean | False | false | | By default the cache is isolated per route. If true, entries are shared across every route that computes the same key. |
| cache_key.include_consumer | boolean | False | false | | If true, scope the cache per consumer so entries are not shared across consumers. |
| cache_key.include_vars | array[string] | False | [] | | NGINX variables added to the cache scope (for example `["http_x_tenant"]`), isolating entries by their values. |
| max_cache_body_size | integer | False | 1048576 | >= 0 | Maximum response body size, in bytes, to cache. Larger responses are not cached. |
| cache_headers | boolean | False | true | | If true, emit the following response headers: `X-AI-Cache-Status` (always), one of `MISS`, `HIT` (exact or semantic cache hit), or `BYPASS`; `X-AI-Cache-Age`, the entry age in seconds, on any cache hit; `X-AI-Cache-Similarity`, the cosine similarity score (0–1) between the incoming prompt and the matched entry, on a semantic cache hit only. |
| fail_mode | string | False | `"skip"` | `skip`, `warn`, `error` | Behavior when the request is not a recognized AI request that this Plugin can cache (for example, a request that did not pass through `ai-proxy` or `ai-proxy-multi`). `skip`: let the request pass through uncached; `warn`: pass through uncached and log a warning; `error`: reject the request. |
| bypass_on | array[object] | False | | | Rules that skip the cache entirely (no lookup, no write-back) when any rule matches. |
| bypass_on[].header | string | True | | | Request header name to match. |
| bypass_on[].equals | string | True | | | Bypass when the request header's value exactly equals this string. |
| policy | string | False | redis | redis | Storage backend. Only single-node `redis` is available in this release. |
| layers | array[string] | False | ["exact"] | exact, semantic | Cache layers to activate. `exact` performs an exact-match fingerprint lookup (L1) and is always active; `"exact"` must always be present in this array. `semantic` enables a vector-similarity lookup (L2) that is consulted only on an L1 miss. At least one value is required; values must be unique. |
| redis_host | string | True | | | Address of the Redis node. |
| redis_port | integer | False | 6379 | >= 1 | Port of the Redis node. |
| redis_username | string | False | | | Username for Redis if Redis ACL is used. For the legacy `requirepass` method, configure only `redis_password`. |
| redis_password | string | False | | | Password of the Redis node. Encrypted with AES before being stored in etcd. |
| redis_database | integer | False | 0 | >= 0 | Database number in Redis. |
| redis_timeout | integer | False | 1000 | >= 1 | Redis timeout value in milliseconds. |
| redis_ssl | boolean | False | false | | If true, use SSL to connect to Redis. |
| redis_ssl_verify | boolean | False | false | | If true, verify the Redis server SSL certificate. |
| redis_keepalive_timeout | integer | False | 10000 | >= 1000 | Keepalive timeout, in milliseconds, for the Redis connection pool. |
| redis_keepalive_pool | integer | False | 100 | >= 1 | Maximum number of connections in the Redis keepalive pool. |

### Semantic (L2) Attributes

:::caution Redis Stack required for semantic caching

When `"semantic"` is included in `layers`, the configured Redis instance **must** be [Redis Stack](https://redis.io/docs/stack/) (with the RediSearch module). The L1 exact cache and the L2 semantic cache share the same Redis connection configured by `redis_host` / `redis_port` etc.

Vanilla Redis is sufficient when `layers` is omitted or contains only `"exact"` (the default).

:::

The `semantic` object is required when `"semantic"` is present in `layers`. It accepts the following attributes:

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| semantic.similarity_threshold | number | False | 0.95 | [0, 1] | Minimum cosine similarity (equivalently, 1 − distance) required to consider a retrieved vector a match. Requests below this threshold fall through to the upstream. |
| semantic.top_k | integer | False | 1 | >= 1 | Number of nearest-neighbour candidates to retrieve from the vector index. Only the highest-scoring result is evaluated against `similarity_threshold`. |
| semantic.distance_metric | string | False | `"cosine"` | `cosine` | Vector distance metric. Only `cosine` is currently supported. |
| semantic.ttl | integer | False | 86400 | >= 1 | Time-to-live, in seconds, of a semantic (L2) cache entry. |
| semantic.match.message_countback | integer | False | 1 | >= 1 | Number of trailing `user`-role messages to include in the embedding input. |
| semantic.match.ignore_system_prompts | boolean | False | true | | If true, `system`-role messages are excluded from the embedding input. |
| semantic.match.ignore_assistant_prompts | boolean | False | true | | If true, `assistant`-role messages are excluded from the embedding input. |
| semantic.match.ignore_tool_prompts | boolean | False | true | | If true, `tool`-role messages are excluded from the embedding input. |
| semantic.embedding | object | **True** | | | Embedding provider configuration. Exactly one of `openai` or `azure_openai` must be specified. |
| semantic.embedding.openai.endpoint | string | False | | | OpenAI-compatible embedding API endpoint URL. Defaults to the public OpenAI API when omitted. |
| semantic.embedding.openai.model | string | **True** | | | Embedding model name (for example, `text-embedding-3-small`). |
| semantic.embedding.openai.api_key | string | **True** | | | OpenAI API key. Encrypted at rest in etcd. |
| semantic.embedding.openai.dimensions | integer | False | | >= 1 | Override the embedding output dimension for models that support it. |
| semantic.embedding.openai.ssl_verify | boolean | False | true | | If true, verifies the embedding service's certificate. |
| semantic.embedding.openai.timeout | integer | False | 5000 | >= 1 | Request timeout in milliseconds for the embedding service. |
| semantic.embedding.azure_openai.endpoint | string | **True** | | | Azure OpenAI deployment endpoint URL. |
| semantic.embedding.azure_openai.api_key | string | **True** | | | Azure OpenAI API key. Encrypted at rest in etcd. |
| semantic.embedding.azure_openai.dimensions | integer | False | | >= 1 | Override the embedding output dimension. |
| semantic.embedding.azure_openai.ssl_verify | boolean | False | true | | If true, verifies the embedding service's certificate. |
| semantic.embedding.azure_openai.timeout | integer | False | 5000 | >= 1 | Request timeout in milliseconds for the embedding service. |
| semantic.vector_search | object | **True** | | | Vector index configuration. |
| semantic.vector_search.redis.index | string | False | `"ai-cache"` | | RediSearch index name used as the vector store. |

:::note Security: multi-tenant deployments

Cache entries are scoped per route by default. In a multi-tenant deployment where multiple consumers share a route, a cached response produced for one consumer could be served to another. To prevent cross-tenant leakage:

- Set `cache_key.include_consumer: true` to scope entries per consumer identity.
- Use `cache_key.include_vars` to add tenant-identifying NGINX variables (for example `["http_x_tenant_id"]`) to the cache scope.

Both L1 and L2 entries respect the same `cache_key` scoping rules.

:::

## Example

The example below uses OpenAI as the Upstream LLM provider. Obtain an [OpenAI API key](https://openai.com/blog/openai-api) and save it, along with your Admin API key, to environment variables:

```shell
export OPENAI_API_KEY=your-openai-api-key
export admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

A Redis instance must be reachable at the configured `redis_host`.

### Cache LLM Responses

Create a Route to the LLM chat completion endpoint with the [`ai-proxy`](./ai-proxy.md) and `ai-cache` Plugins.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-cache-route",
    "uri": "/anything",
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": { "header": { "Authorization": "Bearer '"$OPENAI_API_KEY"'" } },
        "options": { "model": "gpt-4o" }
      },
      "ai-cache": {
        "redis_host": "127.0.0.1"
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

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
              model: gpt-4o
          ai-cache:
            redis_host: 127.0.0.1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="ai-cache-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-cache-plugin-config
spec:
  plugins:
    - name: ai-cache
      config:
        redis_host: 127.0.0.1
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-openai-api-key"
        options:
          model: gpt-4o
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-cache-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-cache-plugin-config
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-cache-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="ai-cache-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-cache-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-cache-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-cache
          enable: true
          config:
            redis_host: 127.0.0.1
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-openai-api-key"
            options:
              model: gpt-4o
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-cache-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{ "messages": [{ "role": "user", "content": "What is Apache APISIX? Answer in one sentence." }] }'
```

The first request is a cache miss and is proxied to the LLM. The response carries the `X-AI-Cache-Status: MISS` header and a body similar to the following:

```json
{
  "id": "chatcmpl-DtmdUDZeSZ0t62y6BvLkSk5qfH3zA",
  "object": "chat.completion",
  "created": 1782187368,
  "model": "gpt-4o-2024-08-06",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Apache APISIX is a dynamic, cloud-native API gateway that provides high performance, scalability, and security for API management."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 19,
    "completion_tokens": 25,
    "total_tokens": 44
  }
}
```

Send the same request again. It is served from the cache without calling the LLM, returning the identical body with the headers:

```text
X-AI-Cache-Status: HIT
X-AI-Cache-Age: 8
```

### Bypass the Cache

To skip the cache for selected requests, add a `bypass_on` rule and update the Route:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/ai-cache-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "ai-cache": {
        "redis_host": "127.0.0.1",
        "bypass_on": [{ "header": "X-Cache-Bypass", "equals": "1" }]
      }
    }
  }'
```

Send a request with the matching header:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H "X-Cache-Bypass: 1" \
  -d '{ "messages": [{ "role": "user", "content": "What is Apache APISIX? Answer in one sentence." }] }'
```

The cache is skipped entirely (no lookup and no write-back), and the response carries the `X-AI-Cache-Status: BYPASS` header.

### Cache LLM Responses with Semantic Matching

This example adds the semantic (L2) cache layer so that near-duplicate prompts are served from cache even when the wording differs slightly. In addition to a running Redis Stack instance, an OpenAI API key is needed for the embedding service.

:::caution

The Redis instance must be [Redis Stack](https://redis.io/docs/stack/) (RediSearch module). Vanilla Redis is not supported for semantic caching.

:::

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'}
]}>

<TabItem value="admin-api">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-cache-semantic-route",
    "uri": "/anything",
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": { "header": { "Authorization": "Bearer '"$OPENAI_API_KEY"'" } },
        "options": { "model": "gpt-4o" }
      },
      "ai-cache": {
        "redis_host": "127.0.0.1",
        "layers": ["exact", "semantic"],
        "semantic": {
          "similarity_threshold": 0.92,
          "embedding": {
            "openai": {
              "model": "text-embedding-3-small",
              "api_key": "'"$OPENAI_API_KEY"'"
            }
          },
          "vector_search": {
            "redis": {
              "index": "ai-cache"
            }
          }
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: ai-cache-semantic-service
    routes:
      - name: ai-cache-semantic-route
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
              model: gpt-4o
          ai-cache:
            redis_host: 127.0.0.1
            layers:
              - exact
              - semantic
            semantic:
              similarity_threshold: 0.92
              embedding:
                openai:
                  model: text-embedding-3-small
                  api_key: "${OPENAI_API_KEY}"
              vector_search:
                redis:
                  index: ai-cache
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

</Tabs>

Send an initial request:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{ "messages": [{ "role": "user", "content": "What is Apache APISIX?" }] }'
```

The first request is an L1 and L2 miss; the Plugin proxies it to the LLM, embeds the prompt, and stores both the exact entry and the vector in Redis. The response carries `X-AI-Cache-Status: MISS`.

Send a semantically similar but differently worded request:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{ "messages": [{ "role": "user", "content": "Can you explain what Apache APISIX is?" }] }'
```

This request misses L1 (different fingerprint) but hits L2 (similar embedding). The response is served from the semantic cache with:

```text
X-AI-Cache-Status: HIT
X-AI-Cache-Age: 12
X-AI-Cache-Similarity: 0.9487
```

The `X-AI-Cache-Similarity` header reports the cosine similarity (1 − distance) between the incoming prompt and the matched cache entry.
