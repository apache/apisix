---
title: Set Up SSO with Keycloak (OIDC)
keywords:
  - APISIX
  - API 网关
  - OIDC
  - Keycloak
description: 本文介绍如何使用 openid-connect 插件，通过 authorization code grant、client credentials grant 和 password grant 将 APISIX 与 Keycloak 集成。
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

[OpenID Connect (OIDC)](https://openid.net/connect/) 是 [OAuth 2.0 协议](https://www.rfc-editor.org/rfc/rfc6749) 之上的简单身份层。它允许客户端基于身份提供者执行的身份验证来验证最终用户的身份，以及以可互操作和类似 REST 的方式获取有关最终​​用户的基本个人资料信息。借助 APISIX 和 [Keycloak](https://www.keycloak.org/)，您可以实现基于 OIDC 的身份验证流程来保护您的 API 并启用单点登录 (SSO)。

[Keycloak](https://www.keycloak.org/) 是适用于现代应用程序和服务的开源身份和访问管理解决方案。Keycloak 支持单点登录 (SSO)，这使得服务能够通过 OIDC 和 OAuth 2.0 等协议与 Keycloak 进行交互。此外，Keycloak 还支持将身份验证委托给第三方身份提供商，例如 Facebook 和 Google。

本教程将向您展示如何使用 [`openid-connect`](/hub/openid-connect) 插件，通过 [authorization code grant](#implement-authorization-code-grant)、[client credentials grant](#implement-client-credentials-grant) 和 [password grant](#implement-password-grant) 将 APISIX 与 Keycloak 集成。

## 配置 Keycloak

在 Docker 中以 [开发模式](https://www.keycloak.org/server/configuration#_starting_keycloak_in_development_mode) 启动一个名为 `apisix-quickstart-keycloak` 的 Keycloak 实例，管理员名称为 `quickstart-admin`，密码为 `quickstart-admin-pass`，暴露的端口映射到宿主机上的 `8080`：

```shell
docker run -d --name "apisix-quickstart-keycloak" \
  -e 'KEYCLOAK_ADMIN=quickstart-admin' \
  -e 'KEYCLOAK_ADMIN_PASSWORD=quickstart-admin-pass' \
  -p 8080:8080 \
  quay.io/keycloak/keycloak:18.0.2 start-dev
```

Keycloak 提供了一个易于使用的 Web UI，帮助管理员管理所有资源，例如客户端、角色和用户。

在浏览器中导航到 `http://localhost:8080` 以访问 Keycloak 网页，然后单击 __管理控制台__：

![web-ui](https://static.api7.ai/uploads/2023/03/30/ItcwYPIx_web-ui.png)

输入管理员用户名 `quickstart-admin` 和密码 `quickstart-admin-pass` 并登录：

![admin-signin](https://static.api7.ai/uploads/2023/03/30/6W3pjzE1_admin-signin.png)

您需要在以下步骤中保持登录状态来配置 Keycloak。

### 创建 Realm

Keycloak 中的 realm 是管理用户、凭证和角色等资源的工作区。不同领域中的资源彼此隔离。您需要为 APISIX 创建一个名为`quickstart-realm` 的 realm。

在左侧菜单中，将鼠标悬停在 **Master** 上，然后在下拉菜单中选择 __Add realm__：

![create-realm](https://static.api7.ai/uploads/2023/03/30/S1Xvqliv_create-realm.png)

输入 realm 名称 `quickstart-realm`，然后单击 `__Create__` 进行创建：

![add-realm](https://static.api7.ai/uploads/2023/03/30/jwb7QU8k_add-realm.png)

### 创建 Client

Keycloak 中的 client 是请求 Keycloak 对用户进行身份验证的实体。更多情况下，client 是希望使用 Keycloak 保护自身安全并提供单点登录解决方案的应用程序。APISIX 相当于负责向 Keycloak 发起身份验证请求的 client，因此您需要创建其对应的客户端，名为 `apisix-quickstart-client`。

单击 __Clients__ > __Create__，打开 __Add Client__ 页面：

![create-client](https://static.api7.ai/uploads/2023/03/30/qLom0axN_create-client.png)

输入 __Client ID__ 为 `apisix-quickstart-client`，然后选择 __Client Protocol__ 为 `openid-connect` 并 __Save__:

![add-client](https://static.api7.ai/uploads/2023/03/30/X5on2r7x_add-client.png)

Client `apisix-quickstart-client` 已创建。重定向到详细信息页面后，选择 `confidential` 作为 __Access Type__:

![config-client](https://static.api7.ai/uploads/2023/03/30/v70c8y9F_config-client.png)

当用户在 SSO 期间登录成功时，Keycloak 会携带状态和代码将客户端重定向到 __Valid Redirect URIs__ 中的地址。为简化操作，输入通配符 `*` 以将任何 URI 视为有效：

![client-redirect](https://static.api7.ai/uploads/2023/03/30/xLxcyVkn_client-redirect.png)

如果您正在 [使用 PKCE authorization code grant](#implement-authorization-code-grant)，请在客户端的高级设置中配置 PKCE 质询方法：

<div style={{textAlign: 'center'}}>
<img src="https://static.api7.ai/uploads/2024/11/04/xvnCNb20_pkce-keycloak-revised.jpeg" alt="PKCE keycloak configuration" style={{width: '70%'}} />
</div>

如果您正在实施 [client credentials grant](#implement-client-credentials-grant)，请为 client 启用服务帐户：

![enable-service-account](https://static.api7.ai/uploads/2023/12/29/h1uNtghd_sa.png)

选择 __Save__ 以应用自定义配置。

### 创建 User

Keycloak 中的用户是能够登录系统的实体。他们可以拥有与自己相关的属性，例如用户名、电子邮件和地址。

如果您只实施 [client credentials grant](#implement-client-credentials-grant)，则可以 [跳过此部分](#obtain-the-oidc-configuration)。

点击 __Users__ > __Add user__ 打开 __Add user__ 页面：

![create-user](https://static.api7.ai/uploads/2023/03/30/onQEp23L_create-user.png)

点击 __Users__ > __Add user__ 打开 __Add user__ 页面：

![add-user](https://static.api7.ai/uploads/2023/03/30/EKhuhgML_add-user.png)

点击 __Credentials__，然后将 __Password__ 设置为 `quickstart-user-pass`。将 __Temporary__ 切换为 `OFF` 以关闭限制，这样您第一次登录时就无需更改密码：

![user-pass](https://static.api7.ai/uploads/2023/03/30/rQKEAEnh_user-pass.png)

## 获取 OIDC 配置

在本节中，您将从 Keycloak 获取关键的 OIDC 配置并将其定义为 shell 变量。本节之后的步骤将使用这些变量通过 shell 命令配置 OIDC。

:::info

打开一个单独的终端按照步骤操作并定义相关的 shell 变量。然后本节之后的步骤可以直接使用定义的变量。

:::

### 获取发现端点

单击 __Realm Settings__，然后右键单击 __OpenID Endpoints Configuration__ 并复制链接。

![get-discovery](https://static.api7.ai/uploads/2023/03/30/526lbJbg_get-discovery.png)

该链接应与以下内容相同：

```text
http://localhost:8080/realms/quickstart-realm/.well-known/openid-configuration
```

在 OIDC 身份验证期间需要使用此端点公开的配置值。使用您的主机 IP 更新地址并保存到环境变量：

```shell
export KEYCLOAK_IP=192.168.42.145    # replace with your host IP
export OIDC_DISCOVERY=http://${KEYCLOAK_IP}:8080/realms/quickstart-realm/.well-known/openid-configuration
```

### 获取客户端 ID 和密钥

单击 __Clients__ > `apisix-quickstart-client` > __Credentials__，并从 __Secret__ 复制客户端密钥：

![client-ID](https://static.api7.ai/uploads/2023/03/30/MwYmU20v_client-id.png)

![client-secret](https://static.api7.ai/uploads/2023/03/30/f9iOG8aN_client-secret.png)

将 OIDC 客户端 ID 和密钥保存到环境变量：

```shell
export OIDC_CLIENT_ID=apisix-quickstart-client
export OIDC_CLIENT_SECRET=bSaIN3MV1YynmtXvU8lKkfeY0iwpr9cH  # replace with your value
```

## 实现 Authorization Code Grant

Authorization Code Grant 由 Web 和移动应用程序使用。流程从授权服务器在浏览器中显示登录页面开始，用户可以在其中输入其凭据。在此过程中，将短期授权码交换为访问令牌，APISIX 将其存储在浏览器会话 cookie 中，并将随访问上游资源服务器的每次请求一起发送。

要实现 Authorization Code Grant，请使用 `openid-connect` 插件创建一个路由，如下所示：

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "auth-with-oidc",
  "uri":"/anything/*",
  "plugins": {
    "openid-connect": {
      "bearer_only": false,
      "session": {
        "secret": "change_to_whatever_secret_you_want"
      },
      "client_id": "'"$OIDC_CLIENT_ID"'",
      "client_secret": "'"$OIDC_CLIENT_SECRET"'",
      "discovery": "'"$OIDC_DISCOVERY"'",
      "scope": "openid profile",
      "redirect_uri": "http://localhost:9080/anything/callback"
    }
  },
  "upstream":{
    "type":"roundrobin",
    "nodes":{
      "httpbin.org:80":1
    }
  }
}'
```

或者，如果您想使用 PKCE 实现 authorization code grant，请使用 `openid-connect` 插件创建一个路由如下：

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "auth-with-oidc",
  "uri":"/anything/*",
  "plugins": {
    "openid-connect": {
      "bearer_only": false,
      "session": {
        "secret": "change_to_whatever_secret_you_want"
      },
      "use_pkce": true,
      "client_id": "'"$OIDC_CLIENT_ID"'",
      "client_secret": "'"$OIDC_CLIENT_SECRET"'",
      "discovery": "'"$OIDC_DISCOVERY"'",
      "scope": "openid profile",
      "redirect_uri": "http://localhost:9080/anything/callback"
    }
  },
  "upstream":{
    "type":"roundrobin",
    "nodes":{
      "httpbin.org:80":1
    }
  }
}'
```

### 使用有效凭证进行验证

在浏览器中导航至 `http://127.0.0.1:9080/anything/test`。请求将重定向到登录页面：

![test-sign-on](https://static.api7.ai/uploads/2023/03/30/i38u1x9a_validate-sign.png)

使用正确的用户名 `quickstart-user` 和密码 `quickstart-user-pass` 登录。如果成功，请求将被转发到 `httpbin.org`，您应该会看到类似以下内容的响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "text/html..."
    ...
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 59.71.244.81",
  "url": "http://127.0.0.1/anything/test"
}
```

### 使用无效凭证进行验证

使用错误的凭证登录。您应该会看到身份验证失败：

![test-sign-failed](https://static.api7.ai/uploads/2023/03/31/YOuSYX1r_validate-sign-failed.png)

## 实现 Client Credential Grant

在 client credential grant 中，客户端无需任何用户参与即可获得访问令牌。它通常用于机器对机器 (M2M) 通信。

要实现 client credential grant，请使用 `openid-connect` 插件创建路由，以使用身份提供者的 JWKS 端点来验证令牌。端点将从发现文档中获取。

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "auth-with-oidc",
  "uri":"/anything/*",
  "plugins": {
    "openid-connect": {
      "use_jwks": true,
      "client_id": "'"$OIDC_CLIENT_ID"'",
      "client_secret": "'"$OIDC_CLIENT_SECRET"'",
      "discovery": "'"$OIDC_DISCOVERY"'",
      "scope": "openid profile",
      "redirect_uri": "http://localhost:9080/anything/callback"
    }
  },
  "upstream":{
    "type":"roundrobin",
    "nodes":{
      "httpbin.org:80":1
    }
  }
}'
```

或者，如果您想使用自省端点来验证令牌，请按如下方式创建路由：

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "auth-with-oidc",
  "uri":"/anything/*",
  "plugins": {
    "openid-connect": {
      "bearer_only": true,
      "client_id": "'"$OIDC_CLIENT_ID"'",
      "client_secret": "'"$OIDC_CLIENT_SECRET"'",
      "discovery": "'"$OIDC_DISCOVERY"'",
      "scope": "openid profile",
      "redirect_uri": "http://localhost:9080/anything/callback"
    }
  },
  "upstream":{
    "type":"roundrobin",
    "nodes":{
      "httpbin.org:80":1
    }
  }
}'
```

自省端点将从发现文档中获取。

### 使用有效访问令牌进行验证

在 [令牌端点](https://www.keycloak.org/docs/latest/securing_apps/#token-endpoint) 获取 Keycloak 服务器的访问令牌：

```shell
curl -i "http://$KEYCLOAK_IP:8080/realms/quickstart-realm/protocol/openid-connect/token" -X POST \
  -d 'grant_type=client_credentials' \
  -d 'client_id='$OIDC_CLIENT_ID'' \
  -d 'client_secret='$OIDC_CLIENT_SECRET''
```

预期响应类似于以下内容：

```text
{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJoT3ludlBPY2d6Y3VWWnYtTU42bXZKMUczb0dOX2d6MFo3WFl6S2FSa1NBIn0.eyJleHAiOjE3MDM4MjU1NjQsImlhdCI6MTcwMzgyNTI2NCwianRpIjoiMWQ4NWE4N2UtZDFhMC00NThmLThiMTItNGZiYWM2ODA5YmYwIiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguMS44Mzo4MDgwL3JlYWxtcy9xdWlja3N0YXJ0LXJlYWxtIiwiYXVkIjoiYWNjb3VudCIsInN1YiI6IjE1OGUzOWFlLTk0YjAtNDI3Zi04ZGU3LTU3MTRhYWYwOGYzOSIsInR5cCI6IkJlYXJlciIsImF6cCI6ImFwaXNpeC1xdWlja3N0YXJ0LWNsaWVudCIsImFjciI6IjEiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiZGVmYXVsdC1yb2xlcy1xdWlja3N0YXJ0LXJlYWxtIiwib2ZmbGluZV9hY2Nlc3MiLCJ1bWFfYXV0aG9yaXphdGlvbiJdfSwicmVzb3VyY2VfYWNjZXNzIjp7ImFjY291bnQiOnsicm9sZXMiOlsibWFuYWdlLWFjY291bnQiLCJtYW5hZ2UtYWNjb3VudC1saW5rcyIsInZpZXctcHJvZmlsZSJdfX0sInNjb3BlIjoiZW1haWwgcHJvZmlsZSIsImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwiY2xpZW50SG9zdCI6IjE3Mi4xNy4wLjEiLCJjbGllbnRJZCI6ImFwaXNpeC1xdWlja3N0YXJ0LWNsaWVudCIsInByZWZlcnJlZF91c2VybmFtZSI6InNlcnZpY2UtYWNjb3VudC1hcGlzaXgtcXVpY2tzdGFydC1jbGllbnQiLCJjbGllbnRBZGRyZXNzIjoiMTcyLjE3LjAuMSJ9.TltzSXqrJuVID7aGrb35jn-oc07U_-jugSn-3jKz4A44LwtAsME_8b3qkmR4boMOIht_5pF6bnnp70MFAlg6JKu4_yIQDxF_GAHjnZXEO8OCKhtIKwXm2w-hnnJVIhIdGkIVkbPP0HfILuar_m0hpa53VpPBGYR-OS4pyh0KTUs8MB22xAEqyz9zjCm6SX9vXCqgeVkSpRW2E8NaGEbAdY25uY-ZC4dI_pON87Ey5e8GdD6HQLXQlGIOdCDi3N7k0HDoD9TZRv2bMRPfy4zVYm1ZlClIuF79A-ZBwr0c-XYuq7t6EY0gPGEXB-s0SaKlrIU5S9JBeVXRzYvqAih41g","expires_in":300,"refresh_expires_in":0,"token_type":"Bearer","not-before-policy":0,"scope":"email profile"}
```

将访问令牌保存到环境变量：

```shell
# replace with your access token
export ACCESS_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJoT3ludlBPY2d6Y3VWWnYtTU42bXZKMUczb0dOX2d6MFo3WFl6S2FSa1NBIn0.eyJleHAiOjE3MDM4MjU1NjQsImlhdCI6MTcwMzgyNTI2NCwianRpIjoiMWQ4NWE4N2UtZDFhMC00NThmLThiMTItNGZiYWM2ODA5YmYwIiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguMS44Mzo4MDgwL3JlYWxtcy9xdWlja3N0YXJ0LXJlYWxtIiwiYXVkIjoiYWNjb3VudCIsInN1YiI6IjE1OGUzOWFlLTk0YjAtNDI3Zi04ZGU3LTU3MTRhYWYwOGYzOSIsInR5cCI6IkJlYXJlciIsImF6cCI6ImFwaXNpeC1xdWlja3N0YXJ0LWNsaWVudCIsImFjciI6IjEiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiZGVmYXVsdC1yb2xlcy1xdWlja3N0YXJ0LXJlYWxtIiwib2ZmbGluZV9hY2Nlc3MiLCJ1bWFfYXV0aG9yaXphdGlvbiJdfSwicmVzb3VyY2VfYWNjZXNzIjp7ImFjY291bnQiOnsicm9sZXMiOlsibWFuYWdlLWFjY291bnQiLCJtYW5hZ2UtYWNjb3VudC1saW5rcyIsInZpZXctcHJvZmlsZSJdfX0sInNjb3BlIjoiZW1haWwgcHJvZmlsZSIsImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwiY2xpZW50SG9zdCI6IjE3Mi4xNy4wLjEiLCJjbGllbnRJZCI6ImFwaXNpeC1xdWlja3N0YXJ0LWNsaWVudCIsInByZWZlcnJlZF91c2VybmFtZSI6InNlcnZpY2UtYWNjb3VudC1hcGlzaXgtcXVpY2tzdGFydC1jbGllbnQiLCJjbGllbnRBZGRyZXNzIjoiMTcyLjE3LjAuMSJ9.TltzSXqrJuVID7aGrb35jn-oc07U_-jugSn-3jKz4A44LwtAsME_8b3qkmR4boMOIht_5pF6bnnp70MFAlg6JKu4_yIQDxF_GAHjnZXEO8OCKhtIKwXm2w-hnnJVIhIdGkIVkbPP0HfILuar_m0hpa53VpPBGYR-OS4pyh0KTUs8MB22xAEqyz9zjCm6SX9vXCqgeVkSpRW2E8NaGEbAdY25uY-ZC4dI_pON87Ey5e8GdD6HQLXQlGIOdCDi3N7k0HDoD9TZRv2bMRPfy4zVYm1ZlClIuF79A-ZBwr0c-XYuq7t6EY0gPGEXB-s0SaKlrIU5S9JBeVXRzYvqAih41g"
```

使用有效的访问令牌向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything/test" -H "Authorization: Bearer $ACCESS_TOKEN"
```

`HTTP/1.1 200 OK` 响应验证对上游资源的请求是否已获得授权。

### 使用无效访问令牌进行验证

使用无效访问令牌向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything/test" -H "Authorization: Bearer invalid-access-token"
```

`HTTP/1.1 401 Unauthorized` 响应验证 OIDC 插件是否拒绝了具有无效访问令牌的请求。

### 验证无访问令牌

向无访问令牌的路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything/test"
```

`HTTP/1.1 401 Unauthorized` 响应验证 OIDC 插件拒绝没有访问令牌的请求。

## 实施 Password Grant

Password Grant 是一种将用户凭据交换为访问令牌的传统方法。

要实施 Password Grant，请使用 `openid-connect` 插件创建路由，以使用身份提供者的 JWKS 端点来验证令牌。端点将从发现文档中获取。

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "auth-with-oidc",
  "uri":"/anything/*",
  "plugins": {
    "openid-connect": {
      "use_jwks": true,
      "client_id": "'"$OIDC_CLIENT_ID"'",
      "client_secret": "'"$OIDC_CLIENT_SECRET"'",
      "discovery": "'"$OIDC_DISCOVERY"'",
      "scope": "openid profile",
      "redirect_uri": "http://localhost:9080/anything/callback"
    }
  },
  "upstream":{
    "type":"roundrobin",
    "nodes":{
      "httpbin.org:80":1
    }
  }
}'
```

### 使用有效访问令牌进行验证

在 [令牌端点](https://www.keycloak.org/docs/latest/securing_apps/#token-endpoint) 获取 Keycloak 服务器的访问令牌：

```shell
OIDC_USER=quickstart-user
OIDC_PASSWORD=quickstart-user-pass
curl -i "http://$KEYCLOAK_IP:8080/realms/quickstart-realm/protocol/openid-connect/token" -X POST \
  -d 'grant_type=password' \
  -d 'client_id='$OIDC_CLIENT_ID'' \
  -d 'client_secret='$OIDC_CLIENT_SECRET'' \
  -d 'username='$OIDC_USER'' \
  -d 'password='$OIDC_PASSWORD''
```

预期响应类似于以下内容：

```text
{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ6U3FFaXN6VlpuYi1sRWMzZkp0UHNpU1ZZcGs4RGN3dXI1Mkx5V05aQTR3In0.eyJleHAiOjE2ODAxNjA5NjgsImlhdCI6MTY4MDE2MDY2OCwianRpIjoiMzQ5MTc4YjQtYmExZC00ZWZjLWFlYTUtZGY2MzJiMDJhNWY5IiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguNDIuMTQ1OjgwODAvcmVhbG1zL3F1aWNrc3RhcnQtcmVhbG0iLCJhdWQiOiJhY2NvdW50Iiwic3ViIjoiMTg4MTVjM2EtNmQwNy00YTY2LWJjZjItYWQ5NjdmMmIwMTFmIiwidHlwIjoiQmVhcmVyIiwiYXpwIjoiYXBpc2l4LXF1aWNrc3RhcnQtY2xpZW50Iiwic2Vzc2lvbl9zdGF0ZSI6ImIxNmIyNjJlLTEwNTYtNDUxNS1hNDU1LWYyNWUwNzdjY2I3NiIsImFjciI6IjEiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiZGVmYXVsdC1yb2xlcy1xdWlja3N0YXJ0LXJlYWxtIiwib2ZmbGluZV9hY2Nlc3MiLCJ1bWFfYXV0aG9yaXphdGlvbiJdfSwicmVzb3VyY2VfYWNjZXNzIjp7ImFjY291bnQiOnsicm9sZXMiOlsibWFuYWdlLWFjY291bnQiLCJtYW5hZ2UtYWNjb3VudC1saW5rcyIsInZpZXctcHJvZmlsZSJdfX0sInNjb3BlIjoicHJvZmlsZSBlbWFpbCIsInNpZCI6ImIxNmIyNjJlLTEwNTYtNDUxNS1hNDU1LWYyNWUwNzdjY2I3NiIsImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwicHJlZmVycmVkX3VzZXJuYW1lIjoicXVpY2tzdGFydC11c2VyIn0.uD_7zfZv5182aLXu9-YBzBDK0nr2mE4FWb_4saTog2JTqFTPZZa99Gm8AIDJx2ZUcZ_ElkATqNUZ4OpWmL2Se5NecMw3slJReewjD6xgpZ3-WvQuTGpoHdW5wN9-Rjy8ungilrnAsnDA3tzctsxm2w6i9KISxvZrzn5Rbk-GN6fxH01VC5eekkPUQJcJgwuJiEiu70SjGnm21xDN4VGkNRC6jrURoclv3j6AeOqDDIV95kA_MTfBswDFMCr2PQlj5U0RTndZqgSoxwFklpjGV09Azp_jnU7L32_Sq-8coZd0nj5mSdbkJLJ8ZDQDV_PP3HjCP7EHdy4P6TyZ7oGvjw","expires_in":300,"refresh_expires_in":1800,"refresh_token":"eyJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI0YjFiNTQ3Yi0zZmZjLTQ5YzQtYjE2Ni03YjdhNzIxMjk1ODcifQ.eyJleHAiOjE2ODAxNjI0NjgsImlhdCI6MTY4MDE2MDY2OCwianRpIjoiYzRjNjNlMTEtZTdlZS00ZmEzLWJlNGYtNDMyZWQ4ZmY5OTQwIiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguNDIuMTQ1OjgwODAvcmVhbG1zL3F1aWNrc3RhcnQtcmVhbG0iLCJhdWQiOiJodHRwOi8vMTkyLjE2OC40Mi4xNDU6ODA4MC9yZWFsbXMvcXVpY2tzdGFydC1yZWFsbSIsInN1YiI6IjE4ODE1YzNhLTZkMDctNGE2Ni1iY2YyLWFkOTY3ZjJiMDExZiIsInR5cCI6IlJlZnJlc2giLCJhenAiOiJhcGlzaXgtcXVpY2tzdGFydC1jbGllbnQiLCJzZXNzaW9uX3N0YXRlIjoiYjE2YjI2MmUtMTA1Ni00NTE1LWE0NTUtZjI1ZTA3N2NjYjc2Iiwic2NvcGUiOiJwcm9maWxlIGVtYWlsIiwic2lkIjoiYjE2YjI2MmUtMTA1Ni00NTE1LWE0NTUtZjI1ZTA3N2NjYjc2In0.8xYP4bhDg1U9B5cTaEVD7B4oxNp8wwAYEynUne_Jm78","token_type":"Bearer","not-before-policy":0,"session_state":"b16b262e-1056-4515-a455-f25e077ccb76","scope":"profile email"}
```

将访问令牌和刷新令牌保存到环境变量中。刷新令牌将在刷新令牌步骤中使用。

```shell
# replace with your access token
export ACCESS_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ6U3FFaXN6VlpuYi1sRWMzZkp0UHNpU1ZZcGs4RGN3dXI1Mkx5V05aQTR3In0.eyJleHAiOjE2ODAxNjA5NjgsImlhdCI6MTY4MDE2MDY2OCwianRpIjoiMzQ5MTc4YjQtYmExZC00ZWZjLWFlYTUtZGY2MzJiMDJhNWY5IiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguNDIuMTQ1OjgwODAvcmVhbG1zL3F1aWNrc3RhcnQtcmVhbG0iLCJhdWQiOiJhY2NvdW50Iiwic3ViIjoiMTg4MTVjM2EtNmQwNy00YTY2LWJjZjItYWQ5NjdmMmIwMTFmIiwidHlwIjoiQmVhcmVyIiwiYXpwIjoiYXBpc2l4LXF1aWNrc3RhcnQtY2xpZW50Iiwic2Vzc2lvbl9zdGF0ZSI6ImIxNmIyNjJlLTEwNTYtNDUxNS1hNDU1LWYyNWUwNzdjY2I3NiIsImFjciI6IjEiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiZGVmYXVsdC1yb2xlcy1xdWlja3N0YXJ0LXJlYWxtIiwib2ZmbGluZV9hY2Nlc3MiLCJ1bWFfYXV0aG9yaXphdGlvbiJdfSwicmVzb3VyY2VfYWNjZXNzIjp7ImFjY291bnQiOnsicm9sZXMiOlsibWFuYWdlLWFjY291bnQiLCJtYW5hZ2UtYWNjb3VudC1saW5rcyIsInZpZXctcHJvZmlsZSJdfX0sInNjb3BlIjoicHJvZmlsZSBlbWFpbCIsInNpZCI6ImIxNmIyNjJlLTEwNTYtNDUxNS1hNDU1LWYyNWUwNzdjY2I3NiIsImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwicHJlZmVycmVkX3VzZXJuYW1lIjoicXVpY2tzdGFydC11c2VyIn0.uD_7zfZv5182aLXu9-YBzBDK0nr2mE4FWb_4saTog2JTqFTPZZa99Gm8AIDJx2ZUcZ_ElkATqNUZ4OpWmL2Se5NecMw3slJReewjD6xgpZ3-WvQuTGpoHdW5wN9-Rjy8ungilrnAsnDA3tzctsxm2w6i9KISxvZrzn5Rbk-GN6fxH01VC5eekkPUQJcJgwuJiEiu70SjGnm21xDN4VGkNRC6jrURoclv3j6AeOqDDIV95kA_MTfBswDFMCr2PQlj5U0RTndZqgSoxwFklpjGV09Azp_jnU7L32_Sq-8coZd0nj5mSdbkJLJ8ZDQDV_PP3HjCP7EHdy4P6TyZ7oGvjw"
export REFRESH_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI0YjFiNTQ3Yi0zZmZjLTQ5YzQtYjE2Ni03YjdhNzIxMjk1ODcifQ.eyJleHAiOjE2ODAxNjI0NjgsImlhdCI6MTY4MDE2MDY2OCwianRpIjoiYzRjNjNlMTEtZTdlZS00ZmEzLWJlNGYtNDMyZWQ4ZmY5OTQwIiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguNDIuMTQ1OjgwODAvcmVhbG1zL3F1aWNrc3RhcnQtcmVhbG0iLCJhdWQiOiJodHRwOi8vMTkyLjE2OC40Mi4xNDU6ODA4MC9yZWFsbXMvcXVpY2tzdGFydC1yZWFsbSIsInN1YiI6IjE4ODE1YzNhLTZkMDctNGE2Ni1iY2YyLWFkOTY3ZjJiMDExZiIsInR5cCI6IlJlZnJlc2giLCJhenAiOiJhcGlzaXgtcXVpY2tzdGFydC1jbGllbnQiLCJzZXNzaW9uX3N0YXRlIjoiYjE2YjI2MmUtMTA1Ni00NTE1LWE0NTUtZjI1ZTA3N2NjYjc2Iiwic2NvcGUiOiJwcm9maWxlIGVtYWlsIiwic2lkIjoiYjE2YjI2MmUtMTA1Ni00NTE1LWE0NTUtZjI1ZTA3N2NjYjc2In0.8xYP4bhDg1U9B5cTaEVD7B4oxNp8wwAYEynUne_Jm78"
```

使用有效的访问令牌向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything/test" -H "Authorization: Bearer $ACCESS_TOKEN"
```

`HTTP/1.1 200 OK` 响应验证对上游资源的请求是否已获得授权。

### 使用无效访问令牌进行验证

使用无效访问令牌向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything/test" -H "Authorization: Bearer invalid-access-token"
```

`HTTP/1.1 401 Unauthorized` 响应验证 OIDC 插件是否拒绝了具有无效访问令牌的请求。

### 验证无访问令牌

向无访问令牌的路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything/test"
```

`HTTP/1.1 401 Unauthorized` 响应验证 OIDC 插件拒绝没有访问令牌的请求。

### 刷新令牌

要刷新访问令牌，请向 Keycloak 令牌端点发送请求，如下所示：

```shell
curl -i "http://$KEYCLOAK_IP:8080/realms/quickstart-realm/protocol/openid-connect/token" -X POST \
  -d 'grant_type=refresh_token' \
  -d 'client_id='$OIDC_CLIENT_ID'' \
  -d 'client_secret='$OIDC_CLIENT_SECRET'' \
  -d 'refresh_token='$REFRESH_TOKEN''
```

您应该看到类似以下的响应，其中包含新的访问令牌和刷新令牌，您可以将其用于后续请求和令牌刷新：

```text
{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJTdnVwLXlPMHhDdTJBVi1za2pCZ0h6SHZNaG1mcDVDQWc0NHpYb2QxVTlNIn0.eyJleHAiOjE3MzAyNzQ3NDUsImlhdCI6MTczMDI3NDQ0NSwianRpIjoiMjk2Mjk5MWUtM2ExOC00YWFiLWE0NzAtODgxNWEzNjZjZmM4IiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguMTUyLjU6ODA4MC9yZWFsbXMvcXVpY2tzdGFydC1yZWFsbSIsImF1ZCI6ImFjY291bnQiLCJzdWIiOiI2ZWI0ZTg0Yy00NmJmLTRkYzUtOTNkMC01YWM5YzE5MWU0OTciLCJ0eXAiOiJCZWFyZXIiLCJhenAiOiJhcGlzaXgtcXVpY2tzdGFydC1jbGllbnQiLCJzZXNzaW9uX3N0YXRlIjoiNTU2ZTQyYjktMjE2Yi00NTEyLWE5ZjAtNzE3ZTAyYTQ4MjZhIiwiYWNyIjoiMSIsInJlYWxtX2FjY2VzcyI6eyJyb2xlcyI6WyJkZWZhdWx0LXJvbGVzLXF1aWNrc3RhcnQtcmVhbG0iLCJvZmZsaW5lX2FjY2VzcyIsInVtYV9hdXRob3JpemF0aW9uIl19LCJyZXNvdXJjZV9hY2Nlc3MiOnsiYWNjb3VudCI6eyJyb2xlcyI6WyJtYW5hZ2UtYWNjb3VudCIsIm1hbmFnZS1hY2NvdW50LWxpbmtzIiwidmlldy1wcm9maWxlIl19fSwic2NvcGUiOiJlbWFpbCBwcm9maWxlIiwic2lkIjoiNTU2ZTQyYjktMjE2Yi00NTEyLWE5ZjAtNzE3ZTAyYTQ4MjZhIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJxdWlja3N0YXJ0LXVzZXIifQ.KLqn1LQdazoPBqLLR856C35XpqbMO9I7WFt3KrDxZF1N8vwv4AvZYWI_2rsbdjCakh9JmPgyYRgEGufYLiDBsqy9CrMVejAIJPYsJIonIXBCp5Ysu92ODJuqtTKuuJ6K7dam7fisBFfCBbVvGspnZ3p0caedpOaF_kSd-F8ARHKVsmkuX3_ucDrP3UctjEXHezefTY4YHjNMB9wuMDPXX2vXt2BsOasnznsIHHHX-ZH8JY6eEfWPtfx0qAED6lVZICT6Rqj_j5-Cf9ogzFtLyy_XvtG9BbHME2B8AXYpxdzqxOxmVVbZdrB8elfmFjs1R3vUn2r3xA9hO_znZo_IoQ","expires_in":300,"refresh_expires_in":1800,"refresh_token":"eyJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICIwYWYwZTAwYy0xMThjLTRkNDktYmIwMS1iMDIwNDE3MmFjMzIifQ.eyJleHAiOjE3MzAyNzYyNDUsImlhdCI6MTczMDI3NDQ0NSwianRpIjoiZGQyZTJmYTktN2Y3Zi00MjM5LWEwODAtNWQyZDFiZTdjNzk4IiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguMTUyLjU6ODA4MC9yZWFsbXMvcXVpY2tzdGFydC1yZWFsbSIsImF1ZCI6Imh0dHA6Ly8xOTIuMTY4LjE1Mi41OjgwODAvcmVhbG1zL3F1aWNrc3RhcnQtcmVhbG0iLCJzdWIiOiI2ZWI0ZTg0Yy00NmJmLTRkYzUtOTNkMC01YWM5YzE5MWU0OTciLCJ0eXAiOiJSZWZyZXNoIiwiYXpwIjoiYXBpc2l4LXF1aWNrc3RhcnQtY2xpZW50Iiwic2Vzc2lvbl9zdGF0ZSI6IjU1NmU0MmI5LTIxNmItNDUxMi1hOWYwLTcxN2UwMmE0ODI2YSIsInNjb3BlIjoiZW1haWwgcHJvZmlsZSIsInNpZCI6IjU1NmU0MmI5LTIxNmItNDUxMi1hOWYwLTcxN2UwMmE0ODI2YSJ9.Uad4BVuojHfyxqedFT5BHliWjIqVDbjM-Xeme0G2AAg","token_type":"Bearer","not-before-policy":0,"session_state":"556e42b9-216b-4512-a9f0-717e02a4826a","scope":"email profile"}
```
