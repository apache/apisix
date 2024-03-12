---
title: proxy-cache
keywords:
  - APISIX
  - API 网关
  - Request Validation
description: 本文介绍了 Apache APISIX proxy-cache 插件的相关操作，你可以使用此插件缓存来自上游的响应。
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

## 描述

`proxy-cache` 插件提供缓存后端响应数据的能力，它可以和其他插件一起使用。该插件支持基于磁盘和内存的缓存。目前可以根据响应码和请求模式来指定需要缓存的数据，也可以通过 `no_cache` 和 `cache_bypass`属性配置更复杂的缓存策略。

## 属性

| 名称               | 类型           | 必选项 | 默认值                    | 有效值                                                                          | 描述                                                                                                                               |
| ------------------ | -------------- | ------ | ------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| cache_strategy     | string         | 否   | disk                      | ["disk","memory"]                                                               | 缓存策略，指定缓存数据存储在磁盘还是内存中。 |
| cache_zone         | string         | 否   | disk_cache_one     |                                                                                 | 指定使用哪个缓存区域，不同的缓存区域可以配置不同的路径，在 `conf/config.yaml` 文件中可以预定义使用的缓存区域。如果指定的缓存区域与配置文件中预定义的缓存区域不一致，那么缓存无效。   |
| cache_key          | array[string]  | 否   | ["$host", "$request_uri"] |                                                                                 | 缓存 key，可以使用变量。例如：`["$host", "$uri", "-cache-id"]`。                                                                        |
| cache_bypass       | array[string]  | 否   |                           |                                                                                 | 当该属性的值不为空或者非 `0` 时则会跳过缓存检查，即不在缓存中查找数据，可以使用变量，例如：`["$arg_bypass"]`。 |
| cache_method       | array[string]  | 否   | ["GET", "HEAD"]           | ["GET", "POST", "HEAD"] | 根据请求 method 决定是否需要缓存。                                                                                                     |
| cache_http_status  | array[integer] | 否   | [200, 301, 404]           | [200, 599]                                                                      | 根据 HTTP 响应码决定是否需要缓存。                                                                                                         |
| hide_cache_headers | boolean        | 否   | false                     |                                                                                 | 当设置为 `true` 时不将 `Expires` 和 `Cache-Control` 响应头返回给客户端。                                                                                 |
| cache_control      | boolean        | 否   | false                     |                                                                                 | 当设置为 `true` 时遵守 HTTP 协议规范中的 `Cache-Control` 的行为。                                 |
| no_cache           | array[string]  | 否   |                           |                                                                                 | 当此参数的值不为空或非 `0` 时将不会缓存数据，可以使用变量。                                                      |
| cache_ttl          | integer        | 否   | 300 秒                    |                                                                                 | 当选项 `cache_control` 未开启或开启以后服务端没有返回缓存控制头时，提供的默认缓存时间。    |

:::note 注意

- 对于基于磁盘的缓存，不能动态配置缓存的过期时间，只能通过后端服务响应头 `Expires` 或 `Cache-Control` 来设置过期时间，当后端响应头中没有 `Expires` 或 `Cache-Control` 时，默认缓存时间为 10 秒钟
- 当上游服务不可用时，APISIX 将返回 `502` 或 `504` HTTP 状态码，默认缓存时间为 10 秒钟；
- 变量以 `$` 开头，不存在时等价于空字符串。也可以使用变量和字符串的结合，但是需要以数组的形式分开写，最终变量被解析后会和字符串拼接在一起。

:::

## 启用插件

你可以在 APISIX 配置文件 `conf/config.yaml` 中添加你的缓存配置，示例如下：

```yaml title="conf/config.yaml"
apisix:
  proxy_cache:
    cache_ttl: 10s  # 如果上游未指定缓存时间，则为默认磁盘缓存时间
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

### 使用基于磁盘的缓存

以下示例展示了如何在路由上启用 `proxy-cache` 插件。该插件默认使用基于磁盘的 `cache_strategy` 和默认使用`disk_cache_one` 为 `cache_zone`：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

### 使用基于内存的缓存

以下示例展示了如何在路由上启用 `proxy-cache` 插件，并使用基于内存的 `cache_strategy` 和相应的基于内存的 `cache_zone`。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## 测试插件

按上述配置启用插件后，使用 `curl` 命令请求该路由：

```shell
curl http://127.0.0.1:9080/ip -i
```

如果返回 `200` HTTP 状态码，并且响应头中包含 `Apisix-Cache-Status`字段，则表示该插件已启用：

```shell
HTTP/1.1 200 OK
···
Apisix-Cache-Status: MISS

hello
```

如果你是第一次请求该路由，数据未缓存，那么 `Apisix-Cache-Status` 字段应为 `MISS`。此时再次请求该路由：

```shell
curl http://127.0.0.1:9080/ip -i
```

如果返回的响应头中 `Apisix-Cache-Status` 字段变为 `HIT`，则表示数据已被缓存，插件生效：

```shell
HTTP/1.1 200 OK
···
Apisix-Cache-Status: HIT

hello
```

如果你设置 `"cache_zone": "invalid_disk_cache"` 属性为无效值，即与配置文件 `conf/config.yaml` 中指定的缓存区域不一致，那么它将返回 `404` HTTP 响应码。

:::tip 提示

为了清除缓存数据，你只需要指定请求的 method 为 `PURGE`：

```shell
curl -i http://127.0.0.1:9080/ip -X PURGE
```

HTTP 响应码为 `200` 即表示删除成功，如果缓存的数据未找到将返回 `404`：

```shell
HTTP/1.1 200 OK
```

:::

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
