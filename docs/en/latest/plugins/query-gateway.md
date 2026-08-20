---
title: query-gateway
keywords:
  - Apache APISIX
  - API Gateway
  - QUERY
  - HTTP method
description: The query-gateway Plugin provides RFC 10008-aware QUERY caching and optional forwarding to POST-only Upstream services.
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

The `query-gateway` Plugin accepts client `QUERY` and `POST` requests. It provides safe, body-aware caching for `QUERY` requests and optionally for explicitly declared read-only `POST` routes. A client `QUERY` is forwarded as `POST` by default; configure a native QUERY-capable Upstream to preserve it.

Configure the Plugin only on Routes that explicitly match `request_method == QUERY`. Route matching and request security policies run against the client method. The method is changed immediately before APISIX proxies the request to the Upstream service.

## Attributes

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `preserve_original_method_header` | boolean | False | `true` | Forward the original method to Upstream. |
| `original_method_header` | string | False | `X-Original-Method` | Header used to forward the original method. APISIX overwrites an incoming header with the same name. |
| `query.upstream_method` | string | False | `post` | `post` forwards client QUERY requests as POST; `query` preserves QUERY for a native QUERY-capable Upstream. |
| `post.cache_enabled` | boolean | False | `false` | Enables cache eligibility for client POST requests only when `post.read_only` is also `true`. POST is never rewritten. |
| `post.read_only` | boolean | False | `false` | Explicitly declares the POST route safe for caching. |
| `cache.enabled` | boolean | False | `false` | Enables body-aware caching. |
| `cache.backend` | string | False | `local` | `local`, `redis`, or `redis-cluster`. |
| `cache.ttl` | integer | False | `30` | Maximum freshness lifetime in seconds. A shorter upstream max-age is honored. |
| `cache.fallback_ttl` | integer | False | `5` | Node-local cache lifetime while a Redis backend is unavailable. |
| `cache.write_queue_size` | integer | False | `1024` | Maximum pending Redis or Redis Cluster cache writes. Full queues drop cache writes without affecting client responses. |
| `cache.write_batch_size` | integer | False | `32` | Maximum Redis or Redis Cluster writes processed by one background drain iteration. |
| `cache.max_request_body_size` | integer | False | `262144` | Maximum in-memory request body size eligible for cache-key generation. Larger or file-backed bodies bypass cache. |
| `cache.max_response_body_size` | integer | False | `1048576` | Maximum response body size stored in cache. |
| `cache.cookie_names` | array[string] | False | | Explicit request-cookie allowlist. A request containing an unlisted cookie bypasses cache. |
| `cache.redis_*` | object fields | Required for `redis` | | Redis address, TLS, authentication, database, timeout, and keepalive settings. |
| `cache.redis_cluster_*` | object fields | Required for `redis-cluster` | | Redis Cluster name, seed nodes, TLS, authentication, timeout, and keepalive settings. |

## Example

Create a Route that accepts client `QUERY` requests and forwards them to a POST-only search service:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/query-search" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/v1/search",
    "vars": [["request_method", "==", "QUERY"]],
    "plugins": {
      "query-gateway": {
        "query": {
          "upstream_method": "post"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "search.internal:8080": 1
      }
    }
  }'
```

A client can issue a QUERY request with a body:

```shell
curl "http://127.0.0.1:9080/v1/search" \
  -X QUERY \
  -H "Content-Type: application/json" \
  --data '{"query":"apisix"}'
```

The Upstream receives:

```text
POST /v1/search
X-Original-Method: QUERY
Content-Type: application/json

{"query":"apisix"}
```

## Notes

- Client `QUERY` requests are forwarded as POST by default. Set `query.upstream_method: query` only for a native QUERY-capable Upstream.
- Client POST requests are passed through unchanged. Enable their cache eligibility only with both `post.cache_enabled: true` and `post.read_only: true`. Such a POST uses the same canonical cache identity as an equivalent QUERY request on the Route; the Upstream forwarding method never changes that identity.
- Match client methods explicitly in the Route when the route should serve only one method.
- The Plugin does not rewrite `OPTIONS`; use the `cors` Plugin when browser clients require QUERY CORS preflight handling.
- Enable cache only for read endpoints whose responses are safe to share.
- QUERY requires `Content-Type` as defined by RFC 10008, regardless of whether caching is enabled. APISIX returns `400` when it is missing.
- Cache keys include the RFC QUERY cache method, route scope, target URI, Content-Type, Content-Encoding, Content-Language, request negotiation headers, consumer identity, allowlisted cookies, and the SHA-256 digest of the unmodified request body. The key does not depend on the Upstream forwarding method.

## Relationship with proxy-cache

Use `proxy-cache` for conventional GET, HEAD, or POST response caching where an NGINX-variable cache key and its disk or memory strategies are sufficient. `query-gateway` is separate because it defines a body-aware SHA-256 cache identity, validates RFC 10008 QUERY requests, preserves client QUERY semantics while supporting POST-only Upstreams, and only admits POST after the Route owner explicitly declares it read-only.

## Cache Safety

The cache is deliberately conservative. It bypasses cache lookup and storage for requests with `Authorization`, `Range`, conditional request headers, `Cookie` unless every cookie is allowlisted, repeated cache-relevant headers, `Cache-Control: no-store` or `no-cache`, `Pragma: no-cache`, oversized bodies, and bodies not available in memory.

It never stores responses with `Set-Cookie`, `WWW-Authenticate`, `Proxy-Authenticate`, `Content-Range`, `Cache-Control: private`, `no-store`, `no-cache`, `max-age=0`, `s-maxage=0`, or unsupported `Vary` values. `Vary: Accept`, `Accept-Encoding`, and `Accept-Language` are included in the key. `Vary: Cookie`, `Authorization`, and `*` bypass cache.

When Redis or Redis Cluster cannot be reached, the Plugin opens a per-node circuit breaker and uses the local shared-memory cache for `cache.fallback_ttl` seconds. Remote writes use a bounded shared-memory queue and a single drain timer per backend, so cache misses do not create one timer per response. A full queue drops only the cache write; it never fails the client request. Cache hits preserve the origin `Date` value and emit a calculated `Age` value.
