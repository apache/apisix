---
title: Upstream
keywords:
  - APISIX
  - API 网关
  - 上游
  - Upstream
description: 本文介绍了 Apache APISIX Upstream 对象的作用以及如何使用 Upstream。
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

Upstream（也称之为上游）是对虚拟主机抽象，即应用层服务或节点的抽象。你可以通过 Upstream 对象对多个服务节点按照配置规则进行负载均衡。

上游的地址信息可以直接配置到[路由](./route.md)（或[服务](./service.md)）中。

![Upstream 示例](../../../assets/images/upstream-example.png)

如上图所示，当多个路由（或服务）使用该上游时，你可以单独创建上游对象，在路由中通过使用 `upstream_id` 的方式引用资源，减轻维护压力。

你也可以将上游的信息直接配置在指定路由或服务中，不过路由中的配置优先级更高，优先级行为与[插件](./plugin.md) 非常相似。

## 配置参数

APISIX 的 Upstream 对象除了基本的负载均衡算法外，还支持对上游做主被动健康检查、重试等逻辑。更多信息，请参考 [Admin API 中的 Upstream 资源](../admin-api.md#upstream)。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

1. 创建上游对象用例。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/upstreams/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "type": "chash",
        "key": "remote_addr",
        "nodes": {
            "127.0.0.1:80": 1,
            "httpbin.org:80": 2
        }
    }'
    ```

    上游对象创建后，可以被路由或服务引用。

2. 在路由中使用创建的上游对象。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "uri": "/index.html",
        "upstream_id": 1
    }'
    ```

3. 为方便使用，你也可以直接把上游信息直接配置在某个路由或服务。

以下示例是将上游信息直接配置在路由中：

```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "uri": "/index.html",
        "plugins": {
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        },
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
    }'
```

## 使用示例

- 配置健康检查的示例。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "uri": "/index.html",
        "plugins": {
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        },
        "upstream": {
            "nodes": {
                "127.0.0.1:1980": 1
            }
            "type": "roundrobin",
            "retries": 2,
            "checks": {
                "active": {
                    "http_path": "/status",
                    "host": "foo.com",
                    "healthy": {
                        "interval": 2,
                        "successes": 1
                    },
                    "unhealthy": {
                        "interval": 1,
                        "http_failures": 2
                    }
                }
            }
        }
    }'
    ```

    更多信息，请参考[健康检查的文档](../tutorials/health-check.md)。

以下是使用不同 [`hash_on`](../admin-api.md#upstream-body-request-methods) 类型的配置示例：

### Consumer

1. 创建一个 Consumer 对象。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "username": "jack",
        "plugins": {
        "key-auth": {
            "key": "auth-jack"
            }
        }
    }'
    ```

2. 创建路由，启用 `key-auth` 插件，配置 `upstream.hash_on` 的类型为 `consumer`。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "plugins": {
            "key-auth": {}
        },
        "upstream": {
            "nodes": {
                "127.0.0.1:1980": 1,
                "127.0.0.1:1981": 1
            },
            "type": "chash",
            "hash_on": "consumer"
        },
        "uri": "/server_port"
    }'
    ```

3. 测试请求，认证通过后的 `consumer_name` 将作为负载均衡哈希算法的哈希值。

    ```shell
    curl http://127.0.0.1:9080/server_port -H "apikey: auth-jack"
    ```

### Cookie

1. 创建路由并配置 `upstream.hash_on` 的类型为 `cookie`。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "uri": "/hash_on_cookie",
        "upstream": {
            "key": "sid",
            "type": "chash",
            "hash_on": "cookie",
            "nodes": {
                "127.0.0.1:1980": 1,
                "127.0.0.1:1981": 1
            }
        }
    }'
    ```

2. 客户端请求携带 `Cookie`。

    ```shell
    curl http://127.0.0.1:9080/hash_on_cookie \
    -H "X-API-KEY: $admin_key" \
    -H "Cookie: sid=3c183a30cffcda1408daf1c61d47b274"
    ```

### Header

1. 创建路由并配置 `upstream.hash_on` 的类型为 `header`，`key` 为 `content-type`。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "uri": "/hash_on_header",
        "upstream": {
            "key": "content-type",
            "type": "chash",
            "hash_on": "header",
            "nodes": {
                "127.0.0.1:1980": 1,
                "127.0.0.1:1981": 1
            }
        }
    }'
    ```

2. 客户端请求携带 `content-type` 的 `header`。

```shell
 curl http://127.0.0.1:9080/hash_on_header \
 -H "X-API-KEY: $admin_key" \
 -H "Content-Type: application/json"
```
