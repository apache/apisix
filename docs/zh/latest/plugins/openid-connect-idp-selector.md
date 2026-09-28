---
title: openid-connect-idp-selector
keywords:
  - Apache APISIX
  - API 网关
  - OpenID Connect
  - OIDC
  - openid-connect-idp-selector
description: openid-connect-idp-selector 插件为每个请求选择 openid-connect 的 IdP 配置（discovery/client_id/client_secret），使单个 Route 可以在不硬编码特定提供商路由逻辑的情况下服务多个 OpenID Connect 领域（realm）、租户或域名。
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

`openid-connect-idp-selector` 插件根据将某个值与一组已配置条目进行匹配，为请求选择一个已命名的 [`openid-connect`](./openid-connect.md) IdP 配置。它应当在同一 Route 上以比 `openid-connect` 更高的优先级运行，从而使单个 Route 可以服务多个 IdP 配置（例如多个领域、租户或域名），而无需将任何特定提供商的路由逻辑硬编码进 `openid-connect` 本身。

该插件本身不执行任何身份验证——它只是通过将 `discovery`、`client_id` 和 `client_secret` 的值暴露为 `oidc_discovery`、`oidc_client_id` 和 `oidc_client_secret` 请求上下文变量，来选择当前请求应使用哪些值。`openid-connect` 的相应字段必须使用 `${var}` 模板引用这些变量（参见 [`openid-connect`](./openid-connect.md) 文档中的「按请求选择 IdP 配置」一节）。

待匹配的值是传入 `Authorization` 请求头中承载令牌（bearer token）的 `iss` claim，解码时不验证其签名——真正的签名验证仍然在下游的 `openid-connect` 中针对最终选中的配置进行。由于这需要请求上已经携带承载令牌，它只在客户端已经带着令牌调用时才能匹配；对于交互式浏览器登录（`bearer_only: false`）流程中未经身份验证的首个请求，它无法为其选择配置——请在 `bearer_only: true` 的 Route 上使用它。

## 属性

| 名称 | 类型 | 必选项 | 描述 |
|------|------|----------|-------------|
| configs | array | 是 | 候选 IdP 配置列表。第一个 `key` 等于令牌 `iss` claim 的条目将被选中。 |
| configs[].key | string | 是 | 用于与令牌 `iss` claim 比较的颁发者 URL。 |
| configs[].discovery | string | 是 | 该条目对应的 discovery URL。 |
| configs[].client_id | string | 是 | 该条目对应的 client ID。 |
| configs[].client_secret | string | 是 | 该条目对应的 client secret。与 `openid-connect` 自身的 `client_secret` 一样，会加密存储。 |

如果令牌的颁发者没有匹配到任何 `configs` 条目（包括根本没有承载令牌的情况），该插件不会设置任何内容，`openid-connect` 会因其自身的 `${var}` 模板解析为空而以 `500` 响应失败关闭。

`configs[].key` 起到白名单的作用：只有 Route 管理员显式配置过的颁发者才能选中某个配置。

## 启用插件

将两个插件都添加到同一个 Route 上，由 `openid-connect-idp-selector` 提供 `openid-connect` 模板所引用的值——完整配置参见下方的[示例](#示例)。

## 示例

```json
{
  "plugins": {
    "openid-connect-idp-selector": {
      "configs": [
        {
          "key": "https://idp-acme.example.com/realms/acme",
          "discovery": "https://idp-acme.example.com/realms/acme/.well-known/openid-configuration",
          "client_id": "acme-client",
          "client_secret": "acme-secret"
        },
        {
          "key": "https://idp-globex.example.com/realms/globex",
          "discovery": "https://idp-globex.example.com/realms/globex/.well-known/openid-configuration",
          "client_id": "globex-client",
          "client_secret": "globex-secret"
        }
      ]
    },
    "openid-connect": {
      "discovery": "${oidc_discovery}",
      "client_id": "${oidc_client_id}",
      "client_secret": "${oidc_client_secret}",
      "bearer_only": true
    }
  }
}
```
