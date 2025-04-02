---
title: Credential
keywords:
  - APISIX
  - API 网关
  - 凭证
  - Credential
description: 本文介绍了 Apache APISIX Credential 对象的作用以及如何使用 Credential。
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

Credential 是存放 [Consumer](./consumer.md) 凭证配置的对象。
一个 Consumer 可以使用不同类型的多个凭证。
当你需要为一个 Consumer 配置不同类型的多个凭证时，就会用到 Credential。

目前，Credential 可以配置的身份认证插件包括 `basic-auth`、`hmac-auth`、`jwt-auth` 以及 `key-auth`。

## 配置选项

 定义 Credential 的字段如下：

| 名称      | 必选项 | 描述                                                  |
|---------|-----|-----------------------------------------------------|
| desc    | 否   | Credential 描述。                                      |
| labels  | 否   | Credential 标签。                                      |
| plugins | 否   | Credential 对应的插件配置。详细信息，请参考 [Plugins](./plugin.md)。 |

:::note

如需了解更多关于 Credential 对象的信息，你可以参考 [Admin API Credential](../admin-api.md#credential) 资源介绍。

:::

## 使用示例

[Consumer 使用示例](./consumer.md#使用示例) 介绍了如何对 Consumer 配置认证插件，并介绍了如何配合其他插件使用。
在该示例中，该 Consumer 只有一个 key-auth 类型的凭证。
现在假设用户需要为该 Consumer 配置多个凭证，你可以使用 Credential 来支持这一点。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

1. 创建 Consumer。不指定认证插件，而是稍后使用 Credential 来配置认证插件。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "username": "jack"
    }'
    ```

2. 为 Consumer 配置 2 个 启用 `key-auth` 的 Credential。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials/key-auth-one \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "plugins": {
            "key-auth": {
                "key": "auth-one"
            }
        }
    }'
    ```

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials/key-auth-two \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "plugins": {
            "key-auth": {
                "key": "auth-two"
            }
        }
    }'
    ```

3. 创建路由，设置路由规则和启用插件配置。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "plugins": {
            "key-auth": {}
        },
        "upstream": {
            "nodes": {
                "127.0.0.1:1980": 1
            },
            "type": "roundrobin"
        },
        "uri": "/hello"
    }'
    ```

4. 测试插件

    分别使用 `auth-one` 和 `auth-two` 两个 key 来测试请求，都响应正常。

    ```shell
    curl http://127.0.0.1:9080/hello -H 'apikey: auth-one' -I
    curl http://127.0.0.1:9080/hello -H 'apikey: auth-two' -I
    ```

    为该 Consumer 启用 `limit-count` 插件。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/consumers \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "username": "jack",
        "plugins": {
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        }
    }'
    ```

    分别使用这两个 key 连续 3 次以上请求该路由，测试返回 `503`，请求被限制。
