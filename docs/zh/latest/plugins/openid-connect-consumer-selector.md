---
title: openid-connect-consumer-selector
keywords:
  - Apache APISIX
  - API 网关
  - OpenID Connect
  - OIDC
  - openid-connect-consumer-selector
description: openid-connect-consumer-selector 插件为每个请求选择 openid-connect 的 IdP 配置（discovery/client_id/client_secret），使单个 Route 可以在不硬编码特定提供商路由逻辑的情况下服务多个 OpenID Connect 领域（realm）、租户或域名。
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

`openid-connect-consumer-selector` 插件根据将某个值与一组已配置条目进行匹配，为请求选择一个已命名的 [`openid-connect`](./openid-connect.md) IdP 配置。它应当在同一 Route 上以比 `openid-connect` 更高的优先级运行，从而使单个 Route 可以服务多个 IdP 配置（例如多个领域、租户或域名），而无需将任何特定提供商的路由逻辑硬编码进 `openid-connect` 本身。

该插件本身不执行任何身份验证——它只是通过将 `discovery`、`client_id` 和 `client_secret` 的值暴露为 `oidc_discovery`、`oidc_client_id` 和 `oidc_client_secret` 请求上下文变量，来选择当前请求应使用哪些值。`openid-connect` 的相应字段必须使用 `${var}` 模板引用这些变量（参见 [`openid-connect`](./openid-connect.md) 文档中的「按请求选择 IdP 配置」一节）。

待匹配的值来自以下两种来源之一，通过 `match_source` 选择：

- `var`（默认值）：由 `match_var` 指定名称的任意请求上下文变量。
- `token_iss`：传入 `Authorization` 请求头中承载令牌（bearer token）的 `iss` claim，解码时不验证其签名——真正的签名验证仍然在下游的 `openid-connect` 中针对最终选中的配置进行。由于该模式需要请求上已经携带承载令牌，它只在客户端已经带着令牌调用时才能匹配；对于交互式浏览器登录（`bearer_only: false`）流程中未经身份验证的首个请求，它无法为其选择配置。

## 属性

| 名称 | 类型 | 必选项 | 描述 |
|------|------|----------|-------------|
| match_source | string | 否 | `"var"`（默认）或 `"token_iss"`——参见上文。 |
| match_var | string | 仅当 `match_source` 为 `"var"` 时必选 | 要读取的请求上下文变量名称（例如 `http_x_tenant_id`），用于与每个 `configs` 条目的 `key` 匹配。 |
| configs | array | 是 | 候选 IdP 配置列表。第一个 `key` 等于解析出的匹配值的条目将被选中。 |
| configs[].key | string | 是 | 用于与解析出的匹配值比较的值——例如租户 ID（`var` 模式）或颁发者 URL（`token_iss` 模式）。 |
| configs[].discovery | string | 是 | 该条目对应的 discovery URL。 |
| configs[].client_id | string | 是 | 该条目对应的 client ID。 |
| configs[].client_secret | string | 是 | 该条目对应的 client secret。与 `openid-connect` 自身的 `client_secret` 一样，会加密存储。 |

如果匹配值解析出的结果没有匹配到任何 `configs` 条目（包括该变量本身缺失或无法读取的情况），该插件不会设置任何内容，`openid-connect` 会因其自身的 `${var}` 模板解析为空而以 `500` 响应失败关闭。

`configs[].key` 起到白名单的作用：只有 Route 管理员显式配置过的值才能选中某个配置，因此该插件可以安全地用于 `match_var` 来源于不受信任客户端可控内容（例如某个请求头）的场景。不要在没有经过这个白名单的情况下，直接用客户端可控的变量来模板化 `openid-connect` 的 `discovery` 字段——未经验证的 `${var}` 模板化 `discovery` URL 可能被指向任意主机（SSRF）。

## 启用插件

将两个插件都添加到同一个 Route 上，由 `openid-connect-consumer-selector` 提供 `openid-connect` 模板所引用的值——完整配置参见下方的[示例](#示例)。

## 示例

```json
{
  "plugins": {
    "openid-connect-consumer-selector": {
      "match_var": "http_x_tenant_id",
      "configs": [
        {
          "key": "acme",
          "discovery": "https://idp-acme.example.com/.well-known/openid-configuration",
          "client_id": "acme-client",
          "client_secret": "acme-secret"
        },
        {
          "key": "globex",
          "discovery": "https://idp-globex.example.com/.well-known/openid-configuration",
          "client_id": "globex-client",
          "client_secret": "globex-secret"
        }
      ]
    },
    "openid-connect": {
      "discovery": "${oidc_discovery}",
      "client_id": "${oidc_client_id}",
      "client_secret": "${oidc_client_secret}",
      "redirect_uri": "https://example.com/protected/.apisix/redirect",
      "session": {
        "secret": "some-strong-random-secret"
      }
    }
  }
}
```

改为根据承载令牌的颁发者选择（适用于 `bearer_only` 的 Route）——Route 结构与上面相同，`openid-connect-consumer-selector` 的配置改为：

```json
{
  "match_source": "token_iss",
  "configs": [
    {
      "key": "https://idp-acme.example.com/realms/acme",
      "discovery": "https://idp-acme.example.com/realms/acme/.well-known/openid-configuration",
      "client_id": "acme-client",
      "client_secret": "acme-secret"
    }
  ]
}
```

`openid-connect` 则配置为 `"bearer_only": true`，而不是 `session`。
