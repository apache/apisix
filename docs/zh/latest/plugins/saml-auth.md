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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/saml-auth" />
</head>

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
| login_callback_uri | string | 是 | | | | SP 断言消费者服务（ACS）的请求路径，例如 `/login/callback`。插件在请求路径等于该值时处理 IdP 的登录响应。该字段是路径，对外可见的 ACS 绝对 URL 通过 `sp_acs_url` 配置。 |
| logout_uri | string | 是 | | | | SP 单点注销（SLO）端点的请求路径，例如 `/logout`，请求此路径将触发注销流程。 |
| logout_callback_uri | string | 是 | | | | SP 的 SLO 回调请求路径，例如 `/logout/callback`，IdP 将注销请求和注销响应发送至此路径，必须在 IdP 中注册。 |
| logout_redirect_uri | string | 是 | | | | 注销成功后重定向用户的 URL。 |
| sp_cert | string | 是 | | | | PEM 格式的 SP X.509 证书，IdP 使用此证书验证 SP 签名的请求。 |
| sp_private_key | string | 是 | 是 | | | PEM 格式的 SP 私钥，用于对 SAML 请求进行签名，该字段在存储时加密。 |
| auth_protocol_binding_method | string | 否 | | `HTTP-Redirect` | `HTTP-Redirect`、`HTTP-POST` | 认证请求的 SAML 绑定方式。设置为 `HTTP-POST` 时，会话 Cookie 的 `SameSite` 属性将设置为 `None`，`Secure` 设置为 `true`。 |
| secret | string | 是 | 是 | | 8–32 个字符 | 用于会话密钥派生的密钥。所有 APISIX 节点必须配置相同的值，以确保会话可在多个 worker 进程之间及重启后正常读取。该字段在存储时加密。 |
| secret_fallbacks | array[string] | 否 | 是 | | 每项：8–32 个字符 | 密钥轮换时使用的历史密钥列表，允许使用旧密钥加密的会话继续有效，该字段在存储时加密。 |
| idp_issuers | array[string] | 否 | | | | 登录响应中允许的颁发者列表，响应中的每个断言都必须属于其中之一。未设置时，接受 `idp_cert` 签名的任意颁发者。空数组不接受任何颁发者，所有登录都会被拒绝。参见[颁发者与受众](#颁发者与受众)。 |
| sp_acs_url | string | 否 | | | `http://` 或 `https://` 开头的绝对 URL | 对外可见的 SP ACS 绝对 URL，例如 `https://sp.example.com/login/callback`。该值会在认证请求中发送给 IdP，登录响应的 `Destination` 和 `Recipient` 必须与之相等。未设置时，根据请求的协议、主机和 `login_callback_uri` 生成。参见[代理后的 ACS URL](#代理后的-acs-url)。 |
| sp_audiences | array[string] | 否 | | `sp_issuer` | | SP 接受的受众列表。带有 `AudienceRestriction` 的断言必须指定其中之一。未设置时，仅接受 `sp_issuer`。 |
| clock_skew | number | 否 | | `60` | >= 0 | 校验 `NotBefore` 和 `NotOnOrAfter` 时允许与 IdP 之间存在的时钟偏差，单位为秒。 |
| replay_dict | string | 否 | | | 非空 | 已声明的 `lua_shared_dict` 名称，用于记录已接受的断言，使同一断言无法在同一 APISIX 节点上登录两次。未设置时，不记录已接受的断言。参见[断言重放防护](#断言重放防护)。 |
| replay_ttl | number | 否 | | `600` | >= 1 | 对没有过期时间的断言，记录的时长，单位为秒。有过期时间的断言会记录到过期后再加 `clock_skew`，最长一天，若 `replay_ttl` 大于一天则以其为上限。仅在设置 `replay_dict` 时生效。 |

## 前提条件

在启用该插件前，请先在每个 APISIX 节点上安装 `lua-resty-saml`：

```shell
luarocks install lua-resty-saml 0.2.6
```

`lua-resty-saml` 会编译原生 xmlsec 绑定，因此构建环境需要提供 LuaRocks 所需的 OpenSSL、libxml2 和 libxslt 开发文件。

在配置 `saml-auth` 插件之前，需要在身份提供商处将 APISIX 注册为服务提供商。具体步骤因 IdP 而异，以下示例使用 [Keycloak](https://www.keycloak.org/)。

### 配置 Keycloak

1. 登录 Keycloak 管理控制台。
2. 创建或选择一个 Realm（例如 `myrealm`）。
3. 进入 **Clients**，点击 **Create client**。
4. 将 **Client type** 设置为 `SAML`。
5. 将 **Client ID** 设置为与插件配置中 `sp_issuer` 一致的值（例如 `https://sp.example.com`）。
6. 在 **Client** > **Settings** 中：
   - 将 **Root URL** 设置为 `https://sp.example.com`。
   - 将 **Valid redirect URIs** 设置为包含 ACS 绝对 URL，即 `sp_acs_url`（例如 `https://sp.example.com/login/callback`）。
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
        "login_callback_uri": "/login/callback",
        "sp_acs_url": "https://sp.example.com/login/callback",
        "logout_uri": "/logout",
        "logout_callback_uri": "/logout/callback",
        "logout_redirect_uri": "https://sp.example.com/logout/done",
        "idp_issuers": ["https://keycloak.example.com/realms/myrealm"],
        "sp_audiences": ["https://sp.example.com"],
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

## 响应校验

插件将以下配置传递给 `lua-resty-saml`，由其校验每个登录响应。这些配置均为可选项，未设置它们的现有配置行为保持不变。

### 颁发者与受众

`idp_cert` 证明响应由 IdP 的密钥签名，但同一密钥可能为多个颁发者签名，例如同一 IdP 部署中的多个 Realm。将 `idp_issuers` 设置为预期 IdP 的颁发者（实体 ID），Keycloak 的颁发者为 `https://<keycloak-host>/realms/<realm>`。响应中若包含其他颁发者的断言，将以 `401` 拒绝。未设置 `idp_issuers` 时接受任意颁发者，设置为空数组时不接受任何颁发者。

IdP 会将每个断言限定给某个受众，通常为 SP 的实体 ID。插件接受 `AudienceRestriction` 中包含 `sp_issuer` 的断言。当 IdP 使用其他受众时，请设置 `sp_audiences` 并列出 SP 接受的全部受众，因为设置 `sp_audiences` 后不会再自动加入 `sp_issuer`。

`clock_skew` 设置校验断言有效期时允许 APISIX 节点与 IdP 之间存在的时钟偏差秒数。请使用 NTP 同步 APISIX 节点时间，使默认值足够使用。

### 代理后的 ACS URL

IdP 将登录响应发送到 ACS 绝对 URL，并在响应的 `Destination` 和 `Recipient` 中写入该 URL。当它们与插件预期的 ACS URL 不同时，响应将以 `401` 拒绝。

未设置 `sp_acs_url` 时，插件根据到达 APISIX 的请求的协议和主机生成预期 URL。当 APISIX 看到的协议或主机与浏览器不同时，例如负载均衡器终止 TLS 后以 HTTP 转发，或改写了 `Host` 请求头，生成的 URL 就是错误的，所有登录都会被拒绝。此时请将 `sp_acs_url` 设置为浏览器使用的 URL，即在 IdP 中注册的 ACS URL：

```json
{
  "login_callback_uri": "/login/callback",
  "sp_acs_url": "https://sp.example.com/login/callback"
}
```

`login_callback_uri` 仍是 APISIX 匹配的请求路径，`sp_acs_url` 是 IdP 和浏览器使用的绝对 URL。请求到达 APISIX 时，`sp_acs_url` 的路径应对应 `login_callback_uri`。

### 断言重放防护

设置 `replay_dict` 后，每个 APISIX 节点会记录其接受的断言，再次提交同一登录响应时将以 `401` 拒绝。

启用 `saml-auth` 插件时，APISIX 会为此声明共享字典 `plugin-saml-auth-replay`。在插件中引用：

```json
{
  "replay_dict": "plugin-saml-auth-replay",
  "replay_ttl": 600
}
```

该共享字典默认大小为 `10m`，约可保存 40,000 个断言。如需调整，请在每个 APISIX 节点的 `conf/config.yaml` 中修改：

```yaml
nginx_config:
  http:
    lua_shared_dict:
      plugin-saml-auth-replay: 20m
```

如需为不同路由使用独立的记录，可在 `nginx_config.http.custom_lua_shared_dict` 中声明更多共享字典，并在 `replay_dict` 中引用。若路由引用了未声明的共享字典，该路由的所有请求都将返回 `500`，并记录日志 `no lua_shared_dict named <name>`。

启用重放防护时，请注意以下事项：

- **记录仅在单个节点内有效。** `lua_shared_dict` 只在同一 APISIX 节点的 worker 进程之间共享。当多个 APISIX 节点服务同一路由时，一个节点接受的响应不会被其他节点知晓。只要 IdP 发送 `InResponseTo`（主流 IdP 均会发送），`lua-resty-saml` 在每个节点上仍会将响应绑定到用户会话中保存的登录请求。
- **按登录速率设置共享字典大小。** 每个已接受的断言在过期前都会占用一个条目。例如，每秒 100 次登录、断言有效期 10 分钟时，约需保存 60,000 个条目，默认的 `10m` 不足以容纳。共享字典已满时，断言会被接受但不会被记录，并记录错误日志。
- **重复提交会被拒绝。** 浏览器再次提交同一登录响应（例如通过浏览历史返回）时会收到 `401`。重新打开受保护的 URL 即可发起新的登录。

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
