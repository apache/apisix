---
title: proxy-cache
keywords:
  - Apache APISIX
  - API Gateway
  - Proxy Cache
description: The proxy-cache Plugin caches responses based on keys, supporting disk and memory caching for GET, POST, and HEAD requests, enhancing API performance.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/proxy-cache" />
</head>

## Description

The `proxy-cache` Plugin provides the capability to cache responses based on a cache key. The Plugin supports both disk-based and memory-based caching options to cache for [GET](https://anything.org/learn/serving-over-http/#get-request), [POST](https://anything.org/learn/serving-over-http/#post-request), and [HEAD](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/HEAD) requests.

Responses can be conditionally cached based on request HTTP methods, response status codes, request header values, and more.

## Attributes

| Name               | Type           | Required | Default                   | Valid values            | Description                                                                                                                                                                                                                                                                                           |
|--------------------|----------------|----------|---------------------------|-------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| cache_strategy     | string         | False    | disk                      | ["disk","memory"]       | Caching strategy. Cache on disk or in memory.          |
| cache_zone         | string         | False    | disk_cache_one            |                         | Cache zone used with the caching strategy. The value should match one of the cache zones defined in the [configuration files](#static-configurations) and should correspond to the caching strategy. For example, when using the in-memory caching strategy, you should use an in-memory cache zone. |
| cache_key          | array[string]  | False    | ["$host", "$request_uri"] |                         | Key to use for caching. Support [NGINX variables](https://nginx.org/en/docs/varindex.html) and constant strings in values. Variables should be prefixed with a `$` sign.    |
| cache_bypass       | array[string]  | False    |                           |                         | One or more parameters to parse value from, such that if any of the values is not empty and is not equal to `0`, response will not be retrieved from cache. Support [NGINX variables](https://nginx.org/en/docs/varindex.html) and constant strings in values. Variables should be prefixed with a `$` sign.     |
| cache_method       | array[string]  | False    | ["GET", "HEAD"]           | ["GET", "POST", "HEAD"] | Request methods of which the response should be cached.       |
| cache_http_status  | array[integer] | False    | [200, 301, 404]           | [200, 599]              | Response HTTP status codes of which the response should be cached.   |
| hide_cache_headers | boolean        | False    | false                     |                         | If true, hide `Expires` and `Cache-Control` response headers.   |
| cache_control      | boolean        | False    | false                     |                         | If true, comply with `Cache-Control` behavior in the HTTP specification. Only valid for in-memory strategy.     |
| no_cache           | array[string]  | False    |                           |                         | One or more parameters to parse value from, such that if any of the values is not empty and is not equal to `0`, response will not be cached. Support [NGINX variables](https://nginx.org/en/docs/varindex.html) and constant strings in values. Variables should be prefixed with a `$` sign.       |
| cache_ttl          | integer        | False    | 300          |        >=1          | Cache time to live (TTL) in seconds when caching in memory. To adjust the TTL when caching on disk, update `cache_ttl` in the [configuration files](#static-configurations). The TTL value is evaluated in conjunction with the values in the response headers  [`Cache-Control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) and [`Expires`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Expires) received from the Upstream service.     |

## Static Configurations

By default, values such as `cache_ttl` when caching on disk and cache `zones` are pre-configured in the [default configuration](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua).

To customize these values, add the corresponding configurations to `config.yaml`. For example:

```yaml
apisix:
  proxy_cache:
    cache_ttl: 10s  # default cache TTL used when caching on disk, only if none of the `Expires`
                    # and `Cache-Control` response headers is present, or if APISIX returns
                    # `502 Bad Gateway` or `504 Gateway Timeout` due to unavailable upstreams
    zones:
      - name: disk_cache_one
        memory_size: 50m
        disk_size: 1G
        disk_path: /tmp/disk_cache_one
        cache_levels: 1:2
      # - name: disk_cache_two
      #   memory_size: 50m
      #   disk_size: 1G
      #   disk_path: "/tmp/disk_cache_two"
      #   cache_levels: "1:2"
      - name: memory_cache
        memory_size: 50m
```

Reload APISIX for changes to take effect.

## Examples

The examples below demonstrate how you can configure `proxy-cache` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Cache Data on Disk

On-disk caching strategy offers the advantages of data persistency when system restarts and having larger storage capacity compared to in-memory cache. It is suitable for applications that prioritize durability and can tolerate slightly larger cache access latency.

The following example demonstrates how you can use `proxy-cache` Plugin on a Route to cache data on disk.

When using the on-disk caching strategy, the cache TTL is determined by value from the response header `Expires` or `Cache-Control`. If none of these headers is present or if APISIX returns `502 Bad Gateway` or `504 Gateway Timeout` due to unavailable Upstreams, the cache TTL defaults to the value configured in the [configuration files](#static-configuration).

Create a Route with the `proxy-cache` Plugin to cache data on disk:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-cache-route",
    "uri": "/anything",
    "plugins": {
      "proxy-cache": {
        "cache_strategy": "disk"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should see an `HTTP/1.1 200 OK` response with the following header, showing the Plugin is successfully enabled:

```text
Apisix-Cache-Status: MISS
```

As there is no cache available before the first response, `Apisix-Cache-Status: MISS` is shown.

Send the same request again within the cache TTL window. You should see an `HTTP/1.1 200 OK` response with the following headers, showing the cache is hit:

```text
Apisix-Cache-Status: HIT
```

Wait for the cache to expire after the TTL and send the same request again. You should see an `HTTP/1.1 200 OK` response with the following headers, showing the cache has expired:

```text
Apisix-Cache-Status: EXPIRED
```

### Cache Data in Memory

In-memory caching strategy offers the advantage of low-latency access to the cached data, as retrieving data from RAM is faster than retrieving data from disk storage. It also works well for storing temporary data that does not need to be persisted long-term, allowing for efficient caching of frequently changing data.

The following example demonstrates how you can use `proxy-cache` Plugin on a Route to cache data in memory.

Create a Route with `proxy-cache` and configure it to use memory-based caching:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-cache-route",
    "uri": "/anything",
    "plugins": {
      "proxy-cache": {
        "cache_strategy": "memory",
        "cache_zone": "memory_cache",
        "cache_ttl": 10
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should see an `HTTP/1.1 200 OK` response with the following header, showing the Plugin is successfully enabled:

```text
Apisix-Cache-Status: MISS
```

As there is no cache available before the first response, `Apisix-Cache-Status: MISS` is shown.

Send the same request again within the cache TTL window. You should see an `HTTP/1.1 200 OK` response with the following headers, showing the cache is hit:

```text
Apisix-Cache-Status: HIT
```

### Cache Responses Conditionally

The following example demonstrates how you can configure the `proxy-cache` Plugin to conditionally cache responses.

Create a Route with the `proxy-cache` Plugin and configure the `no_cache` attribute, such that if at least one of the values of the URL parameter `no_cache` and header `no_cache` is not empty and is not equal to `0`, the response will not be cached:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-cache-route",
    "uri": "/anything",
    "plugins": {
      "proxy-cache": {
        "no_cache": ["$arg_no_cache", "$http_no_cache"]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

Send a few requests to the Route with the URL parameter `no_cache` value indicating cache bypass:

```shell
curl -i "http://127.0.0.1:9080/anything?no_cache=1"
```

You should receive `HTTP/1.1 200 OK` responses for all requests and observe the following header every time:

```text
Apisix-Cache-Status: EXPIRED
```

Send a few other requests to the Route with the URL parameter `no_cache` value being zero:

```shell
curl -i "http://127.0.0.1:9080/anything?no_cache=0"
```

You should receive `HTTP/1.1 200 OK` responses for all requests and start seeing the cache being hit:

```text
Apisix-Cache-Status: HIT
```

You can also specify the value in the `no_cache` header as such:

```shell
curl -i "http://127.0.0.1:9080/anything" -H "no_cache: 1"
```

The response should not be cached:

```text
Apisix-Cache-Status: EXPIRED
```

### Retrieve Responses from Cache Conditionally

The following example demonstrates how you can configure the `proxy-cache` Plugin to conditionally retrieve responses from cache.

Create a Route with the `proxy-cache` Plugin and configure the `cache_bypass` attribute, such that if at least one of the values of the URL parameter `bypass` and header `bypass` is not empty and is not equal to `0`, the response will not be retrieved from the cache:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-cache-route",
    "uri": "/anything",
    "plugins": {
      "proxy-cache": {
        "cache_bypass": ["$arg_bypass", "$http_bypass"]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

Send a request to the Route with the URL parameter `bypass` value indicating cache bypass:

```shell
curl -i "http://127.0.0.1:9080/anything?bypass=1"
```

You should see an `HTTP/1.1 200 OK` response with the following header:

```text
Apisix-Cache-Status: BYPASS
```

Send another request to the Route with the URL parameter `bypass` value being zero:

```shell
curl -i "http://127.0.0.1:9080/anything?bypass=0"
```

You should see an `HTTP/1.1 200 OK` response with the following header:

```text
Apisix-Cache-Status: MISS
```

You can also specify the value in the `bypass` header as such:

```shell
curl -i "http://127.0.0.1:9080/anything" -H "bypass: 1"
```

The cache should be bypassed:

```text
Apisix-Cache-Status: BYPASS
```

### Cache for 502 and 504 Error Response Code

When the Upstream services return server errors in the 500 range, `proxy-cache` Plugin will cache the responses if and only if the returned status is `502 Bad Gateway` or `504 Gateway Timeout`.

The following example demonstrates the behavior of `proxy-cache` Plugin when the Upstream service returns `504 Gateway Timeout`.

Create a Route with the `proxy-cache` Plugin and configure a dummy Upstream service:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "proxy-cache-route",
    "uri": "/timeout",
    "plugins": {
      "proxy-cache": { }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "12.34.56.78": 1
      }
    }
  }'
```

Generate a few requests to the Route:

```shell
seq 4 | xargs -I{} curl -I "http://127.0.0.1:9080/timeout"
```

You should see a response similar to the following:

```text
HTTP/1.1 504 Gateway Time-out
...
Apisix-Cache-Status: MISS

HTTP/1.1 504 Gateway Time-out
...
Apisix-Cache-Status: HIT

HTTP/1.1 504 Gateway Time-out
...
Apisix-Cache-Status: HIT

HTTP/1.1 504 Gateway Time-out
...
Apisix-Cache-Status: HIT
```

However, if the Upstream services returns `503 Service Temporarily Unavailable`, the response will not be cached.
