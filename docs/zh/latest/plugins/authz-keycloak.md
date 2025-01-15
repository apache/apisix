---
title: authz-keycloak
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Authz Keycloak
  - authz-keycloak
description: 本文介绍了关于 Apache APISIX `authz-keycloak` 插件的基本信息及使用方法。
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

`authz-keycloak` 插件可用于通过 [Keycloak Identity Server](https://www.keycloak.org/) 添加身份验证。

:::tip

虽然该插件是为了与 Keycloak 一起使用而开发的，但是它也可以与任何符合 OAuth/OIDC 或 UMA 协议的身份认证软件一起使用。

:::

如果你想了解 Keycloak 的更多信息，请参考 [Authorization Services Guide](https://www.keycloak.org/docs/latest/authorization_services/)。

## 属性

| 名称                                         | 类型          | 必选项 | 默认值                                         | 有效值                                                       | 描述                                                                                                                                                                                                                                           |
|----------------------------------------------|---------------|-------|-----------------------------------------------|--------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| discovery                                    | string        | 否    |                                               | https://host.domain/realms/foo/.well-known/uma2-configuration | Keycloak 授权服务的 [discovery document](https://www.keycloak.org/docs/latest/authorization_services/index.html) 的 URL。                                                                                                |
| token_endpoint                               | string        | 否    |                                               | https://host.domain/realms/foo/protocol/openid-connect/token  | 接受 OAuth2 兼容 token 的接口，需要支持 `urn:ietf:params:oauth:grant-type:uma-ticket` 授权类型。                                                                                       |
| resource_registration_endpoint               | string        | 否    |                                               | https://host.domain/realms/foo/authz/protection/resource_set  | 符合 UMA 的资源注册端点。如果提供，则覆盖发现中的值。                                                                                                                 |
| client_id                                    | string        | 是    |                                               |                                                                    | 客户端正在寻求访问的资源服务器的标识符。                                                                                                                                          |
| client_secret                                | string        | 否    |                                               |                                                                    | 客户端密码（如果需要）。                                                                                                                                                                                                                       |
| grant_type                                   | string        | 否    | "urn:ietf:params:oauth:grant-type:uma-ticket" | ["urn:ietf:params:oauth:grant-type:uma-ticket"]                    |                                                                                                                                                                                                                                                       |
| policy_enforcement_mode                      | string        | 否    | "ENFORCING"                                   | ["ENFORCING", "PERMISSIVE"]                                        |                                                                                                                                                                                                                                                       |
| permissions                                  | array[string] | 否    |                                               |                                                                    | 描述客户端应用所需访问的资源和权限范围的字符串。格式必须为：`RESOURCE_ID#SCOPE_ID`。                                                                                                                                        |
| lazy_load_paths                              | boolean       | 否    | false                                         | [true, false]                                                      | 当设置为 true 时，使用资源注册端点而不是静态权限将请求 URI 动态解析为资源。                                                                                                      |
| http_method_as_scope                         | boolean       | 否    | false                                         | [true, false]                                                      | 设置为 true 时，将 HTTP 请求类型映射到同名范围并添加到所有请求的权限。                                                                                                                                         |
| timeout                                      | integer       | 否    | 3000                                          | [1000, ...]                                                        | 与 Identity Server 的 HTTP 连接超时（毫秒）。                                                                                                                                                                                       |
| access_token_expires_in                      | integer       | 否    | 300                                           | [1, ...]                                                           | 访问令牌的有效期。token.                                                                                                                                                                                                               |
| access_token_expires_leeway                  | integer       | 否    | 0                                             | [0, ...]                                                           | access_token 更新的到期余地。设置后，令牌将在到期前几秒更新 access_token_expires_leeway。这避免了 access_token 在到达 OAuth 资源服务器时刚刚过期的情况。 |
| refresh_token_expires_in                     | integer       | 否    | 3600                                          | [1, ...]                                                           | 刷新令牌的失效时间。                                                                                                                                                                                                          |
| refresh_token_expires_leeway                 | integer       | 否    | 0                                             | [0, ...]                                                           | refresh_token 更新的到期余地。设置后，令牌将在到期前几秒刷新 refresh_token_expires_leeway。这样可以避免在到达 OAuth 资源服务器时 refresh_token 刚刚过期的错误。 |
| ssl_verify                                   | boolean       | 否    | true                                          | [true, false]                                                      | 设置为 `true` 时，验证 TLS 证书是否与主机名匹配。                                                                                                                                                                                        |
| cache_ttl_seconds                            | integer       | 否    | 86400 (equivalent to 24h)                     | positive integer >= 1                                              | 插件缓存插件用于向 Keycloak 进行身份验证的发现文档和令牌的最长时间（以秒为单位）。                                                                                                                                                                |
| keepalive                                    | boolean       | 否    | true                                          | [true, false]                                                      | 当设置为 `true` 时，启用 HTTP keep-alive 保证在使用后仍然保持连接打开。如果您期望对 Keycloak 有很多请求，请设置为 `true`。                                                                                                                                |
| keepalive_timeout                            | integer       | 否    | 60000                                         | positive integer >= 1000                                           | 已建立的 HTTP 连接将关闭之前的空闲时间。                                                                                                                                         |
| keepalive_pool                               | integer       | 否    | 5                                             | positive integer >= 1                                              | 连接池中的最大连接数。                                                                                                                                                                                                    |
| access_denied_redirect_uri                   | string        | 否    |                                               | [1, 2048]                                                          | 需要将用户重定向到的 URI，而不是返回类似 `"error_description":"not_authorized"` 这样的错误消息。                                                                                                                                        |
| password_grant_token_generation_incoming_uri | string        | 否    |                                               | /api/token                                                         | 将此设置为使用密码授予类型生成令牌。该插件会将传入的请求 URI 与此值进行比较。                                                                                                                |

注意：schema 中还定义了 `encrypt_fields = {"client_secret"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

除上述释义外，还有以下需要注意的点：

- Discovery and endpoints
    - 使用 `discovery` 属性后，`authz-keycloak` 插件就可以从其 URL 中发现 Keycloak API 的端点。该 URL 指向 Keyloak 针对相应领域授权服务的发现文档。
    - 如果发现文档可用，则插件将根据该文档确定令牌端点 URL。如果 URL 存在，则 `token_endpoint` 和 `resource_registration_endpoint` 的值将被其覆盖。
- Client ID and secret
    - 该插件需配置 `client_id` 属性来标识自身。
    - 如果 `lazy_load_paths` 属性被设置为 `true`，那么该插件还需要从 Keycloak 中获得一个自身访问令牌。在这种情况下，如果客户端对 Keycloak 的访问是加密的，就需要配置 `client_secret` 属性。
- Policy enforcement mode
    - `policy_enforcement_mode` 属性指定了在处理发送到服务器的授权请求时，该插件如何执行策略。
        - `ENFORCING` mode：即使没有与给定资源关联的策略，请求也会默认被拒绝。`policy_enforcement_mode` 默认设置为 `ENFORCING`。
        - `PERMISSIVE` mode：如果资源没有绑定任何访问策略，也被允许请求。
- Permissions
    - 在处理传入的请求时，插件可以根据请求的参数确定静态或动态检查 Keycloak 的权限。
    - 如果 `lazy_load_paths` 参数设置为 `false`，则权限来自 `permissions` 属性。`permissions` 中的每个条目都需要按照令牌端点预设的 `permission` 属性进行格式化。详细信息请参考 [Obtaining Permissions](https://www.keycloak.org/docs/latest/authorization_services/index.html#_service_obtaining_permissions).

    :::note

    有效权限可以是单个资源，也可以是与一个或多个范围配对的资源。

    :::

    如果 `lazy_load_paths` 属性设置为 `true`，则请求 URI 将解析为使用资源注册端点在 Keycloak 中配置的一个或多个资源。已经解析的资源被用作于检查的权限。

    :::note

    需要该插件从令牌端点为自己获取单独的访问令牌。因此，请确保在 Keycloak 的客户端设置中设置了 `Service Accounts Enabled` 选项。

    还需要确保颁发的访问令牌包含具有 `uma_protection` 角色的 `resource_access` 声明，以保证插件能够通过 Protection API 查询资源。

    :::

- 自动将 HTTP method 映射到作用域

    `http_method_as_scope` 通常与 `lazy_load_paths` 一起使用，但也可以与静态权限列表一起使用。

    - 如果 `http_method_as_scope` 属性设置为 `true`，插件会将请求的 HTTP 方法映射到同名范围。然后将范围添加到每个要检查的权限。

    - 如果 `lazy_load_paths` 属性设置为 `false`，则插件会将映射范围添加到 `permissions` 属性中配置的任意一个静态权限——即使它们已经包含一个或多个范围。

- 使用 `password` 授权生成令牌

    - 如果要使用 `password` 授权生成令牌，你可以设置 `password_grant_token_generation_incoming_uri` 属性的值。

    - 如果传入的 URI 与配置的属性匹配并且请求方法是 POST，则使用 `token_endpoint` 生成一个令牌。

    同时，你还需要添加 `application/x-www-form-urlencoded` 作为 `Content-Type` 标头，`username` 和 `password` 作为参数。

    如下示例是当 `password_grant_token_generation_incoming_uri` 设置为 `/api/token` 时的命令：

    ```shell
    curl --location --request POST 'http://127.0.0.1:9080/api/token' \
    --header 'Accept: application/json, text/plain, */*' \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'username=<User_Name>' \
    --data-urlencode 'password=<Password>'
    ```

## 如何启用

以下示例为你展示了如何在指定 Route 中启用 `authz-keycloak` 插件，其中 `${realm}` 是 Keycloak 中的 `realm` 名称：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/get",
    "plugins": {
        "authz-keycloak": {
            "token_endpoint": "http://127.0.0.1:8090/realms/${realm}/protocol/openid-connect/token",
            "permissions": ["resource name#scope name"],
            "client_id": "Client ID"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## 测试插件

通过上述命令启用插件后，可以通过以下方法测试插件。

首先需要从 Keycloak 获取 JWT 令牌：

```shell
curl "http://<YOUR_KEYCLOAK_HOST>/realms/<YOUR_REALM>/protocol/openid-connect/token" \
  -d "client_id=<YOUR_CLIENT_ID>" \
  -d "client_secret=<YOUR_CLIENT_SECRET>" \
  -d "username=<YOUR_USERNAME>" \
  -d "password=<YOUR_PASSWORD>" \
  -d "grant_type=password"
```

你应该收到类似以下的响应：

```text
{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJoT3ludlBPY2d6Y3VWWnYtTU42bXZKMUczb0dOX2d6MFo3WFl6S2FSa1NBIn0.eyJleHAiOjE3MDMyOTAyNjAsImlhdCI6MTcwMzI4OTk2MCwianRpIjoiMjJhOGFmMzItNDM5Mi00Yzg3LThkM2UtZDkyNDVmZmNiYTNmIiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguMS44Mzo4MDgwL3JlYWxtcy9xdWlja3N0YXJ0LXJlYWxtIiwiYXVkIjoiYWNjb3VudCIsInN1YiI6IjAyZWZlY2VlLTBmYTgtNDg1OS1iYmIwLTgyMGZmZDdjMWRmYSIsInR5cCI6IkJlYXJlciIsImF6cCI6ImFwaXNpeC1xdWlja3N0YXJ0LWNsaWVudCIsInNlc3Npb25fc3RhdGUiOiI1YzIzZjVkZC1hN2ZhLTRlMmItOWQxNC02MmI1YzYyNmU1NDYiLCJhY3IiOiIxIiwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbImRlZmF1bHQtcm9sZXMtcXVpY2tzdGFydC1yZWFsbSIsIm9mZmxpbmVfYWNjZXNzIiwidW1hX2F1dGhvcml6YXRpb24iXX0sInJlc291cmNlX2FjY2VzcyI6eyJhY2NvdW50Ijp7InJvbGVzIjpbIm1hbmFnZS1hY2NvdW50IiwibWFuYWdlLWFjY291bnQtbGlua3MiLCJ2aWV3LXByb2ZpbGUiXX19LCJzY29wZSI6ImVtYWlsIHByb2ZpbGUiLCJzaWQiOiI1YzIzZjVkZC1hN2ZhLTRlMmItOWQxNC02MmI1YzYyNmU1NDYiLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsInByZWZlcnJlZF91c2VybmFtZSI6InF1aWNrc3RhcnQtdXNlciJ9.WNZQiLRleqCxw-JS-MHkqXnX_BPA9i6fyVHqF8l-L-2QxcqTAwbIp7AYKX-z90CG6EdRXOizAEkQytB32eVWXaRkLeTYCI7wIrT8XSVTJle4F88ohuBOjDfRR61yFh5k8FXXdAyRzcR7tIeE2YUFkRqw1gCT_VEsUuXPqm2wTKOmZ8fRBf4T-rP4-ZJwPkHAWc_nG21TmLOBCSulzYqoC6Lc-OvX5AHde9cfRuXx-r2HhSYs4cXtvX-ijA715MY634CQdedheoGca5yzPsJWrAlBbCruN2rdb4u5bDxKU62pJoJpmAsR7d5qYpYVA6AsANDxHLk2-W5F7I_IxqR0YQ","expires_in":300,"refresh_expires_in":1800,"refresh_token":"eyJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJjN2IwYmY4NC1kYjk0LTQ5YzctYWIyZC01NmU3ZDc1MmRkNDkifQ.eyJleHAiOjE3MDMyOTE3NjAsImlhdCI6MTcwMzI4OTk2MCwianRpIjoiYzcyZjAzMzctYmZhNS00MWEzLTlhYjEtZmJlNGY0NmZjMDgxIiwiaXNzIjoiaHR0cDovLzE5Mi4xNjguMS44Mzo4MDgwL3JlYWxtcy9xdWlja3N0YXJ0LXJlYWxtIiwiYXVkIjoiaHR0cDovLzE5Mi4xNjguMS44Mzo4MDgwL3JlYWxtcy9xdWlja3N0YXJ0LXJlYWxtIiwic3ViIjoiMDJlZmVjZWUtMGZhOC00ODU5LWJiYjAtODIwZmZkN2MxZGZhIiwidHlwIjoiUmVmcmVzaCIsImF6cCI6ImFwaXNpeC1xdWlja3N0YXJ0LWNsaWVudCIsInNlc3Npb25fc3RhdGUiOiI1YzIzZjVkZC1hN2ZhLTRlMmItOWQxNC02MmI1YzYyNmU1NDYiLCJzY29wZSI6ImVtYWlsIHByb2ZpbGUiLCJzaWQiOiI1YzIzZjVkZC1hN2ZhLTRlMmItOWQxNC02MmI1YzYyNmU1NDYifQ.7AH7ppbVOlkYc9CoJ7kLSlDUkmFuNga28Amugn2t724","token_type":"Bearer","not-before-policy":0,"session_state":"5c23f5dd-a7fa-4e2b-9d14-62b5c626e546","scope":"email profile"}
```

之后就可以使用获得的访问令牌发起请求：

```shell
curl http://127.0.0.1:9080/get -H 'Authorization: Bearer ${ACCESS_TOKEN}'
```

## 删除插件

当你需要禁用 `authz-keycloak` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/get",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## 插件 Roadmap

- 目前，`authz-keycloak` 插件通过要求定义资源名称和所需的范围，来强制执行路由策略。但 Keycloak 官方适配的其他语言客户端（Java、JavaScript）仍然可以通过动态查询 Keycloak 路径以及延迟加载身份资源的路径来提供路径匹配。在 Apache APISIX 之后发布的插件中即将支持此功能。

- 支持从 Keycloak JSON 文件中读取权限范畴和其他配置项。
