---
title: Cache API Responses
keywords:
  - API Gateway
  - Apache APISIX
  - API Response Cache
  - Proxy Cache
description: Configure and verify Apache APISIX proxy-cache for API responses, including cache keys, TTL, identity isolation, sensitive data, and invalidation.
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

The [`proxy-cache` plugin](../plugins/proxy-cache.md) can serve a stored upstream response when a later request produces the same effective cache key. This can reduce upstream work and response latency for content that is safe to reuse. It does not make every successful response cacheable, and it does not replace an application-level freshness or invalidation design.

This tutorial configures a disk-backed cache for one public `GET` endpoint and verifies `MISS`, `HIT`, and expiration behavior.

## Before you cache a response

Define these properties first:

- **Cacheable content:** Cache only responses whose reuse is valid. The plugin does not cache upstream responses carrying `Cache-Control: private`, `no-store`, or `no-cache`. It also avoids `Set-Cookie` responses by default.
- **Cache key:** The default key is `[$host, $request_uri]`, so the query string is included. The plugin also honors upstream `Vary`. Keep the default unless another verified request dimension changes the response. `cache_key` array values are concatenated without an automatic separator; if you build a custom multidimensional key, insert an explicit constant delimiter that cannot occur in the normalized inputs and test for collisions.
- **Identity boundary:** `consumer_isolation` defaults to `true`, but it partitions only when APISIX has resolved a Consumer or `remote_user`. Prefer that built-in partitioning for authenticated Consumers. A bearer token or arbitrary tenant header does not automatically create a safe per-user namespace. If you include an identity variable in a custom `cache_key`, built-in consumer isolation becomes a no-op, so the custom key must provide an unambiguous, tested identity boundary. Otherwise, do not cache the route.
- **TTL and invalidation:** Choose a TTL from the data's freshness requirement and define how an operator or publisher removes stale entries. Disk-cache TTL comes from upstream cache headers or the static cache-zone configuration.
- **Failure behavior:** A cached response can remain available while an upstream is unhealthy. Decide whether that behavior is acceptable for the data rather than treating it as automatic availability protection.

## Prerequisites

Ensure that Apache APISIX is running and that you can reach its Admin API from an operator environment. The default configuration includes the disk cache zone `disk_cache_one`.

For this local example, reuse the resolved Admin API secret from the environment that starts APISIX:

```bash
admin_key="${ADMIN_KEY:?ADMIN_KEY is not set}"
```

If a local test configuration contains the actual key rather than an environment or secret reference, you can read that literal value with `admin_key="$(yq -r '.deployment.admin.admin_key[0].key' conf/config.yaml)"`. `yq` does not resolve `${{VARIABLE}}` templates or external secrets.

## Configure a cached route

Create a Route that caches only successful `GET` responses:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/proxy-cache-demo" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/anything",
    "methods": ["GET"],
    "plugins": {
      "proxy-cache": {
        "cache_strategy": "disk",
        "cache_zone": "disk_cache_one",
        "cache_key": ["$host", "$request_uri"],
        "cache_method": ["GET"],
        "cache_http_status": [200],
        "consumer_isolation": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

The example deliberately limits `cache_http_status` to `200`; the plugin's broader defaults also include `301` and `404`. Review status codes explicitly for each route.

## Verify cache behavior

Send the first request:

```shell
curl -i "http://127.0.0.1:9080/anything?item=1"
```

The first response should include:

```text
Apisix-Cache-Status: MISS
```

Send the same request again before the entry expires. It should include:

```text
Apisix-Cache-Status: HIT
```

A request with a different query string, such as `?item=2`, has a different default cache key and should initially return `MISS`. After the TTL expires, the next request can report `EXPIRED` while APISIX refreshes the entry from the upstream.

Verify the response body as well as the status header. A `HIT` only proves that APISIX found a matching cache entry; it does not prove that the entry contains the correct tenant, authorization, language, or current business state.

## Configure a disk-cache TTL

For disk caching, set the fallback TTL in the static cache-zone configuration. Upstream `Cache-Control` or `Expires` headers can determine the effective TTL; the fallback applies when those headers do not provide one, and to the documented unavailable-upstream error cases.

```yaml title="conf/config.yaml"
apisix:
  proxy_cache:
    cache_ttl: 60s
    zones:
      - name: disk_cache_one
        memory_size: 50m
        disk_size: 1G
        disk_path: /tmp/disk_cache_one
        cache_levels: "1:2"
```

Reload APISIX after changing the static cache-zone configuration. Size the memory index, disk capacity, and filesystem permissions for the expected key count and response volume.

## Invalidate and protect cached data

Expiration is the simplest invalidation mechanism. The plugin also handles the `PURGE` method for the effective cache key, but a public `GET` Route does not need to accept `PURGE`. If you enable purge access, put it on a separately authenticated and network-restricted operator path, verify the exact key and identity namespace being purged, and audit the action. An unauthenticated purge endpoint would allow clients to evict cached content.

Before using the route in production, test the following:

- authenticated and unauthenticated requests cannot share private data;
- upstream `Cache-Control`, `Expires`, `Vary`, and `Set-Cookie` behavior matches the intended policy;
- key inputs are verified and contain no raw credentials;
- TTL and purge remove the expected variants; and
- cache storage limits, error paths, and upstream recovery are observable.

For all plugin attributes, memory-cache behavior, and additional configuration interfaces, see the [`proxy-cache` plugin reference](../plugins/proxy-cache.md).
