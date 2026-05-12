---
title: acl
keywords:
  - Apache APISIX
  - API Gateway
  - 插件
  - acl
description: acl 插件基于标签实现访问控制，通过检查消费者标签或外部用户属性来允许或拒绝请求。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/acl" />
</head>

## 描述

`acl` 插件为 API 路由提供基于标签的访问控制。它检查 APISIX [消费者](../terminology/consumer.md)的标签，或来自外部认证插件（设置了 `ctx.external_user`）的用户属性，并与配置的允许列表或拒绝列表进行比对。

插件支持三种标签值格式：

- **table**：标签值为 Lua 表（数组）。
- **json**：标签值为 JSON 编码的数组字符串，例如 `["admin","user"]`。
- **segmented_text**：标签值为分隔符分隔的字符串，例如 `admin,user`。

`allow_labels` 和 `deny_labels` 至少需配置其中一个。当两者同时存在时，先评估 `deny_labels`。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| allow_labels | object | 否* | | | 允许的标签。键为标签名，值为允许的标签值数组。`allow_labels` 和 `deny_labels` 至少需配置其中一个。 |
| deny_labels | object | 否* | | | 拒绝的标签。键为标签名，值为拒绝的标签值数组。`allow_labels` 和 `deny_labels` 至少需配置其中一个。 |
| rejected_code | integer | 否 | 403 | >= 200 | 请求被拒绝时返回的 HTTP 状态码。 |
| rejected_msg | string | 否 | | | 自定义拒绝消息体。若未设置，默认返回 `{"message":"The consumer is forbidden."}`。 |
| external_user_label_field | string | 否 | `groups` | | 用于从 `ctx.external_user` 提取标签值的 JSONPath 表达式。 |
| external_user_label_field_key | string | 否 | | | 提取值所使用的标签键名。默认为 `external_user_label_field` 的值。 |
| external_user_label_field_parser | string | 否 | | `segmented_text`、`json`、`table` | 提取字段值的解析方式。若未设置，插件自动检测格式。 |
| external_user_label_field_separator | string | 否 | | | `segmented_text` 解析器使用的分隔符（正则表达式）。当 `external_user_label_field_parser` 为 `segmented_text` 时必填。 |

## 示例

以下示例演示了如何为不同场景配置 `acl` 插件。

:::note

可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 按标签允许消费者

以下示例演示如何将 `acl` 插件与 [`key-auth`](./key-auth.md) 结合使用，仅允许具有特定标签值的消费者访问。

创建消费者 `alice`，标签为 `team: platform`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "alice",
    "plugins": {
      "key-auth": {
        "key": "alice-key"
      }
    },
    "labels": {
      "team": "platform"
    }
  }'
```

创建第二个消费者 `bob`，标签为 `team: sales`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "bob",
    "plugins": {
      "key-auth": {
        "key": "bob-key"
      }
    },
    "labels": {
      "team": "sales"
    }
  }'
```

创建启用了 `key-auth` 和 `acl` 的路由，仅允许标签 `team: platform` 的消费者访问：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "acl-allow-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "acl": {
        "allow_labels": {
          "team": ["platform"]
        }
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

以 `alice`（标签 `team: platform`）的身份发送请求：

```shell
curl "http://127.0.0.1:9080/get" \
  -H "apikey: alice-key"
```

由于 `alice` 具有允许的标签，应收到 HTTP `200` 响应。

以 `bob`（标签 `team: sales`）的身份发送请求：

```shell
curl "http://127.0.0.1:9080/get" \
  -H "apikey: bob-key"
```

由于 `bob` 不具备允许的标签，应收到 HTTP `403` 响应。

### 按标签拒绝消费者

以下示例演示如何基于标签值拒绝特定消费者，同时允许其他消费者访问。

创建消费者 `carol`，标签为 `role: guest`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "carol",
    "plugins": {
      "key-auth": {
        "key": "carol-key"
      }
    },
    "labels": {
      "role": "guest"
    }
  }'
```

创建路由，拒绝标签 `role: guest` 的消费者访问：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "acl-deny-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "acl": {
        "deny_labels": {
          "role": ["guest"]
        }
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

以 `carol` 的身份发送请求：

```shell
curl "http://127.0.0.1:9080/get" \
  -H "apikey: carol-key"
```

应收到 HTTP `403` 响应。

### 自定义拒绝状态码和消息

可以自定义访问被拒绝时返回的 HTTP 状态码和消息。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "acl-custom-reject-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "acl": {
        "allow_labels": {
          "team": ["platform"]
        },
        "rejected_code": 401,
        "rejected_msg": "Access denied: insufficient label permissions."
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

当不具备所需标签的消费者访问该路由时，将收到 `401` 响应和配置的消息。
