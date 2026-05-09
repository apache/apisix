---
title: saml-auth
keywords:
  - Apache APISIX
  - API 网关
  - SAML
  - SAML 2.0
  - SSO
  - 单点登录
description: saml-auth 插件为 API 路由提供 SAML 2.0 身份验证，可与 Keycloak、Okta、Azure Active Directory 等外部身份提供商集成。
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

`saml-auth` 插件为 API 路由提供 [SAML 2.0](https://docs.oasis-open.org/security/saml/Post2.0/sstc-saml-tech-overview-2.0.html)（安全断言标记语言）身份验证。该插件充当 SAML 服务提供商（SP），并与 Keycloak、Okta、Azure Active Directory 等外部身份提供商（IdP）集成，在允许访问上游资源之前对用户进行身份验证。

当请求到达受保护的路由时，插件会检查是否存在有效的 SAML 会话。若没有会话，则将用户重定向到 IdP 进行身份验证。用户在 IdP 完成认证后，IdP 会将签名的 SAML 断言以 POST 方式发送到 SP 的断言消费者服务（ACS）URL。插件验证断言后，为用户建立会话。

该插件支持：

- **HTTP-Redirect 绑定**（默认）— SAML 消息以 URL 查询参数形式传输。
- **HTTP-POST 绑定** — SAML 消息以 HTML 表单值形式传输。
- **单点注销（SLO）** — 注销请求可由 SP 或 IdP 发起。
- 通过 `secret_fallbacks` 实现**会话密钥轮换**。

经过身份验证的用户数据存储在 `ctx.external_user` 中，可供 `acl` 等下游授权插件使用。

## 属性

| 名称 | 类型 | 必填 | 加密 | 默认值 | 有效值 | 描述 |
|------|------|------|------|--------|--------|------|
| sp_issuer | string | 是 | | | | 服务提供商（SP）实体 ID/颁发者 URI，必须与在 IdP 中注册的 SP 实体 ID 一致。 |
| idp_uri | string | 是 | | | | 身份提供商 SSO 端点 URL，SAML 认证请求将发送至此 URL。 |
| idp_cert | string | 是 | | | | PEM 格式的 IdP X.509 证书，用于验证 SAML 断言上的签名。 |
| login_callback_uri | string | 是 | | | | SP 的断言消费者服务（ACS）URL。IdP 在认证后将 SAML 响应 POST 到此 URL，必须在 IdP 中注册。 |
| logout_uri | string | 是 | | | | SP 的单点注销（SLO）端点，请求此 URI 将触发注销流程。 |
| logout_callback_uri | string | 是 | | | | SP 的 SLO 回调 URL，IdP 将注销响应发送至此 URL，必须在 IdP 中注册。 |
| logout_redirect_uri | string | 是 | | | | 注销成功后重定向用户的 URL。 |
| sp_cert | string | 是 | | | | PEM 格式的 SP X.509 证书，IdP 使用此证书验证 SP 签名的请求。 |
| sp_private_key | string | 是 | 是 | | | PEM 格式的 SP 私钥，用于对 SAML 请求进行签名，该字段在存储时加密。 |
| auth_protocol_binding_method | string | 否 | | `HTTP-Redirect` | `HTTP-Redirect`、`HTTP-POST` | 认证请求的 SAML 绑定方式。设置为 `HTTP-POST` 时，会话 Cookie 的 `SameSite` 属性将设置为 `None`，`Secure` 设置为 `true`。 |
| secret | string | 否 | 是 | | 8–32 个字符 | 用于会话密钥派生的密钥，该字段在存储时加密。 |
| secret_fallbacks | array[string] | 否 | 是 | | 每项：8–32 个字符 | 密钥轮换时使用的历史密钥列表，允许使用旧密钥加密的会话继续有效，该字段在存储时加密。 |

## 前提条件

在配置 `saml-auth` 插件之前，需要在身份提供商处将 APISIX 注册为服务提供商。具体步骤因 IdP 而异，以下示例使用 [Keycloak](https://www.keycloak.org/)。

### 配置 Keycloak

1. 登录 Keycloak 管理控制台。
2. 创建或选择一个 Realm（例如 `myrealm`）。
3. 进入 **Clients**，点击 **Create client**。
4. 将 **Client type** 设置为 `SAML`。
5. 将 **Client ID** 设置为与插件配置中 `sp_issuer` 一致的值（例如 `https://sp.example.com`）。
6. 在 **Client** > **Settings** 中：
   - 将 **Root URL** 设置为 `https://sp.example.com`。
   - 将 **Valid redirect URIs** 设置为包含 `login_callback_uri`（例如 `https://sp.example.com/login/callback`）。
   - 将 **Master SAML Processing URL** 设置为 `https://sp.example.com/login/callback`。
7. 在 **Client** > **Keys** 中，上传 SP 证书（`sp_cert`）并启用 **Sign assertions**。
8. 导出 IdP 元数据，获取 `idp_uri`（SSO URL）和 `idp_cert`（签名证书）。
9. 在 Keycloak 中创建允许登录的用户。

## 启用插件

以下示例创建一个使用 Keycloak IdP 的 `saml-auth` 插件保护的路由：

:::note

请将证书和密钥占位符替换为实际的 SP 证书、SP 私钥和 IdP 证书。

:::

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
  -H "X-API-KEY: $ADMIN_API_KEY" \
  -X PUT \
  -d '{
    "uri": "/*",
    "plugins": {
      "saml-auth": {
        "sp_issuer": "https://sp.example.com",
        "idp_uri": "https://keycloak.example.com/realms/myrealm/protocol/saml",
        "idp_cert": "-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----",
        "login_callback_uri": "https://sp.example.com/login/callback",
        "logout_uri": "https://sp.example.com/logout",
        "logout_callback_uri": "https://sp.example.com/logout/callback",
        "logout_redirect_uri": "https://sp.example.com/logout/done",
        "sp_cert": "-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----",
        "sp_private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n-----END RSA PRIVATE KEY-----",
        "auth_protocol_binding_method": "HTTP-Redirect",
        "secret": "my-session-secret"
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

## 禁用插件

如需禁用 `saml-auth` 插件，从路由配置中移除即可：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
  -H "X-API-KEY: $ADMIN_API_KEY" \
  -X PUT \
  -d '{
    "uri": "/*",
    "plugins": {},
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1980": 1
      }
    }
  }'
```
