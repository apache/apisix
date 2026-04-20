---
title: openid-connect
keywords:
  - Apache APISIX
  - API 网关
  - OpenID Connect
  - OIDC
description: openid-connect 插件支持与 OpenID Connect (OIDC) 身份提供商集成，例如 Keycloak、Auth0、Microsoft Entra ID、Google、Okta 等。它允许 APISIX 在允许或拒绝客户端访问受保护的上游资源之前，先对客户端进行身份验证并从身份提供商获取相关信息。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/openid-connect" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`openid-connect` 插件支持与 [OpenID Connect (OIDC)](https://openid.net/connect/) 身份提供商集成，例如 Keycloak、Auth0、Microsoft Entra ID、Google、Okta 等。它允许 APISIX 在允许或拒绝客户端访问受保护的上游资源之前，先对客户端进行身份验证并从身份提供商获取相关信息。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| client_id | string | 是 | | | OAuth 客户端 ID。 |
| client_secret | string | 是 | | | OAuth 客户端密钥。 |
| discovery | string | 是 | | | OpenID 提供商的 well-known 发现文档 URL，包含 OP API 端点列表。插件可直接使用发现文档中的端点。您也可以单独配置这些端点，单独配置的值优先于发现文档中提供的端点。 |
| scope | string | 否 | openid | | 与认证用户相关信息对应的 OIDC 范围，也称为 [claims](https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims)。用于授权具有适当权限的用户。默认值为 `openid`，这是 OIDC 返回唯一标识认证用户的 `sub` claim 所需的范围。可以附加额外的范围并以空格分隔，例如 `openid email profile`。 |
| required_scopes | array[string] | 否 | | | 访问令牌中必须存在的范围。在 `bearer_only` 为 `true` 时与 introspection 端点结合使用。如果缺少任何必需范围，插件将以 403 forbidden 错误拒绝请求。 |
| realm | string | 否 | apisix | | 由于无效 bearer token 导致 401 未授权请求时，[`WWW-Authenticate`](https://www.rfc-editor.org/rfc/rfc6750#section-3) 响应头中的 Realm 值。 |
| bearer_only | boolean | 否 | false | | 如果为 true，则严格要求请求中携带 bearer 访问令牌进行身份验证。 |
| logout_path | string | 否 | /logout | | 触发注销的路径。 |
| post_logout_redirect_uri | string | 否 | | | `logout_path` 收到注销请求后重定向用户的 URL。 |
| redirect_uri | string | 否 | | | 与 OpenID 提供商完成身份验证后的重定向 URI。注意，重定向 URI 不应与请求 URI 相同，而应为请求 URI 的子路径。例如，如果路由的 `uri` 为 `/api/v1/*`，则 `redirect_uri` 可配置为 `/api/v1/redirect`。如果未配置 `redirect_uri`，APISIX 将在请求 URI 后追加 `/.apisix/redirect` 作为 `redirect_uri` 的值。 |
| timeout | integer | 否 | 3 | [1,...] | 请求超时时间，单位为秒。 |
| ssl_verify | boolean | 否 | true | | 如果为 true，则验证 OpenID 提供商的 SSL 证书。注意：该属性的默认值在 APISIX 3.16.0 中从 `false` 更改为 `true`，这是一个破坏性变更。如果您从早期版本升级，请确保您的 OpenID 提供商 SSL 证书有效，或显式将其设置为 `false` 以保持之前的行为。 |
| introspection_endpoint | string | 否 | | | OpenID 提供商用于内省访问令牌的[令牌内省](https://datatracker.ietf.org/doc/html/rfc7662)端点 URL。如果未设置，则使用 well-known 发现文档中提供的内省端点作为[备选项](https://github.com/zmartzone/lua-resty-openidc/commit/cdaf824996d2b499de4c72852c91733872137c9c)。 |
| introspection_endpoint_auth_method | string | 否 | client_secret_basic | | 令牌内省端点的认证方法。值应为 well-known 发现文档中 `introspection_endpoint_auth_methods_supported` [授权服务器元数据](https://www.rfc-editor.org/rfc/rfc8414.html)指定的认证方法之一，例如 `client_secret_basic`、`client_secret_post`、`private_key_jwt` 和 `client_secret_jwt`。 |
| token_endpoint_auth_method | string | 否 | client_secret_basic | | 令牌端点的认证方法。值应为 well-known 发现文档中 `token_endpoint_auth_methods_supported` [授权服务器元数据](https://www.rfc-editor.org/rfc/rfc8414.html)指定的认证方法之一，例如 `client_secret_basic`、`client_secret_post`、`private_key_jwt` 和 `client_secret_jwt`。如果配置的方法不受支持，则回退到 `token_endpoint_auth_methods_supported` 数组中的第一个方法。 |
| public_key | string | 否 | | | 使用非对称算法时用于验证 JWT 签名的公钥。提供此值进行令牌验证将跳过客户端凭证流中的令牌内省。可以以 `-----BEGIN PUBLIC KEY-----\n……\n-----END PUBLIC KEY-----` 格式传递公钥。 |
| use_jwks | boolean | 否 | false | | 如果为 true 且未设置 `public_key`，则使用 JWKS 验证 JWT 签名并跳过客户端凭证流中的令牌内省。JWKS 端点从发现文档中解析。 |
| use_pkce | boolean | 否 | false | | 如果为 true，则按照 [RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636) 定义，在授权码流程中使用 PKCE（Proof Key for Code Exchange）。 |
| token_signing_alg_values_expected | string | 否 | | | 用于签署 JWT 的算法，例如 `RS256`。 |
| set_access_token_header | boolean | 否 | true | | 如果为 true，则在请求头中设置访问令牌。默认使用 `X-Access-Token` 头。 |
| access_token_in_authorization_header | boolean | 否 | false | | 如果为 true 且 `set_access_token_header` 也为 true，则在 `Authorization` 头中设置访问令牌。 |
| set_id_token_header | boolean | 否 | true | | 如果为 true 且 ID 令牌可用，则在 `X-ID-Token` 请求头中设置其值。 |
| set_userinfo_header | boolean | 否 | true | | 如果为 true 且用户信息数据可用，则在 `X-Userinfo` 请求头中设置其值。 |
| set_refresh_token_header | boolean | 否 | false | | 如果为 true 且刷新令牌可用，则在 `X-Refresh-Token` 请求头中设置其值。 |
| session | object | 否 | | | 当 `bearer_only` 为 `false` 且插件使用授权码流程时的会话配置。 |
| session.secret | string | 是 | | 16 个或更多字符 | `bearer_only` 为 `false` 时用于会话加密和 HMAC 操作的密钥。 |
| session.cookie | object | 否 | | | Cookie 配置。 |
| session.cookie.lifetime | integer | 否 | 3600 | | Cookie 生命周期，单位为秒。 |
| session.storage | string | 否 | cookie | ["cookie", "redis"] | 会话存储方式。 |
| session.redis | object | 否 | | | `storage` 为 `redis` 时的 Redis 配置。 |
| session.redis.host | string | 否 | 127.0.0.1 | | Redis 主机。 |
| session.redis.port | integer | 否 | 6379 | | Redis 端口。 |
| session.redis.username | string | 否 | | | Redis 用户名。 |
| session.redis.password | string | 否 | | | Redis 密码。 |
| session.redis.database | integer | 否 | 0 | | Redis 数据库索引。 |
| session.redis.prefix | string | 否 | sessions | | Redis 键前缀。 |
| session.redis.ssl | boolean | 否 | false | | 为 Redis 连接启用 SSL。 |
| session.redis.ssl_verify | boolean | 是 | false | | 验证 Redis 连接的 SSL 证书。 |
| session.redis.server_name | string | 否 | | | 用于 SNI 的 Redis 服务器名称。 |
| session.redis.connect_timeout | integer | 否 | 1000 | | 连接超时时间，单位为毫秒。 |
| session.redis.send_timeout | integer | 否 | 1000 | | 发送超时时间，单位为毫秒。 |
| session.redis.read_timeout | integer | 否 | 1000 | | 读取超时时间，单位为毫秒。 |
| session.redis.keepalive_timeout | integer | 否 | 10000 | | 保活超时时间，单位为毫秒。 |
| session_contents | object | 否 | | | 会话内容配置。如果未配置，所有数据将存储在会话中。 |
| session_contents.access_token | boolean | 否 | | | 如果为 true，则在会话中存储访问令牌。 |
| session_contents.id_token | boolean | 否 | | | 如果为 true，则在会话中存储 ID 令牌。 |
| session_contents.enc_id_token | boolean | 否 | | | 如果为 true，则在会话中存储加密的 ID 令牌。 |
| session_contents.user | boolean | 否 | | | 如果为 true，则在会话中存储用户信息。 |
| unauth_action | string | 否 | auth | ["auth", "deny", "pass"] | 未认证请求的处理方式。设置为 `auth` 时，重定向到 OpenID 提供商的认证端点。设置为 `pass` 时，允许请求不经认证通过。设置为 `deny` 时，返回 401 未认证响应而不启动授权码授权流程。 |
| proxy_opts | object | 否 | | | OpenID 提供商所在代理服务器的配置。 |
| proxy_opts.http_proxy | string | 否 | | | HTTP 请求的代理服务器地址，例如 `http://<proxy_host>:<proxy_port>`。 |
| proxy_opts.https_proxy | string | 否 | | | HTTPS 请求的代理服务器地址，例如 `http://<proxy_host>:<proxy_port>`。 |
| proxy_opts.http_proxy_authorization | string | 否 | | Basic [base64 username:password] | 与 `http_proxy` 一起使用的默认 `Proxy-Authorization` 头值。可以用自定义 `Proxy-Authorization` 请求头覆盖。 |
| proxy_opts.https_proxy_authorization | string | 否 | | Basic [base64 username:password] | 与 `https_proxy` 一起使用的默认 `Proxy-Authorization` 头值。由于 HTTPS 连接时已完成授权，不能用自定义 `Proxy-Authorization` 请求头覆盖。 |
| proxy_opts.no_proxy | string | 否 | | | 不需要代理的主机列表，以逗号分隔。 |
| authorization_params | object | 否 | | | 发送到授权端点请求中的额外参数。 |
| client_rsa_private_key | string | 否 | | | 用于向 OP 签署 JWT 进行身份验证的客户端 RSA 私钥。当 `token_endpoint_auth_method` 为 `private_key_jwt` 时必填。 |
| client_rsa_private_key_id | string | 否 | | | 用于计算已签名 JWT 的客户端 RSA 私钥 ID。当 `token_endpoint_auth_method` 为 `private_key_jwt` 时可选。 |
| client_jwt_assertion_expires_in | integer | 否 | 60 | | 向 OP 进行身份验证的已签名 JWT 的有效期，单位为秒。在 `token_endpoint_auth_method` 为 `private_key_jwt` 或 `client_secret_jwt` 时使用。 |
| renew_access_token_on_expiry | boolean | 否 | true | | 如果为 true，则在访问令牌过期或刷新令牌可用时尝试静默续期。如果令牌续期失败，则重定向用户重新认证。 |
| access_token_expires_in | integer | 否 | | | 当令牌端点响应中没有 `expires_in` 属性时，访问令牌的有效期，单位为秒。 |
| refresh_session_interval | integer | 否 | | | 无需重新认证即可刷新用户 ID 令牌的时间间隔，单位为秒。未设置时不检查网关向客户端签发的会话的过期时间。 |
| iat_slack | integer | 否 | 120 | | ID 令牌 `iat` claim 时钟偏差容忍度，单位为秒。 |
| accept_none_alg | boolean | 否 | false | | 如果 OpenID 提供商不对其 ID 令牌进行签名（例如签名算法设置为 `none`），则设置为 true。 |
| accept_unsupported_alg | boolean | 否 | true | | 如果为 true，则忽略 ID 令牌签名以接受不支持的签名算法。 |
| access_token_expires_leeway | integer | 否 | 0 | | 访问令牌续期的过期宽限时间，单位为秒。当设置为大于 0 的值时，令牌续期将在令牌过期前该时间量时进行。这可避免在访问令牌刚到达资源服务器时过期的错误。 |
| force_reauthorize | boolean | 否 | false | | 如果为 true，即使令牌已缓存也执行授权流程。 |
| use_nonce | boolean | 否 | false | | 如果为 true，则在授权请求中启用 nonce 参数。 |
| revoke_tokens_on_logout | boolean | 否 | false | | 如果为 true，则在注销时通知授权服务器之前获取的刷新令牌或访问令牌不再需要。 |
| jwk_expires_in | integer | 否 | 86400 | | JWK 缓存的过期时间，单位为秒。 |
| jwt_verification_cache_ignore | boolean | 否 | false | | 如果为 true，则强制重新验证 bearer 令牌并忽略任何现有的缓存验证结果。 |
| cache_segment | string | 否 | | | 缓存段的可选名称，用于分离和区分令牌内省或 JWT 验证使用的缓存。 |
| introspection_interval | integer | 否 | 0 | | 缓存和内省的访问令牌的 TTL，单位为秒。默认值为 0，表示不使用此选项，插件默认使用 `introspection_expiry_claim` 定义的过期 claim 传递的 TTL。如果 `introspection_interval` 大于 0 且小于 `introspection_expiry_claim` 定义的过期 claim 传递的 TTL，则使用 `introspection_interval`。 |
| introspection_expiry_claim | string | 否 | exp | | 过期 claim 的名称，用于控制缓存和内省的访问令牌的 TTL。 |
| introspection_addon_headers | array[string] | 否 | | | 用于向内省 HTTP 请求追加额外头值。如果指定的头在原始请求中不存在，则不会追加该值。 |
| claim_validator | object | 否 | | | JWT claim 验证配置。 |
| claim_validator.issuer.valid_issuers | array[string] | 否 | | | 受信任的 JWT 颁发者数组。如果未配置，将使用发现端点返回的颁发者。如果两者均不可用，则不验证颁发者。 |
| claim_validator.audience | object | 否 | | | [受众 claim](https://openid.net/specs/openid-connect-core-1_0.html) 验证配置。 |
| claim_validator.audience.claim | string | 否 | aud | | 包含受众的 claim 名称。 |
| claim_validator.audience.required | boolean | 否 | false | | 如果为 true，则受众 claim 为必填项，claim 名称为 `claim` 中定义的名称。 |
| claim_validator.audience.match_with_client_id | boolean | 否 | false | | 如果为 true，则要求受众与客户端 ID 匹配。如果受众是字符串，则必须与客户端 ID 完全匹配。如果受众是字符串数组，则至少一个值必须与客户端 ID 匹配。如果未找到匹配，将收到 `mismatched audience` 错误。OpenID Connect 规范规定了此要求，以确保令牌是为特定客户端颁发的。 |
| claim_schema | object | 否 | | | OIDC 响应 claim 的 JSON schema。示例：`{"type":"object","properties":{"access_token":{"type":"string"}},"required":["access_token"]}` - 验证响应包含必填的字符串字段 `access_token`。 |

注意：schema 中还定义了 `encrypt_fields = {"client_secret", "client_rsa_private_key"}`，这意味着这些字段将在 etcd 中加密存储。详见[加密存储字段](../plugin-develop.md#加密存储字段)。

此外，您可以使用环境变量或 APISIX Secret 来存储和引用插件属性。APISIX 目前支持两种存储密钥的方式——[环境变量和 HashiCorp Vault](../terminology/secret.md)。

例如，使用以下命令设置环境变量：

```bash
export KEYCLOAK_CLIENT_SECRET=abc
```

并在插件配置中引用：

```json
"client_secret": "$ENV://KEYCLOAK_CLIENT_SECRET"
```

## 示例

以下示例展示了如何针对不同场景配置 `openid-connect` 插件。

:::note

您可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 授权码流程

授权码流程在 [RFC 6749 第 4.1 节](https://datatracker.ietf.org/doc/html/rfc6749#section-4.1)中定义。它涉及将临时授权码换取访问令牌，通常由机密客户端和公共客户端使用。

下图展示了实现授权码流程时不同实体之间的交互：

![授权码流程图](https://static.api7.ai/uploads/2023/11/27/Ga2402sb_oidc-code-auth-flow-revised.png)

当传入请求的头中或合适的会话 Cookie 中不包含访问令牌时，插件作为依赖方重定向到授权服务器以继续授权码流程。

认证成功后，插件将令牌保存在会话 Cookie 中，后续请求将使用 Cookie 中存储的令牌。

以下示例创建一个路由，并配置 `openid-connect` 插件以使用 Keycloak 作为身份提供商的授权码流程：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```bash
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "openid-connect-route",
    "uri": "/api/v1/*",
    "plugins": {
      "openid-connect": {
        "client_id": "apisix",
        "client_secret": "your-client-secret",
        "discovery": "http://keycloak:8080/realms/master/.well-known/openid-configuration",
        "scope": "openid email profile",
        "redirect_uri": "http://127.0.0.1:9080/api/v1/redirect",
        "ssl_verify": false,
        "session": {
          "secret": "your-session-secret-min-16-chars"
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

</TabItem>
<TabItem value="adc" label="ADC">

```yaml
routes:
  - id: openid-connect-route
    uri: /api/v1/*
    plugins:
      openid-connect:
        client_id: apisix
        client_secret: your-client-secret
        discovery: http://keycloak:8080/realms/master/.well-known/openid-configuration
        scope: openid email profile
        redirect_uri: http://127.0.0.1:9080/api/v1/redirect
        ssl_verify: false
        session:
          secret: your-session-secret-min-16-chars
    upstream:
      type: roundrobin
      nodes:
        httpbin.org:80: 1
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: openid-connect-route
  namespace: default
  annotations:
    konghq.com/plugins: openid-connect-plugin
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/v1
      backendRefs:
        - name: httpbin
          port: 80
---
apiVersion: apisix.apache.org/v2
kind: ApisixPlugin
metadata:
  name: openid-connect-plugin
  namespace: default
spec:
  plugin_name: openid-connect
  config:
    client_id: apisix
    client_secret: your-client-secret
    discovery: http://keycloak:8080/realms/master/.well-known/openid-configuration
    scope: openid email profile
    redirect_uri: http://127.0.0.1:9080/api/v1/redirect
    ssl_verify: false
    session:
      secret: your-session-secret-min-16-chars
```

</TabItem>
<TabItem value="apisix-ingress-controller" label="APISIX Ingress Controller">

```yaml
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  name: openid-connect-route
  namespace: default
spec:
  http:
    - name: rule1
      match:
        paths:
          - /api/v1/*
      backends:
        - serviceName: httpbin
          servicePort: 80
      plugins:
        - name: openid-connect
          enable: true
          config:
            client_id: apisix
            client_secret: your-client-secret
            discovery: http://keycloak:8080/realms/master/.well-known/openid-configuration
            scope: openid email profile
            redirect_uri: http://127.0.0.1:9080/api/v1/redirect
            ssl_verify: false
            session:
              secret: your-session-secret-min-16-chars
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

详见[实现授权码授权](../tutorials/keycloak-oidc.md#implement-authorization-code-grant)，获取使用 `openid-connect` 插件与 Keycloak 集成并使用授权码流程的完整示例。

### PKCE (Proof Key for Code Exchange)

PKCE 在 [RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636) 中定义。PKCE 通过添加代码挑战和验证器来增强授权码流程，防止授权码截取攻击。

下图展示了实现带 PKCE 的授权码流程时不同实体之间的交互：

![带 PKCE 的授权码流程图](https://static.api7.ai/uploads/2024/11/04/aJ2ZVuTC_auth-code-with-pkce.png)

要使用 PKCE，在插件配置中将 `use_pkce` 设置为 `true`。同时确保已配置 IdP 客户端以使用 PKCE。

详见[实现授权码授权](../tutorials/keycloak-oidc.md#implement-authorization-code-grant)，获取使用 `openid-connect` 插件与 Keycloak 集成并使用带 PKCE 的授权码流程的示例。

### 客户端凭证流程

客户端凭证流程在 [RFC 6749 第 4.4 节](https://datatracker.ietf.org/doc/html/rfc6749#section-4.4)中定义。它涉及客户端使用自身凭证请求访问令牌以访问受保护资源，通常用于机器间认证，不代表特定用户。

下图展示了实现客户端凭证流程时不同实体之间的交互：

<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/10/28/sbHxqnOz_client-credential-no-introspect.png" alt="客户端凭证流程图" style={{width: '70%'}} />
</div>
<br />

详见[实现客户端凭证授权](../tutorials/keycloak-oidc.md#implement-client-credentials-grant)，获取使用 `openid-connect` 插件与 Keycloak 集成并使用客户端凭证流程的示例。

### 内省流程

内省流程在 [RFC 7662](https://datatracker.ietf.org/doc/html/rfc7662) 中定义。它涉及通过查询授权服务器的内省端点来验证访问令牌的有效性和详细信息。

在此流程中，当客户端向资源服务器提供访问令牌时，资源服务器向授权服务器的内省端点发送请求，如果令牌有效，端点将返回令牌详细信息，包括令牌过期时间、关联范围以及令牌所属的用户或客户端等信息。

下图展示了实现带令牌内省的授权码流程时不同实体之间的交互：

<br />
<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/10/29/Y2RWIUV9_client-cred-flow-introspection.png" alt="带内省的客户端凭证流程图" style={{width: '55%'}} />
</div>
<br />

详见[实现客户端凭证授权](../tutorials/keycloak-oidc.md#implement-client-credentials-grant)，获取使用 `openid-connect` 插件与 Keycloak 集成并使用带令牌内省的客户端凭证流程的示例。

### 密码流程

密码流程在 [RFC 6749 第 4.3 节](https://datatracker.ietf.org/doc/html/rfc6749#section-4.3)中定义。它专为受信任的应用程序设计，允许它们直接使用用户的用户名和密码获取访问令牌。在此授权类型中，客户端应用程序将用户凭证连同其自身的客户端 ID 和密钥一起发送到授权服务器，授权服务器对用户进行身份验证，如果有效则颁发访问令牌。

尽管效率较高，但此流程仅适用于高度受信任的第一方应用程序，因为它要求应用程序直接处理敏感的用户凭证，如果在第三方场景中使用会带来重大安全风险。

下图展示了实现密码流程时不同实体之间的交互：

<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/10/30/njkWZVgX_pass-grant.png" alt="密码流程图" style={{width: '70%'}} />
</div>
<br />

详见[实现密码授权](../tutorials/keycloak-oidc.md#implement-password-grant)，获取使用 `openid-connect` 插件与 Keycloak 集成并使用密码流程的示例。

### 刷新令牌授权

刷新令牌授权在 [RFC 6749 第 6 节](https://datatracker.ietf.org/doc/html/rfc6749#section-6)中定义。它使客户端无需用户重新认证，即可使用之前颁发的刷新令牌请求新的访问令牌。此流程通常在访问令牌过期时使用，允许客户端在无需用户干预的情况下保持对资源的持续访问。刷新令牌与访问令牌一起在某些 OAuth 流程中颁发，其生命周期和安全要求取决于授权服务器的配置。

下图展示了实现带刷新令牌的密码流程时不同实体之间的交互：

<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/10/30/YBF7rI6M_password-with-refresh-token.png" alt="带刷新令牌的密码授权流程图" style={{width: '100%'}} />
</div>
<br />

详见[刷新令牌](../tutorials/keycloak-oidc.md#refresh-token)，获取使用 `openid-connect` 插件与 Keycloak 集成并使用带令牌刷新的密码流程的示例。

### 用户信息

OpenID Connect (OIDC) 中的 UserInfo 端点在 [OpenID Connect Core 1.0 第 5.3 节](https://openid.net/specs/openid-connect-core-1_0.html#UserInfo)中定义。它使客户端能够通过提供有效的访问令牌来检索已认证用户的额外 claim。此端点对于获取用户个人资料信息（如姓名、电子邮件和其他属性）特别有用，这些信息在用户认证后可通过该端点获取。UserInfo 端点返回的数据取决于访问令牌的范围以及授权服务器配置的 claim。

当 `set_userinfo_header` 为 `true`（默认值）时，插件在 `X-Userinfo` 请求头中设置用户信息数据，上游服务可使用该数据进行进一步处理。

## 故障排除

本节涵盖使用此插件时常见的一些问题，以帮助您进行故障排查。

### APISIX 无法连接到 OpenID 提供商

如果 APISIX 无法解析或连接到 OpenID 提供商，请检查配置文件 `config.yaml` 中的 DNS 设置并根据需要进行修改。

### 未找到会话状态

如果在使用[授权码流程](#授权码流程)时，日志中出现 `500 internal server error` 和以下消息，可能有多种原因。

```text
the error request to the redirect_uri path, but there's no session state found
```

#### 1. 重定向 URI 配置错误

一个常见的配置错误是将 `redirect_uri` 配置为与路由 URI 相同。当用户发起访问受保护资源的请求时，请求直接到达重定向 URI，但请求中没有会话 Cookie，导致未找到会话状态的错误。

要正确配置重定向 URI，确保 `redirect_uri` 与配置了插件的路由匹配，但不完全相同。例如，正确的配置是将路由的 `uri` 配置为 `/api/v1/*`，将 `redirect_uri` 的路径部分配置为 `/api/v1/redirect`。

同时确保 `redirect_uri` 包含协议，例如 `http` 或 `https`。

#### 2. 缺少会话密钥

如果您以[独立模式](../production/deployment-modes.md#standalone-mode)部署 APISIX，请确保配置了 `session.secret`。

用户会话以 Cookie 形式存储在浏览器中，并使用会话密钥加密。如果未通过 `session.secret` 属性配置密钥，则会自动生成密钥并保存到 etcd。但在独立模式下，etcd 不再是配置中心。因此，您应在 YAML 配置中心 `apisix.yaml` 中为此插件显式配置 `session.secret`。

#### 3. Cookie 未发送或缺失

检查 [`SameSite`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#samesitesamesite-value) Cookie 属性是否正确设置（即您的应用程序是否需要跨站发送 Cookie），以判断这是否是阻止 Cookie 保存到浏览器 Cookie 存储或从浏览器发送的因素。

#### 4. 上游发送的头太大

如果您在 APISIX 前面使用 NGINX 代理客户端流量，请检查 NGINX 的 `error.log` 中是否出现以下错误：

```text
upstream sent too big header while reading response header from upstream
```

如果是，请尝试将 `proxy_buffers`、`proxy_buffer_size` 和 `proxy_busy_buffers_size` 调整为更大的值。

另一个选项是配置 `session_contents` 属性来调整存储在会话中的数据。例如，可以将 `session_contents.access_token` 设置为 `true`。

#### 5. 客户端密钥无效

验证 `client_secret` 是否有效且正确。无效的 `client_secret` 会导致认证失败，且不会返回令牌并存储在会话中。

#### 6. PKCE IdP 配置

如果您在授权码流程中启用了 PKCE，请确保您已配置 IdP 客户端以使用 PKCE。例如，在 Keycloak 中，您应在客户端的高级设置中配置 PKCE 挑战方法：

<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/11/04/xvnCNb20_pkce-keycloak-revised.jpeg" alt="PKCE Keycloak 配置" style={{width: '70%'}} />
</div>
