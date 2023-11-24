---
title: openid-connect
keywords:
  - Apache APISIX
  - API 网关
  - OpenID Connect
  - OIDC
description: OpenID Connect（OIDC）是基于 OAuth 2.0 的身份认证协议，APISIX 可以与支持该协议的身份认证服务对接，如 Okta、Keycloak、Ory Hydra、Authing 等，实现对客户端请求的身份认证。
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

[OpenID Connect](https://openid.net/connect/)（OIDC）是基于 OAuth 2.0 的身份认证协议，APISIX 可以与支持该协议的身份认证服务对接，如 Okta、Keycloak、Ory Hydra、Authing 等，实现对客户端请求的身份认证。

## 属性

| 名称                                 | 类型     | 必选项 | 默认值                | 有效值         | 描述                                                                                             |
| ------------------------------------ | ------- | ------ | --------------------- | ------------- | ------------------------------------------------------------------------------------------------ |
| client_id                            | string  | 是     |                       |               | OAuth 客户端 ID。                                                                                 |
| client_secret                        | string  | 是     |                       |               | OAuth 客户端 secret。                                                                            |
| discovery                            | string  | 是     |                       |               | 身份认证服务暴露的服务发现端点。                                                                            |
| scope                                | string  | 否     | "openid"              |               | OIDC 范围对应于应返回的有关经过身份验证的用户的信息，也称为 [claims](https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims)。默认值是`openid`，这是 OIDC 返回唯一标识经过身份验证的用户的 `sub` 声明所需的范围。可以附加其他范围并用空格分隔，例如 `openid email profile`。                                                                                  |
| realm                                | string  | 否     | "apisix"              |               | bearer token 无效时 [`WWW-Authenticate` 响应头](https://www.rfc-editor.org/rfc/rfc6750#section-3)中会伴随着的 `realm` 讯息。                                                                                |
| bearer_only                          | boolean | 否     | false                 |               | 当设置为 `true` 时，将仅检查请求头中的令牌（Token）。                                               |
| logout_path                          | string  | 否     | "/logout"             |               | 登出路径。                                                                                        |
| post_logout_redirect_uri             | string  | 否     |                       |               | 调用登出接口后想要跳转的 URL。                                                                     |
| redirect_uri                         | string  | 否     | "ngx.var.request_uri" |               | 身份提供者重定向返回的 URI。                                                                       |
| timeout                              | integer | 否     | 3                     | [1,...]       | 请求超时时间，单位为秒                                                                             |
| ssl_verify                           | boolean | 否     | false                 | [true, false] | 当设置为 `true` 时，验证身份提供者的 SSL 证书。                                                     |
| introspection_endpoint               | string  | 否     |                       |               | 用于内省访问令牌的身份提供者的令牌内省端点的 URL。如果未设置，则使用发现文档中提供的内省端点[作为后备](https://github.com/zmartzone/lua-resty-openidc/commit/cdaf824996d2b499de4c72852c91733872137c9c)。                                                                    |
| introspection_endpoint_auth_method   | string  | 否     | "client_secret_basic" |               |  令牌内省端点的身份验证方法。该值应是“introspection_endpoint_auth_methods_supported”[授权服务器元数据](https://www.rfc-editor.org/rfc/rfc8414.html)中指定的身份验证方法之一，如发现文档中所示，例如 `client_secret_basic`， `client_secret_post`， `private_key_jwt`，或 `client_secret_jwt`。                                                                        |
| token_endpoint_auth_method           | string  | 否     |                       |               | 令牌端点的身份验证方法。该值应是“token_endpoint_auth_methods_supported”[授权服务器元数据](https://www.rfc-editor.org/rfc/rfc8414.html)中指定的身份验证方法之一，如发现文档中所示，例如 `client_secret_basic`， `client_secret_post`， `private_key_jwt`，或 `client_secret_jwt`。如果不支持配置的方法，则回退到`token_endpoint_auth_methods_supported` 数组中的第一个方法。                                  |
| public_key                           | string  | 否     |                       |               | 验证令牌的公钥。                                                                                   |
| use_jwks                             | boolean | 否     | false                 |               | 当设置为 `true` 时，则会使用身份认证服务器的 JWKS 端点来验证令牌。                                    |
| use_pkce                             | boolean | 否     | false                 | [true, false] | 当设置为 `true` 时，则使用 PKEC（Proof Key for Code Exchange）。                                      |
| token_signing_alg_values_expected    | string  | 否     |                       |               | 用于对令牌进行签名的算法。                                                                          |
| set_access_token_header              | boolean | 否     | true                  | [true, false] | 在请求头设置访问令牌。默认使用请求头参数 `X-Access-Token`。                                                                              |
| access_token_in_authorization_header | boolean | 否     | false                 | [true, false] | 当设置为 `true` 以及 `set_access_token_header` 也设置为 `true`时，将访问令牌设置在请求头参数 `Authorization`。  |
| set_id_token_header                  | boolean | 否     | true                  | [true, false] | 是否将 ID 令牌设置到请求头参数 `X-ID-Token`。                                                       |
| set_userinfo_header                  | boolean | 否     | true                  | [true, false] | 是否将用户信息对象设置到请求头参数 `X-Userinfo`。                                                    |
| set_refresh_token_header             | boolean | 否     | false                 |               | 当设置为 `true` 并且刷新令牌可用时，则会将该属性设置在`X-Refresh-Token`请求头中。                      |
| session                              | object  | 否     |                       |               | 当设置 bearer_only 为 false 时，openid-connect 插件将使用 Authorization Code 在 IDP 上进行认证，因此你必须设置 session 相关设置。 |
| session.secret                       | string  | 是     | 自动生成               | 16 个以上字符  | 用于 session 加密和 HMAC 计算的密钥。 |
| unauth_action                        | string   | False    | "auth"                |  ["auth","deny","pass"]            | 指定未经身份验证的请求的响应类型。 `auth` 重定向到身份提供者，`deny` 导致 401 响应，`pass` 将允许请求而无需身份验证。                                                |
| proxy_opts                           | object  | 否    |                     |               | OpenID 服务器前面的 HTTP 代理服务器。 |
| proxy_opts                           | object  | 否    |                       |                                  | 用来访问身份认证服务器的代理服务器。                                                                                             |
| proxy_opts.http_proxy     | string  | 否    |                       | http://proxy-server:port         | HTTP 代理服务器地址。                                                                                                   |
| proxy_opts.https_proxy    | string  | 否    |                       | http://proxy-server:port         | HTTPS 代理服务器地址。                                                                                                  |
| proxy_opts.http_proxy_authorization  | string  | 否    |                       | Basic [base64 username:password] | 与 `http_proxy` 一起使用的默认 `Proxy-Authorization` 标头值。可以使用自定义 `Proxy-Authorization` 请求标头覆盖。                                                                 |
| proxy_opts.https_proxy_authorization | string  | 否    |                       | Basic [base64 username:password] | 与 `https_proxy` 一起使用的默认 `Proxy-Authorization` 标头值。无法使用自定义 `Proxy-Authorization` 请求标头覆盖，因为使用 HTTPS 时，授权在连接时完成。 |
| proxy_opts.no_proxy                  | string  | 否    |                       |                                  | 不应被代理的主机的逗号分隔列表。                                                                                               |
| authorization_params                 | object  | false    |                       |                                  | 在请求中发送到授权端点的附加参数                   |

注意：schema 中还定义了 `encrypt_fields = {"client_secret"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

## 使用场景

:::tip

教程：[使用 Keycloak 与 API 网关保护你的 API](https://apisix.apache.org/zh/blog/2022/07/06/use-keycloak-with-api-gateway-to-secure-apis/)

:::

该插件提供两种使用场景：

1. 应用之间认证授权：将 `bearer_only` 设置为 `true`，并配置 `introspection_endpoint` 或 `public_key` 属性。该场景下，请求头（Header）中没有令牌或无效令牌的请求将被拒绝。

2. 浏览器中认证授权：将 `bearer_only` 设置为 `false`。认证成功后，该插件可获得并管理 Cookie 中的令牌，后续请求将使用该令牌。在这种模式中，用户会话将作为 Cookie 存储在浏览器中，这些数据是加密的，因此你必须通过 `session.secret` 设置一个密钥用于加密。

### 令牌内省

令牌内省是通过针对 OAuth 2.0 授权的服务器来验证令牌及相关请求，详情请阅读 [Token Introspection](https://www.oauth.com/oauth2-servers/token-introspection-endpoint/)。

首先，需要在身份认证服务器中创建受信任的客户端，并生成用于内省的有效令牌（JWT）。下图是通过网关进行令牌内省的成功示例流程：

![token introspection](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/oauth-1.png)

以下示例是在路由上启用插件。该路由将通过内省请求头中提供的令牌来保护上游：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/get",
  "plugins":{
    "openid-connect":{
      "client_id": "${CLIENT_ID}",
      "client_secret": "${CLIENT_SECRET}",
      "discovery": "${DISCOVERY_ENDPOINT}",
      "introspection_endpoint": "${INTROSPECTION_ENDPOINT}",
      "bearer_only": true,
      "realm": "master",
      "introspection_endpoint_auth_method": "client_secret_basic"
    }
  },
  "upstream":{
    "type": "roundrobin",
    "nodes":{
      "httpbin.org:443":1
    }
  }
}'
```

以下命令可用于访问新路由：

```shell
curl -i -X GET http://127.0.0.1:9080/get -H "Authorization: Bearer {JWT_TOKEN}"
```

在此示例中，插件强制在请求头中设置访问令牌和 Userinfo 对象。

当 OAuth 2.0 授权服务器返回结果里除了令牌之外还有过期时间，其中令牌将在 APISIX 中缓存直至过期。更多信息请参考：

1. [lua-resty-openidc](https://github.com/zmartzone/lua-resty-openidc) 的文档和源代码。
2. `exp` 字段的定义：[Introspection Response](https://tools.ietf.org/html/rfc7662#section-2.2)。

### 公钥内省

除了令牌内省外，还可以使用 JWT 令牌的公钥进行验证。如果使用了公共密钥和令牌内省端点，就会执行公共密钥工作流，而不是通过身份服务器进行验证。该方式适可用于减少额外的网络调用并加快认证过程。

以下示例展示了如何将公钥添加到路由中：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/get",
  "plugins":{
    "openid-connect":{
      "client_id": "${CLIENT_ID}",
      "client_secret": "${CLIENT_SECRET}",
      "discovery": "${DISCOVERY_ENDPOINT}",
      "bearer_only": true,
      "realm": "master",
      "token_signing_alg_values_expected": "RS256",
      "public_key": "-----BEGIN PUBLIC KEY-----
      {public_key}
      -----END PUBLIC KEY-----"
    }
  },
  "upstream":{
    "type": "roundrobin",
    "nodes":{
      "httpbin.org:443":1
    }
  }
}'
```

#### 通过 OIDC 依赖方认证流程进行身份验证

当一个请求在请求头或会话 Cookie 中不包含访问令牌时，该插件可以充当 OIDC 依赖方并重定向到身份提供者的授权端点以通过 [OIDC authorization code flow](https://openid.net/specs/openid-connect-core-1_0.html#CodeFlowAuth)。

一旦用户通过身份提供者进行身份验证，插件将代表用户从身份提供者获取和管理访问令牌和更多信息。该信息当前存储在会话 Cookie 中，该插件将会识别 Cookie 并使用其中的信息，以避免再次执行认证流程。

以下示例是将此操作模式添加到 Route：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/get",
  "plugins": {
    "openid-connect": {
      "client_id": "${CLIENT_ID}",
      "client_secret": "${CLIENT_SECRET}",
      "discovery": "${DISCOVERY_ENDPOINT}",
      "bearer_only": false,
      "realm": "master"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:443": 1
    }
  }
}'
```

在以上示例中，该插件可以强制在配置的请求头中设置访问令牌、ID 令牌和 UserInfo 对象。

## 故障排除

1. 如果 APISIX 无法解析或者连接到身份认证服务（如 Okta、Keycloak、Authing 等），请检查或修改配置文件（`./conf/config.yaml`）中的 DNS 设置。

2. 如果遇到 `the error request to the redirect_uri path, but there's no session state found` 的错误，请检查 `redirect_uri` 参数配置：APISIX 会向身份认证服务发起身份认证请求，认证服务完成认证、授权后，会携带 ID Token 和 AccessToken 重定向到 `redirect_uri` 所配置的地址（例如 `http://127.0.0.1:9080/callback`），接着再次进入 APISIX 并在 OIDC 逻辑中完成 Token 交换的功能。因此 `redirect_uri` 需要满足以下条件：

- `redirect_uri` 需要能被当前 APISIX 所在路由捕获，比如当前路由的 `uri` 是 `/api/v1/*`, `redirect_uri` 可以填写为 `/api/v1/callback`；
- `redirect_uri`（`scheme:host`）的 `scheme` 和 `host` 是身份认证服务视角下访问 APISIX 所需的值。
