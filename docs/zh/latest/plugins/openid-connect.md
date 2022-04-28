---
title: openid-connect
keywords:
  - APISIX
  - Plugin
  - OpenID Connect
  - openid-connect
description: 本文介绍了关于 Apache APISIX `openid-connect` 插件的基本信息及使用方法。
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

`openid-connect` 插件通过 [OpenID Connect](https://openid.net/connect/) 为 APISIX 提供身份验证和自省功能。

## 属性

| 名称                                 | 类型     | 必选项 | 默认值                | 有效值  | 描述                                                                                                  |
| ------------------------------------ | ------- | ------ | --------------------- | ------- | ---------------------------------------------------------------------------------------------------- |
| client_id                            | string  | 是     |                       |               | OAuth 客户端 ID。                                                                               |
| client_secret                        | string  | 是     |                       |               | OAuth 客户端 secret。                                                                           |
| discovery                            | string  | 是     |                       |               | 身份服务器发现端点的 URL。                                                                      |
| scope                                | string  | 否     | "openid"              |               | 用于认证的范围。                                                                                 |
| realm                                | string  | 否     | "apisix"              |               | 用于认证的领域。                                                                                 |
| bearer_only                          | boolean | 否     | false                 |               | 设置为 `true` 时，将检查请求中带有承载令牌的授权标头。                                             |
| logout_path                          | string  | 否     | "/logout"             |               | 登出路径。                                                                                       |
| post_logout_redirect_uri             | string  | 否     |                       |               | 调用登出接口后想要跳转的 URL。                                                                    |
| redirect_uri                         | string  | 否     | "ngx.var.request_uri" |               | 身份提供者重定向返回的 URI。                                                                      |
| timeout                              | integer | 否     | 3                     | [1,...]       | 请求超时时间，单位为秒                                                                            |
| ssl_verify                           | boolean | 否     | false                 | [true, false] | 当设置为 `true` 时，验证身份提供者的 SSL 证书。                                                    |
| introspection_endpoint               | string  | 否     |                       |               | 身份服务器的令牌验证端点的 URL。                                                                   |
| introspection_endpoint_auth_method   | string  | 否     | "client_secret_basic" |               | 令牌自省的认证方法名称。                                                                           |
| public_key                           | string  | 否     |                       |               | 验证令牌的公钥。                                                                                  |
| token_signing_alg_values_expected    | string  | 否     |                       |               | 用于对令牌进行签名的算法。                                                                         |
| set_access_token_header              | boolean | 否     | true                  | [true, false] | 在请求头设置访问令牌。                                                                            |
| access_token_in_authorization_header | boolean | 否     | false                 | [true, false] | 当值为 `true` 时，将访问令牌设置在请求头参数 `Authorization`，否则将使用请求头参数 `X-Access-Token`。|
| set_id_token_header                  | boolean | 否     | true                  | [true, false] | 是否将 ID 令牌设置到请求头参数 `X-ID-Token`。                                                      |
| set_userinfo_header                  | boolean | 否     | true                  | [true, false] | 是否将用户信息对象设置到请求头参数 `X-Userinfo`。                                                   |

## 操作模式

`openid-connect` 插件提供三种操作模式：

1. 可以将**插件**配置为：仅验证预期会出现在请求头中的访问令牌。在这种模式下，没有令牌或带有无效令牌的请求将被拒绝。这需要将 `bearer_only` 属性设置为 `true` 并配置 `introspection_endpoint` 或 `public_key` 属性。这种操作模式可用于服务端之间的通信，在这种模式下，请求者可以合理地获取和管理有效的令牌。

2. 可以将**插件**配置为：通过 OIDC 授权对没有有效令牌的请求进行身份验证，其中该插件充当 OIDC 依赖方。在这种情况下，认证成功后，该插件可以获得并管理会话 Cookie 中的访问令牌，包含 Cookie 的后续请求将使用访问令牌。你需要将 `bearer_only` 属性设置为 `false` 才可以使用这种模式。这种操作模式可用于支持以下情况：客户端或请求者是通过 Web 浏览器进行交互的用户。

3. 该插件也可以通过将 `bearer_only` 设置为 `false`，并配置 `introspection_endpoint` 或 `public_key` 属性来支持以上两种场景。在这种情况下，对来自请求头的现有令牌的自省优先于依赖方流程。也就是说，如果一个请求中包含一个无效的令牌，那么该请求将会被拒绝，不会从重定向到 ID 提供者获得一个有效的令牌。

用于验证请求的方法会影响到 header，你可以在将请求发送到上游服务之前对其执行。

### 令牌自省

令牌自省是通过针对 Oauth 2 授权的服务器来验证令牌及相关请求。

首先，需要在身份认证服务器中创建受信任的客户端，并生成用于自省的有效令牌（JWT）。

下图展示了通过网关进行令牌自省的示例（成功）流程。

![token introspection](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/oauth-1.png)

以下示例是在 Route 上启用插件。该 Route 将通过自省请求头中提供的令牌来保护上游：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri":"/get",
    "plugins":{
        "proxy-rewrite":{
            "scheme":"https"
        },
        "openid-connect":{
            "client_id":"api_six_client_id",
            "client_secret":"client_secret_code",
            "discovery":"full_URL_of_the_discovery_endpoint",
            "introspection_endpoint":"full_URL_of_introspection_endpoint",
            "bearer_only":true,
            "realm":"master",
            "introspection_endpoint_auth_method":"client_secret_basic"
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "httpbin.org:443":1
        }
    }
}'
```

以下命令可用于访问新 Route：

```shell
curl -i -X GET http://127.0.0.1:9080/get \
-H "Host: httpbin.org" -H "Authorization: Bearer {replace_jwt_token}"
```

在此示例中，插件强制在请求头中设置访问令牌和 Userinfo 对象。

当 Oauth 2 授权服务器返回结果里除了令牌之外还有过期时间，其中令牌将在 APISIX 中缓存直至过期。有关更多详细信息，请参考：

1. [lua-resty-openidc](https://github.com/zmartzone/lua-resty-openidc) 的文档和源代码。
2. `exp` 字段的定义：[Introspection Response](https://tools.ietf.org/html/rfc7662#section-2.2)。

### 公钥自省

除了令牌自省外，还可以使用 JWT 令牌的公钥进行验证。如果使用了公共密钥和令牌自省端点，就会执行公共密钥工作流，而不是通过身份服务器进行验证。如果要减少额外的网络调用并加快过程，可以使用此方法。

以下示例展示了如何将公钥添加到 Route 中：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri":"/get",
    "plugins":{
        "proxy-rewrite":{
            "scheme":"https"
        },
        "openid-connect":{
            "client_id":"api_six_client_id",
            "client_secret":"client_secret_code",
            "discovery":"full_URL_of_the_discovery_endpoint",
            "bearer_only":true,
            "realm":"master",
            "token_signing_alg_values_expected":"RS256",
            "public_key":"-----BEGIN PUBLIC KEY-----
            {public_key}
            -----END PUBLIC KEY-----"
        }
    },
    "upstream":{
        "type":"roundrobin",
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
curl http://127.0.0.1:9080/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/get",
  "plugins": {
    "proxy-rewrite": {
      "scheme": "https"
    },
    "openid-connect": {
      "client_id": "api_six_client_id",
      "client_secret": "client_secret_code",
      "discovery": "full_URL_of_the_discovery_endpoint",
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

如果 APISIX 无法解析或者连接到身份提供者，请检查或修改配置文件（`./conf/config.yaml`）中的 DNS 设置。
