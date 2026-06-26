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

This release implements the **exact** cache layer (L1); a semantic cache layer (L2) is planned for a future release.

The `ai-cache` Plugin must be used with the [`ai-proxy`](./ai-proxy.md) or [`ai-proxy-multi`](./ai-proxy-multi.md) Plugin.

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
| cache_headers | boolean | False | true | | If true, add the `X-AI-Cache-Status` response header (and `X-AI-Cache-Age`, the entry age in seconds, on a hit). |
| fail_mode | string | False | `"skip"` | `skip`, `warn`, `error` | Behavior when the request is not a recognized AI request that this Plugin can cache (for example, a request that did not pass through `ai-proxy` or `ai-proxy-multi`). `skip`: let the request pass through uncached; `warn`: pass through uncached and log a warning; `error`: reject the request. |
| bypass_on | array[object] | False | | | Rules that skip the cache entirely (no lookup, no write-back) when any rule matches. |
| bypass_on[].header | string | True | | | Request header name to match. |
| bypass_on[].equals | string | True | | | Bypass when the request header's value exactly equals this string. |
| policy | string | False | redis | redis | Storage backend. Only single-node `redis` is available in this release. |
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
