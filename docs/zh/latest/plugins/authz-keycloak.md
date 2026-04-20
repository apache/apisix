---
title: authz-keycloak
keywords:
  - APISIX
  - API 网关
  - Plugin
  - Authz Keycloak
  - authz-keycloak
description: authz-keycloak 插件集成 Keycloak 进行用户身份验证和授权，增强 API 安全性和管理能力。
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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`authz-keycloak` 插件支持与 [Keycloak](https://www.keycloak.org/) 集成以对用户进行身份验证和授权。更多配置选项信息请参阅 Keycloak 的 [Authorization Services Guide](https://www.keycloak.org/docs/latest/authorization_services/)。

虽然该插件是为 Keycloak 开发的，但理论上也可以与其他符合 OAuth/OIDC 和 UMA 协议的身份提供者一起使用。

## 参数

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| client_id | string | 是 | | | 客户端 ID。 |
| client_secret | string | 否 | | | 客户端密钥。该值在存储到 etcd 之前会使用 AES 加密。 |
| discovery | string | 否 | | | 发现文档的 URL。 |
| token_endpoint | string | 否 | | | 支持 `urn:ietf:params:oauth:grant-type:uma-ticket` 授权类型的令牌端点，用于获取访问令牌。若提供，则覆盖发现文档中的值。 |
| resource_registration_endpoint | string | 否 | | | 符合 UMA 规范的资源注册端点。当 `lazy_load_paths` 为 `true` 时必填。插件将首先从此配置项查找资源注册端点；若未找到，则从发现文档中查找。 |
| grant_type | string | 否 | `urn:ietf:params:oauth:grant-type:uma-ticket` | `urn:ietf:params:oauth:grant-type:uma-ticket` | 必须设置为 `urn:ietf:params:oauth:grant-type:uma-ticket`。 |
| policy_enforcement_mode | string | 否 | `ENFORCING` | `ENFORCING` 或 `PERMISSIVE` | [策略执行](https://www.keycloak.org/docs/latest/authorization_services/index.html#policy-enforcement)模式。`ENFORCING` 模式下，当没有与给定资源关联的策略时，请求将被拒绝。`PERMISSIVE` 模式下，当没有与给定资源关联的策略时，请求将被允许。 |
| permissions | array[string] | 否 | | | 表示客户端请求访问的一组资源和范围的权限数组。格式可以为 `RESOURCE_ID#SCOPE_ID`、`RESOURCE_ID` 或 `#SCOPE_ID`。当 `lazy_load_paths` 为 `false` 时使用。 |
| lazy_load_paths | boolean | 否 | `false` | | 若为 `true`，则需要发现文档或资源注册端点来动态将请求 URI 解析为资源。这需要插件从令牌端点为自己获取单独的访问令牌。请确保在 Keycloak 中勾选 `Service Accounts Enabled` 选项，并确保颁发的访问令牌包含带有 `uma_protection` 角色的 `resource_access` 声明。 |
| http_method_as_scope | boolean | 否 | `false` | | 若为 `true`，则使用请求的 HTTP 方法作为范围来检查是否应授予访问权限。当 `lazy_load_paths` 为 `false` 时，插件会将映射的范围添加到 `permissions` 属性中配置的任何静态权限，即使它们已经包含一个或多个范围。 |
| timeout | integer | 否 | 3000 | >= 1 | 与身份提供者的 HTTP 连接超时时间（毫秒）。 |
| access_token_expires_in | integer | 否 | 300 | >= 1 | 访问令牌的有效期（秒），当令牌端点响应中不存在 `expires_in` 属性时使用。 |
| access_token_expires_leeway | integer | 否 | 0 | >= 0 | 访问令牌续期的提前量（秒）。当设置为大于 0 的值时，令牌将在过期前提前该时间进行续期。 |
| refresh_token_expires_in | integer | 否 | 3600 | > 0 | 刷新令牌的过期时间（秒）。 |
| refresh_token_expires_leeway | integer | 否 | 0 | >= 0 | 刷新令牌续期的提前量（秒）。当设置为大于 0 的值时，令牌将在过期前提前该时间进行续期。 |
| ssl_verify | boolean | 否 | `true` | | 若为 `true`，则验证 OpenID 提供者的 SSL 证书。 |
| cache_ttl_seconds | integer | 否 | 86400 | > 0 | 插件缓存发现文档和访问令牌的 TTL（秒）。 |
| keepalive | boolean | 否 | `true` | | 若为 `true`，则启用 HTTP keep-alive 以在使用后保持连接打开。如果预期对 Keycloak 有大量请求，请设置为 `true`。 |
| keepalive_timeout | integer | 否 | 60000 | >= 1000 | 已建立的 HTTP 连接关闭前的空闲时间（毫秒）。 |
| keepalive_pool | integer | 否 | 5 | >= 1 | 连接池中的最大连接数。 |
| access_denied_redirect_uri | string | 否 | | | 访问被拒绝时将用户重定向到的 URI，而不是返回类似 `"error_description":"not_authorized"` 的错误消息。 |
| password_grant_token_generation_incoming_uri | string | 否 | | | 使用密码授权生成令牌的传入请求 URI，例如 `/api/token`。若传入请求的 URI 与配置值匹配、请求方法为 POST 且 `Content-Type` 为 `application/x-www-form-urlencoded`，则在 `token_endpoint` 生成令牌。 |

注意：schema 中还定义了 `encrypt_fields = {"client_secret"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考[加密存储字段](../plugin-develop.md#加密存储字段)。

## 示例

以下示例展示了如何针对不同场景配置 `authz-keycloak`。

请先完成 [Keycloak 的初始配置](#配置-keycloak)，然后再进行以下操作。

:::note

您可以通过以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 配置 Keycloak

#### 启动 Keycloak

在 Docker 中以[开发模式](https://www.keycloak.org/server/configuration#_starting_keycloak_in_development_mode)启动名为 `apisix-quickstart-keycloak` 的 Keycloak 实例，管理员名称为 `quickstart-admin`，密码为 `quickstart-admin-pass`：

```shell
docker run -d --name "apisix-quickstart-keycloak" \
  -e 'KEYCLOAK_ADMIN=quickstart-admin' \
  -e 'KEYCLOAK_ADMIN_PASSWORD=quickstart-admin-pass' \
  -p 8080:8080 \
  quay.io/keycloak/keycloak:18.0.2 start-dev
```

将 Keycloak IP 保存到环境变量：

```shell
KEYCLOAK_IP=192.168.42.145    # 替换为您的主机 IP
```

在浏览器中访问 `http://localhost:8080`，点击 **Administration Console**，使用管理员账号 `quickstart-admin` 和密码 `quickstart-admin-pass` 登录。

#### 创建 Realm

在左侧菜单中，将鼠标悬停在 **Master** 上，在下拉菜单中选择 **Add realm**。输入 realm 名称 `quickstart-realm` 并点击 **Create**。

#### 创建客户端

点击 **Clients** > **Create** 打开 **Add Client** 页面。输入 **Client ID** 为 `apisix-quickstart-client`，保持 **Client Protocol** 为 `openid-connect`，点击 **Save**。

重定向到详情页面后，选择 `confidential` 作为 **Access Type**。在 **Valid Redirect URIs** 中输入通配符 `*`。

为客户端启用授权，这将自动为服务账号分配 `uma_protection` 角色。点击 **Save**。

#### 保存客户端 ID 和密钥

点击 **Clients** > `apisix-quickstart-client` > **Credentials**，从 **Secret** 中复制客户端密钥。

将 OIDC 客户端 ID 和密钥保存到环境变量：

```shell
OIDC_CLIENT_ID=apisix-quickstart-client
OIDC_CLIENT_SECRET=bSaIN3MV1YynmtXvU8lKkfeY0iwpr9cH  # 替换为您的值
```

#### 请求访问令牌

从 Keycloak 请求访问令牌：

```shell
curl -i "http://$KEYCLOAK_IP:8080/realms/quickstart-realm/protocol/openid-connect/token" -X POST \
  -d 'grant_type=client_credentials' \
  -d 'client_id='$OIDC_CLIENT_ID'' \
  -d 'client_secret='$OIDC_CLIENT_SECRET''
```

将访问令牌保存到环境变量：

```shell
ACCESS_TOKEN=<your_access_token>  # 替换为响应中的 access_token 值
```

### 使用懒加载路径和资源注册端点

以下示例演示如何配置插件，通过资源注册端点动态解析请求 URI 到资源，而非使用静态权限。

创建一个带有 `authz-keycloak` 插件的路由：

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: authz-keycloak-service
    routes:
      - name: authz-keycloak-route
        uris:
          - /anything
        plugins:
          authz-keycloak:
            lazy_load_paths: true
            resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
            discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
            client_id: "apisix-quickstart-client"
            client_secret: "<OIDC_CLIENT_SECRET>"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-plugin-config
spec:
  plugins:
    - name: authz-keycloak
      config:
        lazy_load_paths: true
        resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
        discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
        client_id: "apisix-quickstart-client"
        client_secret: "<OIDC_CLIENT_SECRET>"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: authz-keycloak-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  ingressClassName: apisix
  http:
    - name: authz-keycloak-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: authz-keycloak
          enable: true
          config:
            lazy_load_paths: true
            resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
            discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
            client_id: "apisix-quickstart-client"
            client_secret: "<OIDC_CLIENT_SECRET>"
```

将配置应用到集群：

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

❶ 将 `lazy_load_paths` 设置为 `true` 以动态解析请求 URI 到资源。

❷ 将 `resource_registration_endpoint` 设置为 Keycloak 符合 UMA 规范的资源注册端点。当 `lazy_load_paths` 为 `true` 时必填。

❸ 将 `discovery` 设置为 Keycloak 授权服务的发现文档端点。

❹ 将 `client_id` 设置为之前创建的客户端 ID。

❺ 将 `client_secret` 设置为之前创建的客户端密钥。当 `lazy_load_paths` 为 `true` 时必填。

向路由发送请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Authorization: Bearer $ACCESS_TOKEN"
```

您应该收到类似以下的 `HTTP/1.1 200 OK` 响应：

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

以下示例演示如何为 Keycloak 配置基于范围的权限（关联客户端范围策略），并配置 `authz-keycloak` 插件使用静态权限。

#### 在 Keycloak 中创建范围

进入 **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Authorization Scopes**，点击 **Create**。输入范围名称 `access` 并点击 **Save**。

#### 在 Keycloak 中创建资源

进入 **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Resources**，点击 **Create**。输入资源名称 `httpbin-anything`、URI `/anything`、范围 `access`，点击 **Save**。

#### 在 Keycloak 中创建客户端范围

进入 **Client Scopes**，点击 **Create**。输入范围名称 `httpbin-access` 并点击 **Save**。

#### 在 Keycloak 中创建策略

进入 **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Policies** > **Create Policies**，选择 **Client Scope**。输入策略名称 `access-client-scope-policy`，选择客户端范围 `httpbin-access`，勾选 **Required**，点击 **Save**。

#### 在 Keycloak 中创建权限

进入 **Clients** > **`apisix-quickstart-client`** > **Authorization** > **Permissions** > **Create Permissions**，选择 **Scope-Based**。输入权限名称 `access-scope-perm`，选择范围 `access`，应用策略 `access-client-scope-policy`，点击 **Save**。

#### 分配客户端范围

进入 **Clients** > **`apisix-quickstart-client`** > **Client Scopes**，将 `httpbin-access` 添加到默认客户端范围。

#### 配置 APISIX

创建一个带有 `authz-keycloak` 插件的路由：

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: authz-keycloak-service
    routes:
      - name: authz-keycloak-route
        uris:
          - /anything
        plugins:
          authz-keycloak:
            lazy_load_paths: false
            discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
            permissions:
              - "httpbin-anything#access"
            client_id: "apisix-quickstart-client"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-plugin-config
spec:
  plugins:
    - name: authz-keycloak
      config:
        lazy_load_paths: false
        discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
        permissions:
          - "httpbin-anything#access"
        client_id: "apisix-quickstart-client"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: authz-keycloak-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  ingressClassName: apisix
  http:
    - name: authz-keycloak-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: authz-keycloak
          enable: true
          config:
            lazy_load_paths: false
            discovery: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/.well-known/uma2-configuration"
            permissions:
              - "httpbin-anything#access"
            client_id: "apisix-quickstart-client"
```

将配置应用到集群：

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

❶ 将 `lazy_load_paths` 设置为 `false` 以使用静态权限。

❷ 将 `discovery` 设置为 Keycloak 授权服务的发现文档端点。

❸ 将 `permissions` 设置为资源 `httpbin-anything` 和范围 `access`。

向路由发送请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Authorization: Bearer $ACCESS_TOKEN"
```

您应该收到 `HTTP/1.1 200 OK` 响应。如果移除 `apisix-quickstart-client` 的客户端范围 `httpbin-access`，请求将返回 `401 Unauthorized`。

### 使用密码授权生成令牌

以下示例演示如何在自定义端点使用密码授权生成令牌。

#### 在 Keycloak 中创建用户

进入 **Users** > **Add user**，输入用户名 `quickstart-user`，点击 **Save**。点击 **Credentials**，设置密码 `quickstart-user-pass`，将 **Temporary** 切换为 `OFF`，点击 **Set Password**。

#### 配置 APISIX

创建一个带有 `authz-keycloak` 插件的路由：

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: authz-keycloak-service
    routes:
      - name: authz-keycloak-route
        uris:
          - /api/*
        plugins:
          authz-keycloak:
            lazy_load_paths: true
            resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
            client_id: "apisix-quickstart-client"
            client_secret: "<OIDC_CLIENT_SECRET>"
            token_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/protocol/openid-connect/token"
            password_grant_token_generation_incoming_uri: "/api/token"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-plugin-config
spec:
  plugins:
    - name: authz-keycloak
      config:
        lazy_load_paths: true
        resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
        client_id: "apisix-quickstart-client"
        client_secret: "<OIDC_CLIENT_SECRET>"
        token_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/protocol/openid-connect/token"
        password_grant_token_generation_incoming_uri: "/api/token"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: authz-keycloak-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: authz-keycloak-route
spec:
  ingressClassName: apisix
  http:
    - name: authz-keycloak-route
      match:
        paths:
          - /api/*
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: authz-keycloak
          enable: true
          config:
            lazy_load_paths: true
            resource_registration_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/authz/protection/resource_set"
            client_id: "apisix-quickstart-client"
            client_secret: "<OIDC_CLIENT_SECRET>"
            token_endpoint: "http://<KEYCLOAK_IP>:8080/realms/quickstart-realm/protocol/openid-connect/token"
            password_grant_token_generation_incoming_uri: "/api/token"
```

将配置应用到集群：

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

❶ 将 `token_endpoint` 设置为 Keycloak 令牌端点。当未提供发现文档时必填。

❷ 将 `password_grant_token_generation_incoming_uri` 设置为用户可以获取令牌的自定义 URI 路径。

向配置的令牌端点发送请求，使用 POST 方法，`Content-Type` 为 `application/x-www-form-urlencoded`：

```shell
OIDC_USER=quickstart-user
OIDC_PASSWORD=quickstart-user-pass

curl "http://127.0.0.1:9080/api/token" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  -d 'username='$OIDC_USER'' \
  -d 'password='$OIDC_PASSWORD''
```

您应该收到包含访问令牌的 JSON 响应。
