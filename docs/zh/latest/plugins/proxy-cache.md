---
title: proxy-cache
keywords:
  - Apache APISIX
  - API 网关
  - Proxy Cache
description: proxy-cache 插件根据键缓存响应，支持 GET、POST 和 HEAD 请求的磁盘和内存缓存，从而增强 API 性能。
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

## 描述

`proxy-cache` 插件提供了根据缓存键缓存响应的功能。该插​​件支持基于磁盘和基于内存的缓存选项，用于缓存 [GET](https://anything.org/learn/serving-over-http/#get-request)、[POST](https://anything.org/learn/serving-over-http/#post-request) 和 [HEAD](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/HEAD) 请求。

可以根据请求 HTTP 方法、响应状态代码、请求标头值等有条件地缓存响应。

## 属性

| 名称               | 类型           | 必选项 | 默认值                    | 有效值                                                                          | 描述                                                                                                                               |
| ------------------ | -------------- | ------ | ------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| cache_strategy | string | 否 | disk | ["disk","memory"] | 缓存策略。缓存在磁盘还是内存中。 |
| cache_zone | string | 否 | disk_cache_one | | 与缓存策略一起使用的缓存区域。该值应与[配置文件](#static-configurations)中定义的缓存区域之一匹配，并与缓存策略相对应。例如，当使用内存缓存策略时，应该使用内存缓存区域。 |
| cache_key | array[string] | 否 | ["$host", "$request_uri"] | | 用于缓存的键。支持[NGINX 变量](https://nginx.org/en/docs/varindex.html)和值中的常量字符串。变量应该以 `$` 符号为前缀。 |
| cache_bypass | array[string] | 否 | | |一个或多个用于解析值的参数，如果任何值不为空且不等于 `0`，则不会从缓存中检索响应。支持值中的 [NGINX 变量](https://nginx.org/en/docs/varindex.html) 和常量字符串。变量应该以 `$` 符号为前缀。|
| cache_method | array[string] | 否 | ["GET", "HEAD"] | ["GET", "POST", "HEAD"] | 应缓存响应的请求方法。|
| cache_http_status | array[integer] | 否 | [200, 301, 404] | [200, 599] | 应缓存响应的响应 HTTP 状态代码。|
| hide_cache_headers | boolean | 否 | false | | 如果为 true，则隐藏 `Expires` 和 `Cache-Control` 响应标头。|
| cache_control | boolean | 否 | false | | 如果为 true，则遵守 HTTP 规范中的 `Cache-Control` 行为。仅对内存中策略有效。 |
| no_cache | array[string] | 否 | | | 用于解析值的一个或多个参数，如果任何值不为空且不等于 `0`，则不会缓存响应。支持 [NGINX 变量](https://nginx.org/en/docs/varindex.html) 和值中的常量字符串。变量应以 `$` 符号为前缀。 |
| cache_ttl | integer | 否 | 300 | >=1 | 在内存中缓存时的缓存生存时间 (TTL)，以秒为单位。要调整在磁盘上缓存时的 TTL，请更新[配置文件](#static-configurations) 中的 `cache_ttl`。TTL 值与从上游服务收到的响应标头 [`Cache-Control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) 和 [`Expires`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Expires) 中的值一起评估。|

## 静态配置

默认情况下，磁盘缓存时的 `cache_ttl` 和缓存 `zones` 等值已在 [默认配置](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua) 中预先配置。

要自定义这些值，请将相应的配置添加到 `config.yaml`。例如：

```yaml
apisix:
  proxy_cache:
    cache_ttl: 10s  # 仅当 `Expires` 和 `Cache-Control` 响应标头均不存在，或者 APISIX 返回
                    # 由于上游不可用导致 `502 Bad Gateway` 或 `504 Gateway Timeout` 时
                    # 才会在磁盘上缓存时使用默认缓存 TTL
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

重新加载 APISIX 以使更改生效。

## 示例

以下示例演示了如何为不同场景配置 `proxy-cache`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 在磁盘上缓存数据

磁盘缓存策略具有系统重启时数据持久性以及与内存缓存相比具有更大存储容量的优势。它适用于优先考虑耐用性且可以容忍稍大的缓存访问延迟的应用程序。

以下示例演示了如何在路由上使用 `proxy-cache` 插件将数据缓存在磁盘上。

使用磁盘缓存策略时，缓存 TTL 由响应标头 `Expires` 或 `Cache-Control` 中的值确定。如果这些标头均不存在，或者 APISIX 由于上游不可用而返回 `502 Bad Gateway` 或 `504 Gateway Timeout`，则缓存 TTL 默认为 [配置文件](#static-configuration) 中配置的值。

使用 `proxy-cache` 插件创建路由以将数据缓存在磁盘上：

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

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该看到带有以下标头的 `HTTP/1.1 200 OK` 响应，表明插件已成功启用：

```text
Apisix-Cache-Status: MISS
```

由于在第一次响应之前没有可用的缓存，因此显示 `Apisix-Cache-Status: MISS`。

在缓存 TTL 窗口内再次发送相同的请求。您应该看到带有以下标头的 `HTTP/1.1 200 OK` 响应，显示缓存已命中：

```text
Apisix-Cache-Status: HIT
```

等待缓存在 TTL 之后过期，然后再次发送相同的请求。您应该看到带有以下标头的 `HTTP/1.1 200 OK` 响应，表明缓存已过期：

```text
Apisix-Cache-Status: EXPIRED
```

### 在内存中缓存数据

内存缓存策略具有低延迟访问缓存数据的优势，因为从 RAM 检索数据比从磁盘存储检索数据更快。它还适用于存储不需要长期保存的临时数据，从而可以高效缓存频繁更改的数据。

以下示例演示了如何在路由上使用 `proxy-cache` 插件在内存中缓存数据。

使用 `proxy-cache` 创建路由并将其配置为使用基于内存的缓存：

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

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该看到带有以下标头的 `HTTP/1.1 200 OK` 响应，表明插件已成功启用：

```text
Apisix-Cache-Status: MISS
```

由于在第一次响应之前没有可用的缓存，因此显示 `Apisix-Cache-Status: MISS`。

在缓存 TTL 窗口内再次发送相同的请求。您应该看到带有以下标头的 `HTTP/1.1 200 OK` 响应，显示缓存已命中：

```text
Apisix-Cache-Status: HIT
```

### 有条件地缓存响应

以下示例演示了如何配置 `proxy-cache` 插件以有条件地缓存响应。

使用 `proxy-cache` 插件创建路由并配置 `no_cache` 属性，这样如果 URL 参数 `no_cache` 和标头 `no_cache` 的值中至少有一个不为空且不等于 `0`，则不会缓存响应：

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

向路由发送一些请求，其中 URL 参数的 `no_cache` 值表示绕过缓存：

```shell
curl -i "http://127.0.0.1:9080/anything?no_cache=1"
```

您应该收到所有请求的 `HTTP/1.1 200 OK` 响应，并且每次都观察到以下标头：

```text
Apisix-Cache-Status: EXPIRED
```

向路由发送一些其他请求，其中 URL 参数 `no_cache` 值为零：

```shell
curl -i "http://127.0.0.1:9080/anything?no_cache=0"
```

您应该收到所有请求的 `HTTP/1.1 200 OK` 响应，并开始看到缓存被命中：

```text
Apisix-Cache-Status: HIT
```

您还可以在 `no_cache` 标头中指定以下值：

```shell
curl -i "http://127.0.0.1:9080/anything" -H "no_cache: 1"
```

响应不应该被缓存：

```text
Apisix-Cache-Status: EXPIRED
```

### 有条件地从缓存中检索响应

以下示例演示了如何配置 `proxy-cache` 插件以有条件地从缓存中检索响应。

使用 `proxy-cache` 插件创建路由并配置 `cache_bypass` 属性，这样如果 URL 参数 `bypass` 和标头 `bypass` 的值中至少有一个不为空且不等于 `0`，则不会从缓存中检索响应：

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

向路由发送一个请求，其中 URL 参数值为 `bypass`，表示绕过缓存：

```shell
curl -i "http://127.0.0.1:9080/anything?bypass=1"
```

您应该看到带有以下标头的 `HTTP/1.1 200 OK` 响应：

```text
Apisix-Cache-Status: BYPASS
```

向路由发送另一个请求，其中 URL 参数 `bypass` 值为零：

```shell
curl -i "http://127.0.0.1:9080/anything?bypass=0"
```

您应该看到带有以下标头的 `HTTP/1.1 200 OK` 响应：

```text
Apisix-Cache-Status: MISS
```

您还可以在 `bypass` 标头中指定以下值：

```shell
curl -i "http://127.0.0.1:9080/anything" -H "bypass: 1"
```

响应应该显示绕过缓存：

```text
Apisix-Cache-Status: BYPASS
```

### 缓存 502 和 504 错误响应代码

当上游服务返回 500 范围内的服务器错误时，`proxy-cache` 插件将缓存响应，当且仅当返回的状态为 `502 Bad Gateway` 或 `504 Gateway Timeout`。

以下示例演示了当上游服务返回 `504 Gateway Timeout` 时 `proxy-cache` 插件的行为。

使用 `proxy-cache` 插件创建路由并配置虚拟上游服务：

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

生成一些对路由的请求：

```shell
seq 4 | xargs -I{} curl -I "http://127.0.0.1:9080/timeout"
```

您应该会看到类似以下内容的响应：

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

但是，如果上游服务返回 `503 Service Temporarily Unavailable`，则响应将不会被缓存。
