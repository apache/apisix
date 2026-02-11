---
title: openid-connect
keywords:
  - Apache APISIX
  - API 网关
  - OpenID Connect
  - OIDC
description: openid-connect 插件支持与 OpenID Connect (OIDC) 身份提供商集成，例如 Keycloak、Auth0、Microsoft Entra ID、Google、Okta 等。它允许 APISIX 对客户端进行身份验证并从身份提供商处获取其信息，然后允许或拒绝其访问上游受保护资源。
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

## 描述

`openid-connect` 插件支持与 [OpenID Connect (OIDC)](https://openid.net/connect/) 身份提供商集成，例如 Keycloak、Auth0、Microsoft Entra ID、Google、Okta 等。它允许 APISIX 对客户端进行身份验证，并从身份提供商处获取其信息，然后允许或拒绝其访问上游受保护资源。

## 属性

| 名称                                 | 类型     | 必选项 | 默认值                | 有效值         | 描述                                                                                             |
| ------------------------------------ | ------- | ------ | --------------------- | ------------- | ------------------------------------------------------------------------------------------------ |
| client_id                            | string  | 是     |                       |               | OAuth 客户端 ID。                                                                                 |
| client_secret                        | string  | 是     |                       |               | OAuth 客户端 secret。                                                                            |
| discovery | string | 是 | | | OpenID 提供商的知名发现文档的 URL，其中包含 OP API 端点列表。插件可以直接利用发现文档中的端点。您也可以单独配置这些端点，这优先于发现文档中提供的端点。 |
| scope | string | 否 | openid | | 与应返回的有关经过身份验证的用户的信息相对应的 OIDC 范围，也称为 [claim](https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims)。这用于向用户授权适当的权限。默认值为 `openid`，这是 OIDC 返回唯一标识经过身份验证的用户的 `sub` 声明所需的范围。可以附加其他范围并用空格分隔，例如 `openid email profile`。 |
| required_scopes | array[string] | 否 | | | 访问令牌中必须存在的范围。当 `bearer_only` 为 `true` 时与自省端点结合使用。如果缺少任何必需的范围，插件将以 403 禁止错误拒绝请求。|
| realm | string | 否 | apisix | | 由于持有者令牌无效，[`WWW-Authenticate`](https://www.rfc-editor.org/rfc/rfc6750#section-3) 响应标头中的领域伴随 401 未经授权的请求。 |
| bearer_only | boolean | 否 | false | | 如果为 true，则严格要求在身份验证请求中使用持有者访问令牌。 |
| logout_path | string | 否 | /logout | | 激活注销的路径。 |
| post_logout_redirect_uri | string | 否 | | | `logout_path` 收到注销请求后将用户重定向到的 URL。|
| redirect_uri | string | 否 | | | 通过 OpenID 提供商进行身份验证后重定向到的 URI。请注意，重定向 URI 不应与请求 URI 相同，而应为请求 URI 的子路径。例如，如果路由的 `uri` 是 `/api/v1/*`，则 `redirect_uri` 可以配置为 `/api/v1/redirect`。如果未配置 `redirect_uri`，APISIX 将在请求 URI 后附加 `/.apisix/redirect` 以确定 `redirect_uri` 的值。|
| timeout | integer | 否 | 3 | [1,...] | 请求超时时间（秒）。|
| ssl_verify | boolean | 否 | false | | 如果为 true，则验证 OpenID 提供商的 SSL 证书。|
| introspection_endpoint | string | 否 | | |用于自检访问令牌的 OpenID 提供程序的 [令牌自检](https://datatracker.ietf.org/doc/html/rfc7662) 端点的 URL。如果未设置，则将使用众所周知的发现文档中提供的自检端点[作为后备](https://github.com/zmartzone/lua-resty-openidc/commit/cdaf824996d2b499de4c72852c91733872137c9c)。|
| introspection_endpoint_auth_method | string | 否 | client_secret_basic | | 令牌自检端点的身份验证方法。该值应为 `introspection_endpoint_auth_methods_supported` [授权服务器元数据](https://www.rfc-editor.org/rfc/rfc8414.html) 中指定的身份验证方法之一，如众所周知的发现文档中所示，例如 `client_secret_basic`、`client_secret_post`、`private_key_jwt` 和 `client_secret_jwt`。|
| token_endpoint_auth_method | string | 否 | client_secret_basic | | 令牌端点的身份验证方法。该值应为 `token_endpoint_auth_methods_supported` [授权服务器元数据](https://www.rfc-editor.org/rfc/rfc8414.html) 中指定的身份验证方法之一，如众所周知的发现文档中所示，例如 `client_secret_basic`、`client_secret_post`、`private_key_jwt` 和 `client_secret_jwt`。如果配置的方法不受支持，则回退到 `token_endpoint_auth_methods_supported` 数组中的第一个方法。|
| public_key | string | 否 | | | 用于验证 JWT 签名 id 的公钥使用非对称算法。提供此值来执行令牌验证将跳过客户端凭据流中的令牌自检。您可以以 `-----BEGIN PUBLIC KEY-----\\n……\\n-----END PUBLIC KEY-----` 格式传递公钥。|
| use_jwks | boolean | 否 | false | | 如果为 true 并且未设置 `public_key`，则使用 JWKS 验证 JWT 签名并跳过客户端凭据流中的令牌自检。JWKS 端点是从发现文档中解析出来的。|
| use_pkce | boolean | 否 | false | | 如果为 true，则使用 [RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636) 中定义的授权码流的代码交换证明密钥 (PKCE)。|
| token_signing_alg_values_expected | string | 否 | | | 用于签署 JWT 的算法，例如 `RS256`。 |
| set_access_token_header | boolean | 否 | true | | 如果为 true，则在请求标头中设置访问令牌。默认情况下，使用 `X-Access-Token` 标头。|
| access_token_in_authorization_header | boolean | 否 | false | | 如果为 true 并且 `set_access_token_header` 也为 true，则在 `Authorization` 标头中设置访问令牌。 |
| set_id_token_header | boolean | 否 | true | | 如果为 true 并且 ID 令牌可用，则在 `X-ID-Token` 请求标头中设置值。 |
| set_userinfo_header | boolean | 否 | true | | 如果为 true 并且用户信息数据可用，则在 `X-Userinfo` 请求标头中设置值。 |
| set_refresh_token_header | boolean | 否 | false | | 如果为 true 并且刷新令牌可用，则在 `X-Refresh-Token` 请求标头中设置值。 |
| session | object | 否 | | | 当 `bearer_only` 为 `false` 且插件使用 Authorization Code 流程时使用的 Session 配置。 |
| session.secret | string | 是 | | 16 个字符以上 | 当 `bearer_only` 为 `false` 时，用于 session 加密和 HMAC 运算的密钥。|
| session.cookie | object | 否 | | | Cookie 配置。 |
| session.cookie.lifetime | integer | 否 | 3600 | | Cookie 生存时间（秒）。|
| session.storage | string | 否 | cookie | ["cookie", "redis"] | 会话存储方式。 |
| session.redis | object | 否 | | | 当 `storage` 为 `redis` 时的 Redis 配置。 |
| session.redis.host | string | 否 | 127.0.0.1 | | Redis 主机地址。 |
| session.redis.port | integer | 否 | 6379 | | Redis 端口。 |
| session.redis.password | string | 否 | | | Redis 密码。 |
| session.redis.username | string | 否 | | | Redis 用户名。 |
| session.redis.database | integer | 否 | 0 | | Redis 数据库索引。 |
| session.redis.prefix | string | 否 | sessions | | Redis 键前缀。 |
| session.redis.ssl    | boolean   | 否    | false |             |   启用 Redis SSL 连接。    |
| session.redis.ssl_verify | boolean   | 否    | false |             |   验证 SSL 证书。    |
| session.redis.server_name | string   | 否    |     |             |   Redis SNI 服务器名称。    |
| session.redis.connect_timeout | integer   | 否    | 1000 |             |   连接超时时间（毫秒）。    |
| session.redis.send_timeout   | integer   | 否    | 1000 |             |   发送超时时间（毫秒）。    |
| session.redis.read_timeout   | integer   | 否    | 1000 |             |   读取超时时间（毫秒）。    |
| session.redis.keepalive_timeout | integer   | 否    | 10000 |             |   Keepalive 超时时间（毫秒）。    |
| unauth_action | string | 否 | auth | ["auth","deny","pass"] | 未经身份验证的请求的操作。设置为 `auth` 时，重定向到 OpenID 提供程序的身份验证端点。设置为 `pass` 时，允许请求而无需身份验证。设置为 `deny` 时，返回 401 未经身份验证的响应，而不是启动授权代码授予流程。|
| session_contents   | object   | 否    |       |        | 会话内容配置。如果未配置，将把所有数据存储在会话中。 |
| session_contents.access_token   | boolean   | 否    |          |        | 若为 true，则将访问令牌存储在会话中。 |
| session_contents.id_token   | boolean   | 否    |          |       | 若为 true，则将 ID 令牌存储在会话中。 |
| session_contents.enc_id_token   | boolean   | 否    |          |        | 若为 true，则将加密的 ID 令牌存储在会话中。 |
| session_contents.user   | boolean   | 否    |          |        | 若为 true，则将用户信息存储在会话中。 |
| proxy_opts | object | 否 | | | OpenID 提供程序背后的代理服务器的配置。|
| proxy_opts.http_proxy | string | 否 | |  | HTTP 请求的代理服务器地址，例如 `http://<proxy_host>:<proxy_port>`。|
| proxy_opts.https_proxy | string | 否 | | | HTTPS 请求的代理服务器地址，例如 `http://<proxy_host>:<proxy_port>`。 |
| proxy_opts.http_proxy_authorization | string | 否 | | Basic [base64 用户名：密码] | 与 `http_proxy` 一起使用的默认 `Proxy-Authorization` 标头值。可以用自定义的 `Proxy-Authorization` 请求标头覆盖。 |
| proxy_opts.https_proxy_authorization | string | 否 | | Basic [base64 用户名：密码] | 与 `https_proxy` 一起使用的默认 `Proxy-Authorization` 标头值。不能用自定义的 `Proxy-Authorization` 请求标头覆盖，因为使用 HTTPS 时，授权在连接时完成。 |
| proxy_opts.no_proxy | string | 否 | | | 不应代理的主机的逗号分隔列表。|
| authorization_params | object | 否 | | | 在请求中发送到授权端点的附加参数。 |
| client_rsa_private_key | string | 否 | | | 用于签署 JWT 以向 OP 进行身份验证的客户端 RSA 私钥。当 `token_endpoint_auth_method` 为 `private_key_jwt` 时必需。 |
| client_rsa_private_key_id | string | 否 | | | 用于计算签名的 JWT 的客户端 RSA 私钥 ID。当 `token_endpoint_auth_method` 为 `private_key_jwt` 时可选。 |
| client_jwt_assertion_expires_in | integer | 否 | 60 | | 用于向 OP 进行身份验证的签名 JWT 的生命周期，以秒为单位。当 `token_endpoint_auth_method` 为 `private_key_jwt` 或 `client_secret_jwt` 时使用。 |
| renew_access_token_on_expiry | boolean | 否 | true | | 如果为 true，则在访问令牌过期或刷新令牌可用时尝试静默更新访问令牌。如果令牌无法更新，则重定向用户进行重新身份验证。|
| access_token_expires_in | integer | 否 | | | 如果令牌端点响应中不存在 `expires_in` 属性，则访问令牌的有效期（以秒为单位）。 |
| refresh_session_interval | integer | 否 | | | 刷新用户 ID 令牌而无需重新认证的时间间隔。如果未设置，则不会检查网关向客户端发出的会话的到期时间。如果设置为 900，则表示在 900 秒后刷新用户的 `id_token`（或浏览器中的会话），而无需重新认证。 |
| iat_slack | integer | 否 | 120 | | ID 令牌中 `iat` 声明的时钟偏差容忍度（以秒为单位）。 |
| accept_none_alg | boolean | 否 | false | | 如果 OpenID 提供程序未签署其 ID 令牌（例如当签名算法设置为`none` 时），则设置为 true。 |
| accept_unsupported_alg | boolean | 否 | true | | 如果为 true，则忽略 ID 令牌签名以接受不支持的签名算法。 |
| access_token_expires_leeway | integer | 否 | 0 | | 访问令牌续订的过期余地（以秒为单位）。当设置为大于 0 的值时，令牌续订将在令牌过期前设定的时间内进行。这样可以避免访问令牌在到达资源服务器时刚好过期而导致的错误。|
| force_reauthorize | boolean | 否 | false | | 如果为 true，即使令牌已被缓存，也执行授权流程。 |
| use_nonce | boolean | 否 | false | | 如果为 true，在授权请求中启用 nonce 参数。 |
| revoke_tokens_on_logout | boolean | 否 | false | | 如果为 true，则通知授权服务器，撤销端点不再需要先前获得的刷新或访问令牌。 |
| jwk_expires_in | integer | 否 | 86400 | | JWK 缓存的过期时间（秒）。 |
| jwt_verification_cache_ignore | boolean | 否 | false | | 如果为 true，则强制重新验证承载令牌并忽略任何现有的缓存验证结果。 |
| cache_segment | string | 否 | | | 缓存段的可选名称，用于分隔和区分令牌自检或 JWT 验证使用的缓存。|
| introspection_interval | integer | 否 | 0 | | 缓存和自省访问令牌的 TTL（以秒为单位）。默认值为 0，这意味着不使用此选项，插件默认使用 `introspection_expiry_claim` 中定义的到期声明传递的 TTL。如果`introspection_interval` 大于 0 且小于 `introspection_expiry_claim` 中定义的到期声明传递的 TTL，则使用`introspection_interval`。|
| introspection_expiry_claim | string | 否 | exp | | 到期声明的名称，它控制缓存和自省访问令牌的 TTL。|
| introspection_addon_headers | array[string] | 否 | | | 用于将其他标头值附加到自省 HTTP 请求。如果原始请求中不存在指定的标头，则不会附加值。|
| claim_validator | object | 否 |  |  | JWT 声明（claim）验证的相关配置。 |
| claim_validator.issuer.valid_issuers | array[string] | 否 |  |  | 可信任的 JWT 发行者（issuer）列表。如果未配置，将使用发现端点返回的发行者；如果两者都不可用，将不会验证发行者。 |
| claim_validator.audience | object | 否 |  |  | [Audience 声明](https://openid.net/specs/openid-connect-core-1_0.html) 验证的相关配置。 |
| claim_validator.audience.claim | string | 否 | aud |  | 包含受众（audience）的声明名称。 |
| claim_validator.audience.required | boolean | 否 | false |  | 若为 `true`，则要求必须存在受众声明，其名称为 `claim` 中定义的值。 |
| claim_validator.audience.match_with_client_id | boolean | 否 | false |  | 若为 `true`，则要求受众（audience）必须与客户端 ID 匹配。若受众为字符串，则必须与客户端 ID 完全一致；若受众为字符串数组，则至少有一个值需与客户端 ID 匹配。若未找到匹配项，将返回 `mismatched audience` 错误。此要求来自 OpenID Connect 规范，用于确保令牌仅用于指定的客户端。 |
| claim_schema | object | 否 |  |  | OIDC 响应 claim 的 JSON schema。示例：`{"type":"object","properties":{"access_token":{"type":"string"}},"required":["access_token"]}` - 验证响应中包含必需的字符串字段 `access_token`。 |

注意：schema 中还定义了 `encrypt_fields = {"client_secret"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

此外：你可以使用环境变量或者 APISIX secret 来存放和引用插件配置，APISIX 当前支持通过两种方式配置 secrets - [Environment Variables and HashiCorp Vault](../terminology/secret.md)。

例如：你可以使用以下方式来设置环境变量
`export keycloak_secret=abc`

并且像下面这样在插件里使用

`"client_secret": "$ENV://keycloak_secret"`

## 示例

以下示例演示了如何针对不同场景配置 `openid-connect` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Authorization Code Flow

Authorization Code Flow 在 [RFC 6749，第 4.1 节](https://datatracker.ietf.org/doc/html/rfc6749#section-4.1) 中定义。它涉及用临时授权码交换访问令牌，通常由机密和公共客户端使用。

下图说明了实施 Authorization Code Flow 时不同实体之间的交互：

![授权码流程图](https://static.api7.ai/uploads/2023/11/27/Ga2402sb_oidc-code-auth-flow-revised.png)

当传入请求的标头中或适当的会话 cookie 中不包含访问令牌时，插件将充当依赖方并重定向到授权服务器以继续授权码流程。

成功验证后，插件将令牌保留在会话 cookie 中，后续请求将使用存储在 cookie 中的令牌。

请参阅 [实现 Authorization Code Flow](../tutorials/keycloak-oidc.md#实现-authorization-code-grant)以获取使用`openid-connect`插件通过授权码流与 Keycloak 集成的示例。

### Proof Key for Code Exchange (PKCE)

Proof Key for Code Exchange (PKCE) 在 [RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636) 中定义。PKCE 通过添加代码质询和验证器来增强授权码流程，以防止授权码拦截攻击。

下图说明了使用 PKCE 实现授权码流程时不同实体之间的交互：

![使用 PKCE 的授权码流程图](https://static.api7.ai/uploads/2024/11/04/aJ2ZVuTC_auth-code-with-pkce.png)

请参阅 [实现 Authorization Code Grant](../tutorials/keycloak-oidc.md#实现-authorization-code-grant)，了解使用 `openid-connect` 插件通过 PKCE 授权码流程与 Keycloak 集成的示例。

### Client Credential Flow

Client Credential Flow 在 [RFC 6749，第 4.4 节](https://datatracker.ietf.org/doc/html/rfc6749#section-4.4) 中定义。它涉及客户端使用自己的凭证请求访问令牌以访问受保护的资源，通常用于机器对机器身份验证，并不代表特定用户。

下图说明了实施 Client Credential Flow 时不同实体之间的交互：

<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/10/28/sbHxqnOz_client-credential-no-introspect.png" alt="Client credential flow diagram" style={{width: '70%'}} />
</div>
<br />

请参阅[实现 Client Credentials Grant](../tutorials/keycloak-oidc.md#实现-client-credentials-grant) 获取使用 `openid-connect` 插件通过客户端凭证流与 Keycloak 集成的示例。

### Introspection Flow

Introspection Flow 在 [RFC 7662](https://datatracker.ietf.org/doc/html/rfc7662) 中定义。它涉及通过查询授权服务器的自省端点来验证访问令牌的有效性和详细信息。

在此流程中，当客户端向资源服务器出示访问令牌时，资源服务器会向授权服务器的自省端点发送请求，如果令牌处于活动状态，则该端点会响应令牌详细信息，包括令牌到期时间、相关范围以及它所属的用户或客户端等信息。

下图说明了使用令牌自省实现 Introspection Flow 时不同实体之间的交互：

<br />
<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/10/29/Y2RWIUV9_client-cred-flow-introspection.png" alt="Client credential with introspection diagram" style={{width: '55%'}} />
</div>
<br />

请参阅 [实现 Client Credentials Grant](../tutorials/keycloak-oidc.md#实现-client-credentials-grant) 以获取使用 `openid-connect` 插件通过带有令牌自省的客户端凭据流与 Keycloak 集成的示例。

### Password Flow

Password Flow 在 [RFC 6749，第 4.3 节](https://datatracker.ietf.org/doc/html/rfc6749#section-4.3) 中定义。它专为受信任的应用程序而设计，允许它们使用用户的用户名和密码直接获取访问令牌。在此授权类型中，客户端应用程序将用户的凭据连同其自己的客户端 ID 和密钥一起发送到授权服务器，然后授权服务器对用户进行身份验证，如果有效，则颁发访问令牌。

虽然高效，但此流程仅适用于高度受信任的第一方应用程序，因为它要求应用程序直接处理敏感的用户凭据，如果在第三方环境中使用，则会带来重大安全风险。

下图说明了实施 Password Flow 时不同实体之间的交互：

<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/10/30/njkWZVgX_pass-grant.png" alt="Password flow diagram" style={{width: '70%'}} />
</div>
<br />

请参阅 [实现 Password Grant](../tutorials/keycloak-oidc.md#实现-password-grant) 获取使用 `openid-connect` 插件通过密码流与 Keycloak 集成的示例。

### Refresh Token Grant

Refresh Token Grant 在 [RFC 6749，第 6 节](https://datatracker.ietf.org/doc/html/rfc6749#section-6) 中定义。它允许客户端使用之前颁发的刷新令牌请求新的访问令牌，而无需用户重新进行身份验证。此流程通常在访问令牌过期时使用，允许客户端无需用户干预即可持续访问资源。刷新令牌与某些 OAuth 流程中的访问令牌一起颁发，其使用寿命和安全要求取决于授权服务器的配置。

下图说明了在实施 Password Grant 和 Refresh Token Grant 时不同实体之间的交互：

<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/10/30/YBF7rI6M_password-with-refresh-token.png" alt="Password grant with refresh token flow diagram" style={{width: '100%'}} />
</div>
<br />

请参阅 [Refresh Token](../tutorials/keycloak-oidc.md#refresh-token) 获取使用 `openid-connect` 插件通过带令牌刷新的密码流与 Keycloak 集成的示例。

## 故障排除

本节介绍使用此插件时的一些常见问题，以帮助您排除故障。

### APISIX 无法连接到 OpenID 提供商

如果 APISIX 无法解析或无法连接到 OpenID 提供商，请仔细检查配置文件 `config.yaml` 中的 DNS 设置并根据需要进行修改。

### `No Session State Found`

如果您在使用[授权码流](#authorization-code-flow) 时遇到 500 内部服务器错误并在日志中显示以下消息，则可能有多种原因。

```text
the error request to the redirect_uri path, but there's no session state found
```

#### 1. 重定向 URI 配置错误

一个常见的错误配置是将 `redirect_uri` 配置为与路由的 URI 相同。当用户发起访问受保护资源的请求时，请求直接命中重定向 URI，且请求中没有 session cookie，从而导致 no session state found 错误。

要正确配置重定向 URI，请确保 `redirect_uri` 与配置插件的路由匹配，但不要完全相同。例如，正确的配置是将路由的 `uri` 配置为 `/api/v1/*`，并将 `redirect_uri` 的路径部分配置为 `/api/v1/redirect`。

您还应该确保 `redirect_uri` 包含 scheme，例如 `http` 或 `https` 。

#### 2. Cookie 未发送或不存在

检查 [`SameSite`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#samesitesamesite-value) cookie 属性是否已正确设置（即您的应用程序是否需要跨站点发送 cookie），看看这是否会成为阻止 cookie 保存到浏览器的 cookie jar 或从浏览器发送的因素。

#### 3. 上游发送的标头太大

如果您有 NGINX 位于 APISIX 前面来代理客户端流量，请查看 NGINX 的 `error.log` 中是否观察到以下错误：

```text
upstream sent too big header while reading response header from upstream
```

如果是这样，请尝试将 `proxy_buffers` 、 `proxy_buffer_size` 和 `proxy_busy_buffers_size` 调整为更大的值。

另一个选项是配置 `session_content` 属性来调整在会话中存储哪些数据。例如，你可以将 `session_content.access_token` 设置为 `true`。

#### 4. 无效的客户端密钥

验证 `client_secret` 是否有效且正确。无效的 `client_secret` 将导致身份验证失败，并且不会返回任何令牌并将其存储在 session 中。

#### 5. PKCE IdP 配置

如果您使用授权码流程启用 PKCE，请确保您已将 IdP 客户端配置为使用 PKCE。例如，在 Keycloak 中，您应该在客户端的高级设置中配置 PKCE 质询方法：

<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/11/04/xvnCNb20_pkce-keycloak-revised.jpeg" alt="PKCE keycloak configuration" style={{width: '70%'}} />
</div>
