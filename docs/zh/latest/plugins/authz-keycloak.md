---
title: Keycloak Authorization (authz-keycloak)
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Authz Keycloak
  - authz-keycloak
description: authz-keycloak 插件将 Apache APISIX 请求的 UMA 权限决策委托给 Keycloak 授权服务。
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

`authz-keycloak` 插件将 APISIX 与 [Keycloak 授权服务](https://www.keycloak.org/docs/latest/authorization_services/)集成。插件将调用方的 Bearer 令牌和请求的权限发送到 Keycloak 的用户管理访问 (UMA) 令牌端点。Keycloak 在 APISIX 代理请求之前评估相关资源、作用域、策略和权限。

权限可以动态选择，也可以显式配置。使用动态路径加载时，APISIX 通过 Keycloak 服务账号调用 Protection API，将请求 URI 解析为对应资源。使用静态权限时，APISIX 直接将配置的资源和作用域名称发送到 UMA 令牌端点。

## 属性

| 名称                                         | 类型          | 必填 | 默认值                                        | 有效值                                                                 | 描述 |
|----------------------------------------------|---------------|------|-----------------------------------------------|------------------------------------------------------------------------|------|
| max_req_body_size                            | integer       | 否   | 67108864                                      | >= 1                                                                   | 插件生成密码授权令牌时缓冲到内存中的请求体大小上限，单位为字节。如果请求体超过限制或无法读取，插件将返回 `503 Service Unavailable`。 |
| discovery                                    | string        | 否   |                                               | https://host.domain/realms/foo/.well-known/uma2-configuration           | Keycloak UMA 发现文档的 URL。必须至少配置 `discovery` 或 `token_endpoint` 之一。 |
| token_endpoint                               | string        | 否   |                                               | https://host.domain/realms/foo/protocol/openid-connect/token            | 支持 `urn:ietf:params:oauth:grant-type:uma-ticket` 授权类型并用于权限评估的令牌端点。该配置将覆盖发现文档中的值。必须至少配置 `discovery` 或 `token_endpoint` 之一。 |
| resource_registration_endpoint               | string        | 否   |                                               | https://host.domain/realms/foo/authz/protection/resource_set            | UMA 资源注册端点。启用 `lazy_load_paths` 时，插件优先使用该值，否则从发现文档获取。动态加载需要配置 `discovery`，或同时配置 `token_endpoint` 和 `resource_registration_endpoint`。 |
| client_id                                    | string        | 是   |                                               |                                                                        | Keycloak 资源服务器的客户端 ID。 |
| client_secret                                | string        | 否   |                                               |                                                                        | 插件向令牌端点认证时使用的客户端密钥。启用字段加密后，该值会在存入 etcd 前加密。 |
| grant_type                                   | string        | 否   | "urn:ietf:params:oauth:grant-type:uma-ticket" | ["urn:ietf:params:oauth:grant-type:uma-ticket"]                        | 用于权限评估的 UMA ticket 授权类型，也是唯一可接受的值。 |
| policy_enforcement_mode                      | string        | 否   | "ENFORCING"                                   | ["ENFORCING", "PERMISSIVE"]                                          | 控制插件在向 Keycloak 请求决策前如何处理空权限列表。 |
| permissions                                  | array[string] | 否   |                                               |                                                                        | `lazy_load_paths` 为 `false` 时需要评估的权限。支持 `RESOURCE_ID#SCOPE_ID`、`RESOURCE_ID` 和 `#SCOPE_ID` 格式。 |
| lazy_load_paths                              | boolean       | 否   | false                                         |                                                                        | 设置为 `true` 时，通过资源注册端点将请求 URI 解析为 Keycloak 资源。 |
| http_method_as_scope                         | boolean       | 否   | false                                         |                                                                        | 设置为 `true` 时，将 HTTP 请求方法映射为同名作用域，并添加到所有请求的权限中。 |
| timeout                                      | integer       | 否   | 3000                                          | [1000, ...]                                                            | 与身份提供商建立 HTTP 连接的超时时间，单位为毫秒。 |
| access_token_expires_in                      | integer       | 否   | 300                                           | [1, ...]                                                               | 令牌端点响应中不包含 `expires_in` 时使用的访问令牌有效期，单位为秒。 |
| access_token_expires_leeway                  | integer       | 否   | 0                                             | [0, ...]                                                               | 访问令牌续期的提前量，单位为秒。大于 `0` 时，插件会在令牌过期前按该值提前续期。 |
| refresh_token_expires_in                     | integer       | 否   | 3600                                          | [1, ...]                                                               | 刷新令牌的有效期，单位为秒。 |
| refresh_token_expires_leeway                 | integer       | 否   | 0                                             | [0, ...]                                                               | 刷新令牌续期的提前量，单位为秒。大于 `0` 时，插件会在令牌过期前按该值提前续期。 |
| ssl_verify                                   | boolean       | 否   | true                                          |                                                                        | 设置为 `true` 时，验证 OpenID 提供商的 TLS 证书。 |
| cache_ttl_seconds                            | integer       | 否   | 86400                                         | 正整数 >= 1                                                            | 插件缓存发现文档和访问令牌的时间，单位为秒。 |
| keepalive                                    | boolean       | 否   | true                                          |                                                                        | 设置为 `true` 时，保持与身份提供商的 HTTP 连接以供复用。 |
| keepalive_timeout                            | integer       | 否   | 60000                                         | 正整数 >= 1000                                                         | 已建立的 HTTP 连接在关闭前可保持空闲的时间，单位为毫秒。 |
| keepalive_pool                               | integer       | 否   | 5                                             | 正整数 >= 1                                                            | 连接池中的最大连接数。 |
| access_denied_redirect_uri                   | string        | 否   |                                               | [1, 2048]                                                              | 当 `ENFORCING` 模式下权限列表为空或 Keycloak 返回 `403 Forbidden` 时，用于发送 `307 Temporary Redirect` 的 URI。 |
| password_grant_token_generation_incoming_uri | string        | 否   |                                               | /api/token                                                             | 兼容旧配置的资源所有者密码凭证授权端点。OAuth 2.0 安全最佳当前实践规定不得使用此授权类型。新部署中不要配置此字段。 |

注意：schema 将 `client_secret` 标记为加密字段。启用字段加密后，APISIX 会在将该值存入 etcd 前进行加密。更多信息，请参阅[加密存储字段](../plugin-develop.md#加密存储字段)。

### 发现文档与端点

配置 `discovery` 后，`authz-keycloak` 插件会从 UMA 发现文档获取 Keycloak 的令牌端点和资源注册端点。

如果配置了 `token_endpoint` 或 `resource_registration_endpoint`，对应值将覆盖从发现文档获取的端点。

必须至少配置 `discovery` 或 `token_endpoint` 之一。动态路径加载还需要配置 `discovery`，或同时配置 `token_endpoint` 和 `resource_registration_endpoint`。

### Client ID 与密钥

`client_id` 用于标识评估权限的 Keycloak 资源服务器。

当 `lazy_load_paths` 为 `true` 时，插件会先获取服务账号令牌，再查询 Protection API。需要为该请求配置 `client_secret`，并确保服务账号令牌包含 `uma_protection` 角色。

### 策略执行模式

`policy_enforcement_mode` 属性控制插件在向 Keycloak 请求决策前如何处理空权限列表。

#### `ENFORCING` 模式

空权限列表会返回 `403 Forbidden`。如果配置了 `access_denied_redirect_uri`，则返回 `307 Temporary Redirect`。默认模式为 `ENFORCING`。

#### `PERMISSIVE` 模式

插件会在不携带权限参数的情况下继续发送 UMA 令牌请求，是否授权仍由 Keycloak 决定。

### 权限

处理传入请求时，插件可以静态确定要由 Keycloak 检查的权限，也可以根据请求属性动态确定。

当 `lazy_load_paths` 为 `false` 时，插件从 `permissions` 属性读取权限。`permissions` 中的每个条目都需要使用令牌端点 `permission` 参数支持的格式。更多信息，请参阅 [Obtaining Permissions](https://www.keycloak.org/docs/latest/authorization_services/index.html#_service_obtaining_permissions)。

权限可以包含资源、资源和作用域，或仅包含作用域。支持的格式为 `RESOURCE_ID`、`RESOURCE_ID#SCOPE_ID` 和 `#SCOPE_ID`。

当 `lazy_load_paths` 为 `true` 时，插件通过资源注册端点将请求 URI 解析为 Keycloak 中配置的一个或多个资源，并使用解析出的资源作为待检查权限。

动态加载要求插件获取服务账号令牌。使用 Protection API 前，需要为 Keycloak 客户端启用服务账号，并确保签发的令牌包含 `uma_protection` 角色。

### 自动将 HTTP 方法映射到作用域

`http_method_as_scope` 通常与 `lazy_load_paths` 一起使用，也可以与静态权限列表配合使用。

当 `http_method_as_scope` 为 `true` 时，插件会将请求的 HTTP 方法映射为同名作用域，并将该作用域添加到每个待检查权限。

当 `lazy_load_paths` 为 `false` 时，插件会将映射的作用域添加到 `permissions` 中配置的所有静态权限，即使这些权限已经包含一个或多个作用域。

### 旧版密码授权兼容性

`password_grant_token_generation_incoming_uri` 属性用于兼容现有配置。当包含 `username` 和 `password` 的表单编码 `POST` 请求与此 URI 匹配时，插件会向配置的 `token_endpoint` 提交密码授权请求并返回其响应。

OAuth 2.0 安全最佳当前实践规定不得使用资源所有者密码凭证授权。新部署中不要配置此属性。更多信息，请参阅 [RFC 9700 第 2.4 节](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.4)。

## 示例

以下配置将创建一个 Keycloak 资源服务器，并演示动态和静态 UMA 权限检查。

开始之前：

- 安装 [Docker](https://docs.docker.com/get-docker/)。
- 安装 [cURL](https://curl.se/) 和 [jq](https://jqlang.org/)。
- 按照[入门指南](../getting-started/README.md)使用 Docker 启动 APISIX。
- 如果需要使用 ADC，请先[安装并配置 ADC](https://docs.api7.ai/apisix/reference/adc)。
- 如果需要使用 Ingress Controller 示例，请先在 `aic` 命名空间中[配置 Ingress Controller 和网关](https://apisix.apache.org/zh/docs/ingress-controller/getting-started/)。

### 配置 Keycloak

启动 Keycloak，然后配置受保护资源、授权策略和基于作用域的权限。

本指南使用 Keycloak 服务账号获取测试访问令牌。客户端作用域策略允许包含 `httpbin-access` 的令牌使用 `access` 授权作用域访问受保护资源。

#### 启动 Keycloak

选择与 APISIX 部署匹配的环境。

<Tabs
groupId="runtime"
defaultValue="docker"
values={[
{label: 'Docker', value: 'docker'},
{label: 'Kubernetes', value: 'k8s'},
]}>

<TabItem value="docker">

以开发模式启动 Keycloak，并将管理控制台绑定到环回接口：

```shell
docker run -d --name apisix-keycloak \
  --network apisix-quickstart-net \
  -e 'KC_BOOTSTRAP_ADMIN_USERNAME=quickstart-admin' \
  -e 'KC_BOOTSTRAP_ADMIN_PASSWORD=quickstart-admin-pass' \
  -p 127.0.0.1:8080:8080 \
  quay.io/keycloak/keycloak:26.7.3 start-dev
```

保存 Keycloak 地址：

```shell
export KEYCLOAK_URL=http://apisix-keycloak:8080
```

</TabItem>

<TabItem value="k8s">

如果命名空间尚不存在，请先创建：

```shell
kubectl create namespace aic --dry-run=client -o yaml | kubectl apply -f -
```

创建 `keycloak.yaml`，其中包含 Keycloak Deployment 和 Service：

```yaml title="keycloak.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: aic
  name: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
        - name: keycloak
          image: quay.io/keycloak/keycloak:26.7.3
          args:
            - start-dev
          env:
            - name: KC_BOOTSTRAP_ADMIN_USERNAME
              value: quickstart-admin
            - name: KC_BOOTSTRAP_ADMIN_PASSWORD
              value: quickstart-admin-pass
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: keycloak
spec:
  selector:
    app: keycloak
  ports:
    - port: 8080
      targetPort: 8080
```

应用清单并等待 Keycloak 可用：

```shell
kubectl apply -f keycloak.yaml
kubectl rollout status -n aic deployment/keycloak
```

保存集群内的 Keycloak 地址：

```shell
export KEYCLOAK_URL=http://keycloak.aic.svc.cluster.local:8080
```

在另一个终端中转发 Keycloak 端口，以便在本地访问管理控制台：

```shell
kubectl port-forward -n aic service/keycloak 8080:8080
```

</TabItem>

</Tabs>

开发模式和示例管理员凭证仅用于本地测试。生产部署应使用 HTTPS、生产数据库和永久管理员账号。

打开 `http://localhost:8080/admin/`，使用管理员用户名 `quickstart-admin` 和密码 `quickstart-admin-pass` 登录。

#### 创建 Realm 和资源服务器

为授权资源创建 Realm：

1. 选择 **Manage realms → Create realm**。
2. 输入 `authz-realm` 作为 Realm 名称。
3. 选择 **Create**。

注册一个机密 OIDC 客户端作为受保护资源服务器：

1. 选择 **Clients → Create client**。
2. 将 **Client type** 保持为 **OpenID Connect**，输入 `apisix-authz` 作为客户端 ID，然后选择 **Next**。
3. 开启 **Client authentication** 和 **Authorization**。保持交互式认证流程关闭，然后选择 **Save**。

![在 Keycloak 中启用客户端认证和授权](https://static.api7.ai/uploads/2026/09/11/7FMltdQ3_authz-keycloak-client-capabilities.jpg)

启用 Authorization 也会启用客户端服务账号并为其分配 `uma_protection` 角色。启用动态路径加载时，APISIX 使用该服务账号查询 Protection API。

#### 创建并分配客户端作用域

创建授权策略所需的客户端作用域：

1. 选择 **Client scopes → Create client scope**。
2. 输入 `httpbin-access` 作为名称，并将 **Protocol** 保持为 **OpenID Connect**。
3. 开启 **Include in token scope**，然后选择 **Save**。
4. 打开 **Clients → apisix-authz → Client scopes**，然后选择 **Add client scope**。
5. 选择 `httpbin-access` 和 **Add**，并将其添加为可选客户端作用域。

![向 Keycloak 客户端分配可选客户端作用域](https://static.api7.ai/uploads/2026/09/11/0ZrLTeZM_authz-keycloak-client-scope.jpg)

后续令牌请求将包含 `scope=httpbin-access`。将该作用域设为可选后，无需修改 Keycloak 配置即可复现拒绝请求示例。

#### 创建授权对象

打开 **Clients → apisix-authz → Authorization**，然后创建作用域和受保护资源：

1. 打开 **Scopes**，选择 **Create authorization scope**，输入 `access`，然后选择 **Save**。
2. 打开 **Resources**，选择 **Create resource**，然后配置以下值：

   | 字段 | 值 |
   | --- | --- |
   | **Name** | `httpbin-anything` |
   | **Display name** | `HTTPBin Anything` |
   | **URIs** | `/anything/authz` |
   | **Authorization scopes** | `access` |

3. 选择 **Save**。

![创建受保护的 Keycloak 资源](https://static.api7.ai/uploads/2026/09/11/Nqy4m40y_authz-keycloak-resources.jpg)

创建要求客户端作用域的策略：

1. 打开 **Policies**，然后选择 **Create client policy → Client scope**。
2. 输入 `httpbin-access-policy` 作为名称。
3. 选择 `httpbin-access` 作为客户端作用域，并将其标记为必需。
4. 选择 **Save**。

![创建 Keycloak 客户端作用域策略](https://static.api7.ai/uploads/2026/09/11/26SlHPNl_authz-keycloak-policy.jpg)

将资源和授权作用域关联到策略：

1. 打开 **Permissions**，然后选择 **Create permission → Scope-based**。
2. 输入 `httpbin-access-permission` 作为名称。
3. 选择 `httpbin-anything` 作为资源、`access` 作为授权作用域，并选择 `httpbin-access-policy` 作为策略。
4. 选择 **Save**。

![创建 Keycloak 基于作用域的权限](https://static.api7.ai/uploads/2026/09/11/7uNxuJ79_authz-keycloak-permission.jpg)

#### 保存客户端凭证

打开 **Clients → apisix-authz → Credentials** 并复制客户端密钥。将客户端 ID 和密钥保存为环境变量：

```shell
export KEYCLOAK_CLIENT_ID=apisix-authz
export KEYCLOAK_CLIENT_SECRET=replace-with-your-client-secret
```

请妥善保管客户端密钥。生产凭证应存储在密钥管理器中，并根据组织的凭证轮换策略定期轮换。

#### 请求访问令牌

请求包含可选客户端作用域的服务账号令牌。根据之前选择的环境运行相应命令。

<Tabs
groupId="runtime"
defaultValue="docker"
values={[
{label: 'Docker', value: 'docker'},
{label: 'Kubernetes', value: 'k8s'},
]}>

<TabItem value="docker">

从快速入门网络中的临时容器发送令牌请求：

```shell
export ACCESS_TOKEN="$(
  docker run --rm --network apisix-quickstart-net \
    curlimages/curl:8.22.0 -sS \
    "${KEYCLOAK_URL}/realms/authz-realm/protocol/openid-connect/token" \
    --user "${KEYCLOAK_CLIENT_ID}:${KEYCLOAK_CLIENT_SECRET}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "scope=httpbin-access" | \
  jq -er '.access_token'
)"
```

</TabItem>

<TabItem value="k8s">

从 `aic` 命名空间中的临时 Pod 发送令牌请求：

```shell
export ACCESS_TOKEN="$(
  kubectl run authz-token-request --rm -i --restart=Never --quiet \
    --namespace aic \
    --image curlimages/curl:8.22.0 \
    --command -- \
    curl -sS \
      "${KEYCLOAK_URL}/realms/authz-realm/protocol/openid-connect/token" \
      --user "${KEYCLOAK_CLIENT_ID}:${KEYCLOAK_CLIENT_SECRET}" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "grant_type=client_credentials" \
      --data-urlencode "scope=httpbin-access" | \
  jq -er '.access_token'
)"
```

</TabItem>

</Tabs>

### 按路径授权请求

动态路径加载使 APISIX 能够将传入请求 URI 解析为 Keycloak 资源。配置路由后，APISIX 会先查询 Protection API，再通过 UMA 令牌端点判断调用方是否可以访问解析出的资源。

选择用于配置路由的 API。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'},
]}>

<TabItem value="admin-api">

通过 Admin API 创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/authz-keycloak" -X PUT \
  --data-binary @- <<EOF
{
  "uri": "/anything/authz",
  "plugins": {
    "authz-keycloak": {
# highlight-start
      // Annotate 1
      "lazy_load_paths": true,
      // Annotate 2
      "discovery": "$KEYCLOAK_URL/realms/authz-realm/.well-known/uma2-configuration",
      // Annotate 3
      "client_id": "$KEYCLOAK_CLIENT_ID",
      "client_secret": "$KEYCLOAK_CLIENT_SECRET"
# highlight-end
    },
# highlight-start
    // Annotate 4
    "serverless-post-function": {
      "phase": "access",
      "functions": [
        "return function(conf, ctx) ngx.req.clear_header('Authorization') end"
      ]
    }
# highlight-end
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
EOF
```

</TabItem>

<TabItem value="adc">

创建包含路由配置的 `adc.yaml`：

```yaml title="adc.yaml"
services:
  - name: authz-keycloak-httpbin
    routes:
      - name: authz-keycloak
        uris:
          - /anything/authz
        plugins:
          authz-keycloak:
            # highlight-start
            // Annotate 1
            lazy_load_paths: true
            // Annotate 2
            discovery: "${KEYCLOAK_URL}/realms/authz-realm/.well-known/uma2-configuration"
            // Annotate 3
            client_id: "${KEYCLOAK_CLIENT_ID}"
            client_secret: "${KEYCLOAK_CLIENT_SECRET}"
            # highlight-end
          # highlight-start
          // Annotate 4
          serverless-post-function:
            phase: access
            functions:
              - "return function(conf, ctx) ngx.req.clear_header('Authorization') end"
          # highlight-end
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步到 APISIX：

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

使用 Gateway API 或 APISIX 自定义资源配置插件。

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'},
]}>

<TabItem value="gateway-api">

创建 `authz-keycloak-ic.yaml`：

```yaml title="authz-keycloak-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-plugin-config
spec:
  plugins:
    - name: authz-keycloak
      config:
        # highlight-start
        // Annotate 1
        lazy_load_paths: true
        // Annotate 2
        discovery: http://keycloak.aic.svc.cluster.local:8080/realms/authz-realm/.well-known/uma2-configuration
        // Annotate 3
        client_id: apisix-authz
        client_secret: replace-with-your-client-secret
        # highlight-end
    # highlight-start
    // Annotate 4
    - name: serverless-post-function
      config:
        phase: access
        functions:
          - "return function(conf, ctx) ngx.req.clear_header('Authorization') end"
    # highlight-end
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: authz-keycloak
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything/authz
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

</TabItem>

<TabItem value="apisix-crd">

创建 `authz-keycloak-ic.yaml`：

```yaml title="authz-keycloak-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
    - type: Domain
      name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixPluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-plugin-config
spec:
  ingressClassName: apisix
  plugins:
    - name: authz-keycloak
      enable: true
      config:
        # highlight-start
        // Annotate 1
        lazy_load_paths: true
        // Annotate 2
        discovery: http://keycloak.aic.svc.cluster.local:8080/realms/authz-realm/.well-known/uma2-configuration
        // Annotate 3
        client_id: apisix-authz
        client_secret: replace-with-your-client-secret
        # highlight-end
    # highlight-start
    // Annotate 4
    - name: serverless-post-function
      enable: true
      config:
        phase: access
        functions:
          - "return function(conf, ctx) ngx.req.clear_header('Authorization') end"
    # highlight-end
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: authz-keycloak
spec:
  ingressClassName: apisix
  http:
    - name: authz-keycloak
      match:
        paths:
          - /anything/authz
        methods:
          - GET
      upstreams:
        - name: httpbin-external-domain
      plugin_config_name: authz-keycloak-plugin-config
```

</TabItem>

</Tabs>

应用配置：

```shell
kubectl apply -f authz-keycloak-ic.yaml
```

</TabItem>

</Tabs>

❶ `lazy_load_paths`：通过 Protection API 将请求 URI 解析为 Keycloak 资源，而不是使用静态权限列表。

❷ `discovery`：Keycloak UMA 发现文档的 URI。插件从该文档获取令牌端点和资源注册端点。

❸ `client_id` 和 `client_secret`：Keycloak 资源服务器客户端的凭证。APISIX 使用这些凭证获取 Protection API 所需的服务账号令牌。

❹ `serverless-post-function`：在 `authz-keycloak` 完成评估后移除调用方的 Bearer 令牌，防止示例上游收到该凭证。如果上游应用需要接收令牌，请不要配置此插件。

#### 验证动态授权

携带访问令牌请求受保护路由：

```shell
curl -i "http://127.0.0.1:9080/anything/authz" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

返回 `HTTP/1.1 200 OK` 表示 Keycloak 已允许该令牌访问资源。响应体应包含类似以下内容的字段：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.7.1",
    "X-Amzn-Trace-Id": "Root=1-...",
    "X-Forwarded-Host": "127.0.0.1:9080"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.155.1, xxx.xxx.xxx.xxx",
  "url": "http://127.0.0.1:9080/anything/authz"
}
```

请求头值和响应中的来源地址会因环境而异。示例上游不应收到 `Authorization` 请求头。

请求另一个不包含所需客户端作用域的访问令牌。

<Tabs
groupId="runtime"
defaultValue="docker"
values={[
{label: 'Docker', value: 'docker'},
{label: 'Kubernetes', value: 'k8s'},
]}>

<TabItem value="docker">

```shell
export TOKEN_WITHOUT_SCOPE="$(
  docker run --rm --network apisix-quickstart-net \
    curlimages/curl:8.22.0 -sS \
    "${KEYCLOAK_URL}/realms/authz-realm/protocol/openid-connect/token" \
    --user "${KEYCLOAK_CLIENT_ID}:${KEYCLOAK_CLIENT_SECRET}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=client_credentials" | \
  jq -er '.access_token'
)"
```

</TabItem>

<TabItem value="k8s">

```shell
export TOKEN_WITHOUT_SCOPE="$(
  kubectl run authz-token-request --rm -i --restart=Never --quiet \
    --namespace aic \
    --image curlimages/curl:8.22.0 \
    --command -- \
    curl -sS \
      "${KEYCLOAK_URL}/realms/authz-realm/protocol/openid-connect/token" \
      --user "${KEYCLOAK_CLIENT_ID}:${KEYCLOAK_CLIENT_SECRET}" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "grant_type=client_credentials" | \
  jq -er '.access_token'
)"
```

</TabItem>

</Tabs>

携带该令牌请求路由：

```shell
curl -i "http://127.0.0.1:9080/anything/authz" \
  -H "Authorization: Bearer ${TOKEN_WITHOUT_SCOPE}"
```

由于该令牌不满足 `httpbin-access-policy`，APISIX 返回 `HTTP/1.1 403 Forbidden`。

发送不包含 Bearer 令牌的请求：

```shell
curl -i "http://127.0.0.1:9080/anything/authz"
```

由于请求中没有可供 Keycloak 评估的令牌，APISIX 返回 `HTTP/1.1 401 Unauthorized`。

### 使用静态权限授权请求

如果所需的 Keycloak 资源和作用域已经明确，可以使用静态权限避免查询 Protection API。配置路由后，每次请求都会由 Keycloak 评估 `httpbin-anything#access`。

选择用于配置路由的 API。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'},
]}>

<TabItem value="admin-api">

通过 Admin API 创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/authz-keycloak-static" -X PUT \
  --data-binary @- <<EOF
{
  "uri": "/anything/authz-static",
  "plugins": {
    "authz-keycloak": {
# highlight-start
      // Annotate 1
      "lazy_load_paths": false,
      // Annotate 2
      "permissions": ["httpbin-anything#access"],
      // Annotate 3
      "discovery": "$KEYCLOAK_URL/realms/authz-realm/.well-known/uma2-configuration",
      "client_id": "$KEYCLOAK_CLIENT_ID"
# highlight-end
    },
    "serverless-post-function": {
      "phase": "access",
      "functions": [
        "return function(conf, ctx) ngx.req.clear_header('Authorization') end"
      ]
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
EOF
```

</TabItem>

<TabItem value="adc">

创建包含路由配置的 `adc-static.yaml`：

```yaml title="adc-static.yaml"
services:
  - name: authz-keycloak-static-httpbin
    routes:
      - name: authz-keycloak-static
        uris:
          - /anything/authz-static
        plugins:
          authz-keycloak:
            # highlight-start
            // Annotate 1
            lazy_load_paths: false
            // Annotate 2
            permissions:
              - httpbin-anything#access
            // Annotate 3
            discovery: "${KEYCLOAK_URL}/realms/authz-realm/.well-known/uma2-configuration"
            client_id: "${KEYCLOAK_CLIENT_ID}"
            # highlight-end
          serverless-post-function:
            phase: access
            functions:
              - "return function(conf, ctx) ngx.req.clear_header('Authorization') end"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步到 APISIX：

```shell
adc sync -f adc-static.yaml
```

</TabItem>

<TabItem value="aic">

使用 Gateway API 或 APISIX 自定义资源配置静态路由。

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'},
]}>

<TabItem value="gateway-api">

创建 `authz-keycloak-static-ic.yaml`：

```yaml title="authz-keycloak-static-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-static-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-static-plugin-config
spec:
  plugins:
    - name: authz-keycloak
      config:
        # highlight-start
        // Annotate 1
        lazy_load_paths: false
        // Annotate 2
        permissions:
          - httpbin-anything#access
        // Annotate 3
        discovery: http://keycloak.aic.svc.cluster.local:8080/realms/authz-realm/.well-known/uma2-configuration
        client_id: apisix-authz
        # highlight-end
    - name: serverless-post-function
      config:
        phase: access
        functions:
          - "return function(conf, ctx) ngx.req.clear_header('Authorization') end"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: authz-keycloak-static
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything/authz-static
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: authz-keycloak-static-plugin-config
      backendRefs:
        - name: httpbin-static-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

创建 `authz-keycloak-static-ic.yaml`：

```yaml title="authz-keycloak-static-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-static-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
    - type: Domain
      name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixPluginConfig
metadata:
  namespace: aic
  name: authz-keycloak-static-plugin-config
spec:
  ingressClassName: apisix
  plugins:
    - name: authz-keycloak
      enable: true
      config:
        # highlight-start
        // Annotate 1
        lazy_load_paths: false
        // Annotate 2
        permissions:
          - httpbin-anything#access
        // Annotate 3
        discovery: http://keycloak.aic.svc.cluster.local:8080/realms/authz-realm/.well-known/uma2-configuration
        client_id: apisix-authz
        # highlight-end
    - name: serverless-post-function
      enable: true
      config:
        phase: access
        functions:
          - "return function(conf, ctx) ngx.req.clear_header('Authorization') end"
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: authz-keycloak-static
spec:
  ingressClassName: apisix
  http:
    - name: authz-keycloak-static
      match:
        paths:
          - /anything/authz-static
        methods:
          - GET
      upstreams:
        - name: httpbin-static-external-domain
      plugin_config_name: authz-keycloak-static-plugin-config
```

</TabItem>

</Tabs>

应用配置：

```shell
kubectl apply -f authz-keycloak-static-ic.yaml
```

</TabItem>

</Tabs>

❶ `lazy_load_paths`：设置为 `false`，使用配置的权限列表而不查询 Protection API。

❷ `permissions`：Keycloak 对该路由的每个请求进行评估的资源和授权作用域。

❸ `discovery` 和 `client_id`：标识 Keycloak UMA 令牌端点和资源服务器。由于静态流程不会调用 Protection API，因此不需要客户端密钥。

#### 验证静态授权

携带允许访问的令牌请求静态路由：

```shell
curl -i "http://127.0.0.1:9080/anything/authz-static" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

APISIX 返回 `HTTP/1.1 200 OK`。改用 `TOKEN_WITHOUT_SCOPE` 发送请求时，将返回 `HTTP/1.1 403 Forbidden`。

至此，Keycloak 授权服务已配置完成，可以在 APISIX 上执行动态和静态权限检查。有关 HTTP 方法作用域、拒绝访问重定向等选项，请参阅[属性](#属性)。有关更多策略和权限类型，请参阅 [Keycloak Authorization Services Guide](https://www.keycloak.org/docs/latest/authorization_services/)。
