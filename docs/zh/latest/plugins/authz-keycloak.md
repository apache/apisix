---
title: authz-keycloak
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Authz Keycloak
  - authz-keycloak
description: The authz-keycloak Plugin integrates with Keycloak for user authentication and authorization, enhancing API security and management.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/authz-keycloak" />
</head>

## 描述

`authz-keycloak` 插件可用于通过 [Keycloak Identity Server](https://www.keycloak.org/) 进行认证。

:::tip

虽然本插件是针对 Keycloak 开发的，但也应该适用于任何符合 OAuth/OIDC 和 UMA 规范的身份提供商。

:::

有关 Keycloak 的更多信息，请参阅 [Authorization Services Guide](https://www.keycloak.org/docs/latest/authorization_services/)。

## 属性

| 名称                                         | 类型          | 必填 | 默认值                                        | 有效值                                                                 | 描述                                                                                                                                                                                                                                                  |
|----------------------------------------------|---------------|------|-----------------------------------------------|------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| discovery                                    | string        | 否   |                                               | https://host.domain/realms/foo/.well-known/uma2-configuration      | Keycloak Authorization Services 的[发现文档](https://www.keycloak.org/docs/latest/authorization_services/index.html) URL。                                                                                                                            |
| token_endpoint                               | string        | 否   |                                               | https://host.domain/realms/foo/protocol/openid-connect/token       | 支持 `urn:ietf:params:oauth:grant-type:uma-ticket` 授权类型的符合 OAuth2 规范的令牌端点。若设置，将覆盖从发现文档中获取的值。                                                                                                                          |
| resource_registration_endpoint               | string        | 否   |                                               | https://host.domain/realms/foo/authz/protection/resource_set       | 符合 UMA 规范的资源注册端点。若设置，将覆盖从发现文档中获取的值。                                                                                                                                                                                     |
| client_id                                    | string        | 是   |                                               |                                                                        | 客户端尝试访问的资源服务器的标识符。                                                                                                                                                                                                                  |
| client_secret                                | string        | 否   |                                               |                                                                        | 客户端密钥（如需要）。可以使用 APISIX secret 存储和引用该值，APISIX 目前支持[环境变量和 HashiCorp Vault](../terminology/secret.md) 两种方式。                                                                                                          |
| grant_type                                   | string        | 否   | "urn:ietf:params:oauth:grant-type:uma-ticket" | ["urn:ietf:params:oauth:grant-type:uma-ticket"]                        |                                                                                                                                                                                                                                                       |
| policy_enforcement_mode                      | string        | 否   | "ENFORCING"                                   | ["ENFORCING", "PERMISSIVE"]                                            |                                                                                                                                                                                                                                                       |
| permissions                                  | array[string] | 否   |                                               |                                                                        | 字符串数组，每个字符串代表客户端请求访问的一个或多个资源和作用域的集合。                                                                                                                                                                              |
| lazy_load_paths                              | boolean       | 否   | false                                         |                                                                        | 设置为 `true` 时，使用资源注册端点将请求 URI 动态解析为资源，而非使用静态权限。                                                                                                                                                                       |
| http_method_as_scope                         | boolean       | 否   | false                                         |                                                                        | 设置为 `true` 时，将 HTTP 请求方法映射为同名作用域，并添加到所有请求的权限中。                                                                                                                                                                        |
| timeout                                      | integer       | 否   | 3000                                          | [1000, ...]                                                            | 与 Identity Server 进行 HTTP 连接的超时时间（毫秒）。                                                                                                                                                                                                 |
| access_token_expires_in                      | integer       | 否   | 300                                           | [1, ...]                                                               | 访问令牌的过期时间（秒）。                                                                                                                                                                                                                            |
| access_token_expires_leeway                  | integer       | 否   | 0                                             | [0, ...]                                                               | 访问令牌续期的宽限时间（秒）。设置后，将在令牌过期前 access_token_expires_leeway 秒进行续期，以避免访问令牌恰好在到达 OAuth 资源服务器时过期的错误。                                                                                                  |
| refresh_token_expires_in                     | integer       | 否   | 3600                                          | [1, ...]                                                               | 刷新令牌的过期时间（秒）。                                                                                                                                                                                                                            |
| refresh_token_expires_leeway                 | integer       | 否   | 0                                             | [0, ...]                                                               | 刷新令牌续期的宽限时间（秒）。设置后，将在令牌过期前 refresh_token_expires_leeway 秒进行续期，以避免刷新令牌恰好在到达 OAuth 资源服务器时过期的错误。                                                                                                 |
| ssl_verify                                   | boolean       | 否   | true                                          |                                                                        | 设置为 `true` 时，验证 TLS 证书与主机名是否匹配。                                                                                                                                                                                                    |
| cache_ttl_seconds                            | integer       | 否   | 86400（相当于 24 小时）                       | 正整数 >= 1                                                            | 插件缓存发现文档和用于向 Keycloak 认证的令牌的最长时间（秒）。                                                                                                                                                                                        |
| keepalive                                    | boolean       | 否   | true                                          |                                                                        | 设置为 `true` 时，启用 HTTP keep-alive，保持连接在使用后不关闭。如果预期有大量请求发往 Keycloak，建议设为 `true`。                                                                                                                                    |
| keepalive_timeout                            | integer       | 否   | 60000                                         | 正整数 >= 1000                                                         | 已建立的 HTTP 连接在空闲多久后关闭。                                                                                                                                                                                                                  |
| keepalive_pool                               | integer       | 否   | 5                                             | 正整数 >= 1                                                            | 连接池中的最大连接数。                                                                                                                                                                                                                                |
| access_denied_redirect_uri                   | string        | 否   |                                               | [1, 2048]                                                              | 用于替代返回 `"error_description":"not_authorized"` 错误信息而重定向用户的 URI。                                                                                                                                                                      |
| password_grant_token_generation_incoming_uri | string        | 否   |                                               | /api/token                                                             | 设置此项以使用密码授权类型生成令牌。插件会将传入请求的 URI 与此值进行比较。                                                                                                                                                                           |

注意：schema 中还定义了 `encrypt_fields = {"client_secret"}`，这意味着该字段将以加密方式存储在 etcd 中。请参阅[加密存储字段](../../../en/latest/plugin-develop.md#encrypted-storage-fields)。

### 发现文档与端点

建议使用 `discovery` 属性，`authz-keycloak` 插件可从中自动发现 Keycloak API 端点。

若设置 `token_endpoint` 和 `resource_registration_endpoint`，将覆盖从发现文档中获取的值。

### Client ID 与密钥

插件需要 `client_id` 属性进行标识，并在与 Keycloak 交互时指定评估权限的上下文。

若 `lazy_load_paths` 属性设置为 `true`，插件还需要从 Keycloak 为自身获取访问令牌。在此情况下，若客户端对 Keycloak 的访问是保密的，则需要配置 `client_secret` 属性。

### 策略执行模式

`policy_enforcement_mode` 属性指定在处理发送到服务器的授权请求时如何执行策略。

#### `ENFORCING` 模式

即使没有与资源关联的策略，请求也会被默认拒绝。

`policy_enforcement_mode` 默认设置为 `ENFORCING`。

#### `PERMISSIVE` 模式

当给定资源没有关联策略时，允许请求通过。

### 权限

处理传入请求时，插件可以静态或动态地从请求属性中确定要与 Keycloak 核对的权限。

若 `lazy_load_paths` 属性设置为 `false`，权限取自 `permissions` 属性。`permissions` 中的每个条目需要按照令牌端点 `permission` 参数的预期格式进行格式化。参阅 [Obtaining Permissions](https://www.keycloak.org/docs/latest/authorization_services/index.html#_service_obtaining_permissions)。

:::note

有效的权限可以是单个资源，也可以是资源与一个或多个作用域的组合。

:::

若 `lazy_load_paths` 属性设置为 `true`，将使用资源注册端点将请求 URI 解析为 Keycloak 中配置的一个或多个资源，并将解析出的资源用作待核对的权限。

:::note

这需要插件通过令牌端点为自身获取单独的访问令牌。请确保在 Keycloak 的客户端设置中启用 `Service Accounts Enabled` 选项。

同时请确保签发的访问令牌包含带有 `uma_protection` 角色的 `resource_access` 声明，以确保插件能够通过 Protection API 查询资源。

:::

### 自动将 HTTP 方法映射到作用域

`http_method_as_scope` 通常与 `lazy_load_paths` 一起使用，但也可以与静态权限列表配合使用。

若 `http_method_as_scope` 属性设置为 `true`，插件会将请求的 HTTP 方法映射为同名作用域，并将该作用域添加到每个待核对的权限中。

若 `lazy_load_paths` 属性设置为 `false`，插件会将映射的作用域添加到 `permissions` 属性中配置的所有静态权限中——即使这些权限已经包含一个或多个作用域。

### 使用 `password` 授权类型生成令牌

若要使用 `password` 授权类型生成令牌，可以设置 `password_grant_token_generation_incoming_uri` 属性的值。

若传入的 URI 与配置的属性匹配且请求方法为 POST，则使用 `token_endpoint` 生成令牌。

还需要在请求中添加 `application/x-www-form-urlencoded` 作为 `Content-Type` 请求头，并将 `username` 和 `password` 作为参数传入。

## 示例

以下示例演示了如何针对不同场景配置 `authz-keycloak` 插件。

请先完成 Keycloak 的[前置配置](#配置-keycloak)。

:::note
您可以使用以下命令从 `conf/config.yaml` 获取 `admin_key` 并保存到环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 配置 Keycloak

#### 启动 Keycloak

在 Docker 中以[开发模式](https://www.keycloak.org/server/configuration#_starting_keycloak_in_development_mode)启动一个名为 `apisix-quickstart-keycloak` 的 Keycloak 实例，管理员用户名为 `quickstart-admin`，密码为 `quickstart-admin-pass`：

```shell
docker run -d --name "apisix-quickstart-keycloak" \
  -e 'KEYCLOAK_ADMIN=quickstart-admin' \
  -e 'KEYCLOAK_ADMIN_PASSWORD=quickstart-admin-pass' \
  -p 8080:8080 \
  quay.io/keycloak/keycloak:18.0.2 start-dev
```

将 Keycloak 的 IP 保存到环境变量，以供后续配置引用：

```shell
KEYCLOAK_IP=192.168.42.145    # 替换为您的主机 IP
```

在浏览器中访问 `http://localhost:8080` 并点击 **Administration Console**：

![admin-console](https://static.api7.ai/uploads/2024/01/12/yEKlaSf5_admin-console.png)

输入管理员用户名 `quickstart-admin` 和密码 `quickstart-admin-pass` 登录：

![admin-signin](https://static.api7.ai/uploads/2024/01/12/GYIVrPyb_signin.png)

#### 创建 Realm

在左侧菜单中，将鼠标悬停在 **Master** 上，然后在下拉菜单中选择 **Add realm**：

![create-realm](https://static.api7.ai/uploads/2024/01/12/563XIJPK_add-realm.png)

输入 Realm 名称 `quickstart-realm` 并点击 **Create**：

![add-realm](https://static.api7.ai/uploads/2024/01/12/0lD21Z8R_create-realm.png)

#### 创建客户端

点击 **Clients** > **Create** 打开 **Add Client** 页面：

![create-client](https://static.api7.ai/uploads/2024/01/12/nHxgXyd9_create-client.png)

将 **Client ID** 填写为 `apisix-quickstart-client`，保持 **Client Protocol** 为 `openid-connect`，然后点击 **Save**：

![add-client](https://static.api7.ai/uploads/2024/01/12/7YSCHCnp_add-client.png)

客户端 `apisix-quickstart-client` 创建成功。跳转到详情页后，将 **Access Type** 选择为 `confidential`：

![client-access-type-confidential](https://static.api7.ai/uploads/2024/01/12/L7cahPUe_confidential.png)

SSO 登录成功后，Keycloak 会携带 state 和 code 将客户端重定向到 **Valid Redirect URIs** 中的地址。为简化演示，输入通配符 `*` 接受任意重定向 URI：

![client-redirect](https://static.api7.ai/uploads/2024/01/12/B3VGbQbW_redirect-uri.png)

为客户端启用授权，此操作会自动启用服务账号，并分配 `uma_protection` 角色：

![enable-authorization](https://static.api7.ai/uploads/2024/01/05/S4we4KO9_enable-auth.png)

点击 **Save** 应用自定义配置。

#### 保存 Client ID 和密钥

点击 **Clients** > `apisix-quickstart-client` > **Credentials**，从 **Secret** 中复制客户端密钥：

![client-secret](https://static.api7.ai/uploads/2024/01/12/3VqiXdf9_client-secret.png)

将 OIDC 客户端 ID 和密钥保存到环境变量：

```shell
OIDC_CLIENT_ID=apisix-quickstart-client
OIDC_CLIENT_SECRET=bSaIN3MV1YynmtXvU8lKkfeY0iwpr9cH  # 替换为您的实际值
```

#### 获取访问令牌

从 Keycloak 获取访问令牌：

```shell
curl -i "http://$KEYCLOAK_IP:8080/realms/quickstart-realm/protocol/openid-connect/token" -X POST \
  -d 'grant_type=client_credentials' \
  -d 'client_id='$OIDC_CLIENT_ID'' \
  -d 'client_secret='$OIDC_CLIENT_SECRET''
```

您应该会看到类似如下的响应：

```text
{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJoT3ludlBPY2d6Y3VWWnYtTU42bXZKMUczb0dOX2d6MFo3WFl6S2FSa1NBIn0...","expires_in":300,"refresh_expires_in":0,"token_type":"Bearer","not-before-policy":0,"scope":"email profile"}
```

将令牌保存到环境变量：

```shell
# 替换为您的访问令牌
ACCESS_TOKEN=<your_access_token>
```

### 使用懒加载路径和资源注册端点

以下示例演示如何配置插件，使用资源注册端点将请求 URI 动态解析为资源，而非使用静态权限。

按如下方式创建路由 `authz-keycloak-route`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "authz-keycloak-route",
    "uri": "/anything",
    "plugins": {
      "authz-keycloak": {
        "lazy_load_paths": true,
        "resource_registration_endpoint": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/authz/protection/resource_set",
        "discovery": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/.well-known/uma2-configuration",
        "client_id": "'"$OIDC_CLIENT_ID"'",
        "client_secret": "'"$OIDC_CLIENT_SECRET"'"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

- 将 `lazy_load_paths` 设置为 `true`。
- 将 `resource_registration_endpoint` 设置为 Keycloak 符合 UMA 规范的资源注册端点。当 `lazy_load_paths` 为 `true` 且未提供 `discovery` 时，此项必填。
- 将 `discovery` 设置为 Keycloak 授权服务的发现文档端点。
- 将 `client_id` 设置为之前创建的客户端 ID。
- 将 `client_secret` 设置为之前创建的客户端密钥。当 `lazy_load_paths` 为 `true` 时，此项必填。

向路由发送请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Authorization: Bearer $ACCESS_TOKEN"
```

您应该会看到类似如下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Bearer eyJhbGciOiJSU...",
    ...
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 108.180.51.111",
  "url": "http://127.0.0.1/anything"
}
```

### 使用静态权限

以下示例演示如何在 Keycloak 中配置与客户端作用域策略关联的基于作用域的权限，并配置 `authz-keycloak` 插件使用静态权限。

#### 在 Keycloak 中创建作用域

前往 **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Authorization Scopes**，点击 **Create** 打开 **Add Scope** 页面：

![add-scope](https://static.api7.ai/uploads/2024/01/06/bVHhiALe_auth-scope.png)

输入作用域名称 `access` 并点击 **Save**：

![create-new-scope](https://static.api7.ai/uploads/2024/01/06/xPorYwK3_save-scope.png)

#### 在 Keycloak 中创建资源

前往 **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Resources**，点击 **Create** 打开 **Add Resource** 页面：

![create-resource](https://static.api7.ai/uploads/2024/01/06/15DJ9HAU_create-resource.png)

输入资源名称 `httpbin-anything`、URI `/anything`、作用域 `access`，然后点击 **Save**：

![save-resource](https://static.api7.ai/uploads/2024/01/06/epuAPgos_save-resource.png)

#### 在 Keycloak 中创建客户端作用域

前往 **Client Scopes**，点击 **Create** 打开 **Add client scope** 页面：

![create-client-scope](https://static.api7.ai/uploads/2024/01/11/PyseoG7T_creat-client-scope.png)

输入作用域名称 `httpbin-access` 并点击 **Save**：

![save-client-scope](https://static.api7.ai/uploads/2024/01/12/5xQl0Xbx_save-client-scope.png)

#### 在 Keycloak 中创建策略

前往 **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Policies** > **Create Policies**，在下拉菜单中选择 **Client Scope** 打开 **Add Client Scope Policy** 页面：

![create-policy](https://static.api7.ai/uploads/2024/01/06/7UtT3cF6_create-policy.png)

为客户端作用域 `httpbin-access` 输入策略名称 `access-client-scope-policy`，勾选 **Required**，然后点击 **Save**：

![save-policy](https://static.api7.ai/uploads/2024/12/12/2DR0K39f_add_client_scope.png)

#### 在 Keycloak 中创建权限

前往 **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Permissions** > **Create Permissions**，在下拉菜单中选择 **Scope-Based** 打开 **Add Scope Permission** 页面：

![create-permission](https://static.api7.ai/uploads/2024/12/12/0PWsJUti_create_permission.png)

输入权限名称 `access-scope-perm`，选择 `access` 作用域，应用策略 `access-client-scope-policy`，然后点击 **Save**：

![add-scope-permission](https://static.api7.ai/uploads/2024/01/12/Y0vlk1Tj_add-scope-permission.png)

#### 分配客户端作用域

前往 **Clients** > **`apisix-quickstart-client`** > **Client Scopes**，将 `httpbin-access` 添加到默认客户端作用域：

![add-client-scope](https://static.api7.ai/uploads/2024/01/06/sJKUMUcP_add-client-scope.png)

#### 配置 APISIX

按如下方式创建路由 `authz-keycloak-route`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "authz-keycloak-route",
    "uri": "/anything",
    "plugins": {
      "authz-keycloak": {
        "lazy_load_paths": false,
        "discovery": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/.well-known/uma2-configuration",
        "permissions": ["httpbin-anything#access"],
        "client_id": "apisix-quickstart-client"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

- 将 `lazy_load_paths` 设置为 `false`。
- 将 `discovery` 设置为 Keycloak 授权服务的发现文档端点。
- 将 `permissions` 设置为资源 `httpbin-anything` 和作用域 `access`。

向路由发送请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Authorization: Bearer $ACCESS_TOKEN"
```

您应该会看到类似如下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Bearer eyJhbGciOiJSU...",
    ...
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 108.180.51.111",
  "url": "http://127.0.0.1/anything"
}
```

若您移除 `apisix-quickstart-client` 的客户端作用域 `httpbin-access`，访问该资源时将收到 `401 Unauthorized` 响应。

### 在自定义令牌端点使用密码授权类型生成令牌

以下示例演示如何在自定义端点使用密码授权类型生成令牌。

#### 在 Keycloak 中创建用户

若要使用密码授权类型，需要先创建一个用户。

前往 **Users** > **Add user** 并点击 **Add user**：

![add-user](https://static.api7.ai/uploads/2024/01/12/IBCav8aa_add-user.png)

将 **Username** 填写为 `quickstart-user` 并点击 **Save**：

![save-user](https://static.api7.ai/uploads/2024/01/12/3fUQOFWg_save-user.png)

点击 **Credentials**，将 **Password** 设置为 `quickstart-user-pass`。将 **Temporary** 切换为 `OFF`，这样首次登录时无需修改密码：

![set-password](https://static.api7.ai/uploads/2024/01/12/aoabcBbC_set-password.png)

#### 配置 APISIX

按如下方式创建路由 `authz-keycloak-route`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "authz-keycloak-route",
    "uri": "/api/*",
    "plugins": {
      "authz-keycloak": {
        "lazy_load_paths": true,
        "resource_registration_endpoint": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/authz/protection/resource_set",
        "client_id": "'"$OIDC_CLIENT_ID"'",
        "client_secret": "'"$OIDC_CLIENT_SECRET"'",
        "token_endpoint": "http://'"$KEYCLOAK_IP"':8080/realms/quickstart-realm/protocol/openid-connect/token",
        "password_grant_token_generation_incoming_uri": "/api/token"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

- 将 `token_endpoint` 设置为 Keycloak 的令牌端点。当未提供发现文档时，此项必填。
- 将 `password_grant_token_generation_incoming_uri` 设置为用户获取令牌的自定义 URI 路径。

向已配置的令牌端点发送请求。注意请求应使用 POST 方法，并将 `Content-Type` 设置为 `application/x-www-form-urlencoded`：

```shell
OIDC_USER=quickstart-user
OIDC_PASSWORD=quickstart-user-pass

curl "http://127.0.0.1:9080/api/token" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  -d 'username='$OIDC_USER'' \
  -d 'password='$OIDC_PASSWORD''
```

您应该会看到包含访问令牌的 JSON 响应，类似如下：

```text
{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ6U3FFaXN6VlpuYi1sRWMzZkp0UHNpU1ZZcGs4RGN3dXI1Mkx5V05aQTR3In0...","expires_in":300,"refresh_expires_in":1800,"refresh_token":"eyJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI0YjFiNTQ3Yi0zZmZjLTQ5YzQtYjE2Ni03YjdhNzIxMjk1ODcifQ...","token_type":"Bearer","not-before-policy":0,"session_state":"b16b262e-1056-4515-a455-f25e077ccb76","scope":"profile email"}
```
