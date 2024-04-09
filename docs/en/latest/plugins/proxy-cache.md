---
title: proxy-cache
keywords:
  - Apache APISIX
  - API Gateway
  - Proxy Cache
description: This document contains information about the Apache APISIX proxy-cache Plugin, you can use it to cache the response from the Upstream.
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

The `proxy-cache` Plugin can be used to cache the response from the Upstream. It can be used with other Plugins and currently supports disk-based and memory-based caching.

The data to be cached can be filtered with response codes, request modes, or more complex methods using the `no_cache` and `cache_bypass` attributes.

## Attributes

| Name               | Type           | Required | Default                   | Valid values            | Description                                                                                                                                                                                                                                                                                           |
|--------------------|----------------|----------|---------------------------|-------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| cache_strategy     | string         | False    | disk                      | ["disk","memory"]       | Specifies where the cached data should be stored.                                                                                                                                                                                                                                                     |
| cache_zone         | string         | False    | disk_cache_one            |                         | Specifies which cache area to use. Each cache area can be configured with different paths. Cache areas can be predefined in your configuration file (`conf/config.yaml`). If the specified cache area is inconsistent with the pre-defined cache area in your configuration file, the cache is invalid. |
| cache_key          | array[string]  | False    | ["$host", "$request_uri"] |                         | Key to use for caching. For example, `["$host", "$uri", "-cache-id"]`.                                                                                                                                                                                                                                |
| cache_bypass       | array[string]  | False    |                           |                         | Conditions in which response from cache is bypassed. Whether to skip cache retrieval. If at least one value of the string parameters is not empty and is not equal to `0` then the response will not be taken from the cache. For example, `["$arg_bypass"]`.                                         |
| cache_method       | array[string]  | False    | ["GET", "HEAD"]           | ["GET", "POST", "HEAD"] | Request methods for which the response will be cached.                                                                                                                                                                                                                                                |
| cache_http_status  | array[integer] | False    | [200, 301, 404]           | [200, 599]              | HTTP status codes of the Upstream response for which the response will be cached.                                                                                                                                                                                                                     |
| hide_cache_headers | boolean        | False    | false                     |                         | When set to `true`, hide the `Expires` and `Cache-Control` response headers.                                                                                                                                                                                                               |
| cache_control      | boolean        | False    | false                     |                         | When set to `true`, complies with Cache-Control behavior in the HTTP specification. Used only for memory strategy.                                                                                                                                                                                      |
| no_cache           | array[string]  | False    |                           |                         | Conditions in which the response will not be cached. If at least one value of the string parameters is not empty and is not equal to `0` then the response will not be saved.                                                                                                                         |
| cache_ttl          | integer        | False    | 300 seconds               |                         | Time that a response is cached until it is deleted or refreshed. Comes in to effect when the `cache_control` attribute is not enabled or the proxied server does not return cache header. Used only for memory strategy.                                                                              |

:::note

- The cache expiration time cannot be configured dynamically. It can only be set by the Upstream response header `Expires` or `Cache-Control`. The default expiration time is 10s if there is no `Expires` or `Cache-Control` in the Upstream response header.
- If the Upstream service is not available and APISIX returns a `502` or `504` status code, it will be cached for 10s.
- Variables (start with `$`) can be specified in `cache_key`, `cache_bypass` and `no_cache`. It's worth mentioning that the variable value will be an empty string if it doesn't exist.
- You can also combine a number of variables and strings (constants), by writing them into an array, eventually, variables will be parsed and stitched together with strings.

:::

## Enable Plugin

You can add your cache configuration in you APISIX configuration file (`conf/config.yaml`) as shown below:

```yaml title="conf/config.yaml"
apisix:
  proxy_cache:
    cache_ttl: 10s  # default cache TTL for caching on disk
    zones:
      - name: disk_cache_one
        memory_size: 50m
        disk_size: 1G
        disk_path: /tmp/disk_cache_one
        cache_levels: 1:2
    #   - name: disk_cache_two
    #     memory_size: 50m
    #     disk_size: 1G
    #     disk_path: "/tmp/disk_cache_two"
    #     cache_levels: "1:2"
      - name: memory_cache
        memory_size: 50m
```

### Use disk-based caching

You can enable the Plugin on a Route as shown below. The Plugin uses the disk-based `cache_strategy` and `disk_cache_one` as the `cache_zone` by default:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/ip",
    "plugins": {
        "proxy-cache": {
            "cache_key":  ["$uri", "-cache-id"],
            "cache_bypass": ["$arg_bypass"],
            "cache_method": ["GET"],
            "cache_http_status": [200],
            "hide_cache_headers": true,
            "no_cache": ["$arg_test"]
        }
    },
    "upstream": {
        "nodes": {
            "httpbin.org": 1
        },
        "type": "roundrobin"
    }
}'
```

### Use memory-based caching

You can enable the Plugin on a Route with in-memory `cache_strategy` and a corresponding in-memory `cache_zone` as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/ip",
    "plugins": {
        "proxy-cache": {
            "cache_strategy": "memory",
            "cache_zone": "memory_cache",
            "cache_ttl": 10
        }
    },
    "upstream": {
        "nodes": {
            "httpbin.org": 1
        },
        "type": "roundrobin"
    }
}'
```

## Example usage

Once you have configured the Plugin as shown above, you can make an initial request:

```shell
curl http://127.0.0.1:9080/ip -i
```

```shell
HTTP/1.1 200 OK
···
Apisix-Cache-Status: MISS

hello
```

The `Apisix-Cache-Status` in the response shows `MISS` meaning that the response is not cached, as expected. Now, if you make another request, you will see that you get a cached response:

```shell
curl http://127.0.0.1:9080/ip -i
```

```shell
HTTP/1.1 200 OK
···
Apisix-Cache-Status: HIT

hello
```

If you set `"cache_zone": "invalid_disk_cache"` attribute to an invalid value (cache not configured in the your configuration file), then it will return a `404` response.

:::tip

To clear the cached data, you can send a request with `PURGE` method:

```shell
curl -i http://127.0.0.1:9080/ip -X PURGE
```

```shell
HTTP/1.1 200 OK
```

If the response code is `200`, the deletion is successful. If the cached data is not found, a `404` response code will be returned.

:::

## Delete Plugin

To remove the `proxy-cache` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/ip",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```
