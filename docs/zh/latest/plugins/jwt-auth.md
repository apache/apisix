---
title: jwt-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - JWT Auth
  - jwt-auth
description: jwt-auth 插件支持使用 JSON Web Token（JWT）作为客户端在访问上游资源之前进行身份验证的机制。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/jwt-auth" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`jwt-auth` 插件支持使用 [JSON Web Token（JWT）](https://jwt.io/) 作为客户端在访问上游资源之前进行身份验证的机制。

启用后，该插件会暴露一个端点，供 [消费者](../terminology/consumer.md) 创建 JWT 凭据。该过程会生成一个令牌，客户端请求应携带该令牌以向 APISIX 标识自身。令牌可以包含在请求 URL 查询字符串、请求头或 Cookie 中。APISIX 随后会验证该令牌，以判断是否允许或拒绝请求访问上游资源。

当消费者成功通过身份验证后，APISIX 会在将请求代理到上游服务之前，向请求添加额外的请求头，例如 `X-Consumer-Username`、`X-Credential-Identifier` 以及其他已配置的消费者自定义请求头。上游服务可据此区分消费者并根据需要实现额外逻辑。若某个值不可用，则不会添加对应的请求头。

## 属性

以下属性可用于消费者或凭据上的配置。

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| key | string | 是 | | 非空 | 用于标识消费者凭据的唯一键。 |
| secret | string | 否 | | 非空 | 算法为对称算法时，用于签名和验证 JWT 的共享密钥。使用 `HS256`、`HS384` 或 `HS512` 算法时必填。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源将值保存在 Secret Manager 中。 |
| public_key | string | 否 | | | RSA 或 ECDSA 公钥。当 `algorithm` 为 `RS256`、`ES256`、`RS384`、`RS512`、`ES384`、`ES512`、`PS256`、`PS384`、`PS512` 或 `EdDSA` 时必填。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源将值保存在 Secret Manager 中。 |
| algorithm | string | 否 | HS256 | `HS256`、`HS384`、`HS512`、`RS256`、`RS384`、`RS512`、`ES256`、`ES384`、`ES512`、`PS256`、`PS384`、`PS512`、`EdDSA` | 加密算法。 |
| exp | integer | 否 | 86400 | >=1 | 令牌的过期时间，单位为秒。若不使用 APISIX 签发 JWT，则该参数会被忽略，签发时应在 payload 中指定过期时间。 |
| base64_secret | boolean | 否 | false | | 若密钥经过 base64 编码，则设为 true。 |
| lifetime_grace_period | integer | 否 | 0 | >=0 | 宽限期，单位为秒。用于处理生成 JWT 的服务器与验证 JWT 的服务器之间的时钟偏差。 |

注意：Schema 中同时定义了 `encrypt_fields = {"secret"}`，这意味着该字段将在 etcd 中加密存储。详见[加密存储字段](../plugin-develop.md#encrypted-storage-fields)。

以下属性可用于路由或服务上的配置。

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| header | string | 否 | authorization | | 用于获取令牌的请求头。 |
| query | string | 否 | jwt | | 用于获取令牌的查询字符串。优先级低于 header。 |
| cookie | string | 否 | jwt | | 用于获取令牌的 Cookie。优先级低于 query。 |
| hide_credentials | boolean | 否 | false | | 若为 true，则不将携带 JWT 的 header、query 或 cookie 传递给上游服务。 |
| anonymous_consumer | string | 否 | | | 匿名消费者名称。配置后，允许匿名用户绕过身份验证。 |
| claims_to_verify | array[string] | 否 | ["exp", "nbf"] | `exp` 和 `nbf` 的组合 | 指定需要验证的 JWT 声明，以确保令牌在其允许的时间范围内使用。注意，这不是要求 payload 中必须存在的声明，而是在声明存在时进行验证。 |
| store_in_ctx | boolean | 否 | false | | 若为 true，则将 JWT payload 存储在请求上下文变量 `ctx.jwt_auth_payload` 中，以便在同一请求中在 `jwt-auth` 之后执行的插件获取和使用 payload 信息。 |
| realm | string | 否 | jwt | | 身份验证失败时，在 `WWW-Authenticate` 响应头中包含的 realm 值。 |
| key_claim_name | string | 否 | key | | JWT payload 中用于标识关联密钥的声明，例如 `iss`。 |

你可以将 `jwt-auth` 与 [HashiCorp Vault](https://www.vaultproject.io/) 结合使用，通过 [APISIX Secret](../terminology/secret.md) 资源从其[加密 KV 引擎](https://developer.hashicorp.com/vault/docs/secrets/kv)中存储和获取密钥及 RSA 密钥对。

## 示例

以下示例展示了如何针对不同场景使用 `jwt-auth` 插件。

:::note

你可以通过以下命令从 `conf/config.yaml` 中获取 `admin_key` 并保存到环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /conf/config.yaml | sed 's/"//g')
```

:::

### 使用 JWT 进行消费者身份验证

以下示例演示如何为消费者实现 JWT 密钥身份验证。

<Tabs
groupId="api"
defaultValue="dashboard"
values={[
{label: 'Admin API', value: 'dashboard'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'ingress'}
]}>

<TabItem value="dashboard">

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭据：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret-that-is-very-long"
      }
    }
  }'
```

创建带有 `jwt-auth` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-route",
    "uri": "/headers",
    "plugins": {
      "jwt-auth": {}
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

<TabItem value="adc">

创建带有 `jwt-auth` 凭据的消费者和配置了 `jwt-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: jwt-auth
        type: jwt-auth
        config:
          key: jack-key
          secret: jack-hs256-secret-that-is-very-long
services:
  - name: jwt-auth-service
    routes:
      - name: jwt-route
        uris:
          - /headers
        plugins:
          jwt-auth: {}
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

<TabItem value="ingress">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

创建带有 `jwt-auth` 凭据的消费者和配置了 `jwt-auth` 插件的路由：

```yaml title="jwt-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: jwt-auth
      name: primary-cred
      config:
        key: jack-key
        secret: jack-hs256-secret-that-is-very-long
---
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
  name: jwt-auth-plugin-config
spec:
  plugins:
    - name: jwt-auth
      config:
        _meta:
          disable: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: jwt-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /headers
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: jwt-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f jwt-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

ApisixConsumer CRD 存在一个已知问题，配置时会错误地要求提供 `private_key`。该问题将在后续版本中修复。目前，此示例无法通过 APISIX CRD 完成。

</TabItem>

</Tabs>

</TabItem>

</Tabs>

如需为 `jack` 签发 JWT，可以使用 [JWT.io 的 JWT 编码器](https://jwt.io)或其他工具。若使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下步骤：

* 将算法填写为 `HS256`。
* 在 __Valid secret__ 部分将密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 在 payload 中填入消费者密钥 `jack-key`，并以 UNIX 时间戳格式添加 `exp` 或 `nbf`。

payload 应类似如下所示：

```json
{
  "key": "jack-key",
  "nbf": 1729132271
}
```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

携带 JWT 在 `Authorization` 请求头中向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

你应收到类似如下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "headers": {
    "Accept": "*/*",
    "Authorization": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3MjY2NDk2NDAsImtleSI6ImphY2sta2V5In0.kdhumNWrZFxjUvYzWLt4lFr546PNsr9TXuf0Az5opoM",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea951a-4d740d724bd2a44f174d4daf",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-jwt-auth",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

发送携带无效令牌的请求：

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3MjY2NDk2NDAsImtleSI6ImphY2sta2V5In0.kdhumNWrZFxjU_random_random"
```

你应收到类似如下的 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"failed to verify jwt"}
```

### 在请求头、查询字符串或 Cookie 中携带 JWT

以下示例演示如何从指定的请求头、查询字符串和 Cookie 中获取 JWT。

<Tabs
groupId="api"
defaultValue="dashboard"
values={[
{label: 'Admin API', value: 'dashboard'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'ingress'}
]}>

<TabItem value="dashboard">

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭据：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret-that-is-very-long"
      }
    }
  }'
```

创建带有 `jwt-auth` 插件的路由，并指定携带令牌的请求参数：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-route",
    "uri": "/get",
    "plugins": {
      "jwt-auth": {
        "header": "jwt-auth-header",
        "query": "jwt-query",
        "cookie": "jwt-cookie"
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

<TabItem value="adc">

创建带有 `jwt-auth` 凭据的消费者和配置了 `jwt-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: jwt-auth
        type: jwt-auth
        config:
          key: jack-key
          secret: jack-hs256-secret-that-is-very-long
services:
  - name: jwt-auth-service
    routes:
      - name: jwt-route
        uris:
          - /get
        plugins:
          jwt-auth:
            header: jwt-auth-header
            query: jwt-query
            cookie: jwt-cookie
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

<TabItem value="ingress">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

创建带有 `jwt-auth` 凭据的消费者和配置了 `jwt-auth` 插件的路由：

```yaml title="jwt-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: jwt-auth
      name: primary-cred
      config:
        key: jack-key
        secret: jack-hs256-secret-that-is-very-long
---
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
  name: jwt-auth-plugin-config
spec:
  plugins:
    - name: jwt-auth
      config:
        _meta:
          disable: false
        header: jwt-auth-header
        query: jwt-query
        cookie: jwt-cookie
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: jwt-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: jwt-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f jwt-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

ApisixConsumer CRD 存在一个已知问题，配置时会错误地要求提供 `private_key`。该问题将在后续版本中修复。目前，此示例无法通过 APISIX CRD 完成。

</TabItem>

</Tabs>

</TabItem>

</Tabs>

如需为 `jack` 签发 JWT，可以使用 [JWT.io 的 JWT 编码器](https://jwt.io)或其他工具。若使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下步骤：

* 将算法填写为 `HS256`。
* 在 __Valid secret__ 部分将密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 在 payload 中填入消费者密钥 `jack-key`，并以 UNIX 时间戳格式添加 `exp` 或 `nbf`。

payload 应类似如下所示：

```json
{
  "key": "jack-key",
  "nbf": 1729132271
}
```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

#### 通过请求头中的 JWT 验证

携带 JWT 在请求头中发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "jwt-auth-header: ${jwt_token}"
```

你应收到类似如下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "Jwt-Auth-Header": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU",
    ...
  },
  ...
}
```

#### 通过查询字符串中的 JWT 验证

携带 JWT 在查询字符串中发送请求：

```shell
curl -i "http://127.0.0.1:9080/get?jwt-query=${jwt_token}"
```

你应收到类似如下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {
    "jwt-query": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU"
  },
  "headers": {
    "Accept": "*/*",
    ...
  },
  "origin": "127.0.0.1, 183.17.233.107",
  "url": "http://127.0.0.1/get?jwt-query=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTY5NTEyOTA0NH0.EiktFX7di_tBbspbjmqDKoWAD9JG39Wo_CAQ1LZ9voQ"
}
```

#### 通过 Cookie 中的 JWT 验证

携带 JWT 在 Cookie 中发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" --cookie jwt-cookie=${jwt_token}
```

你应收到类似如下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Cookie": "jwt-cookie=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU",
    ...
  },
  ...
}
```

### 在环境变量中管理密钥

以下示例演示如何将 `jwt-auth` 消费者密钥保存到环境变量，并在配置中引用。

APISIX 支持通过 [NGINX `env` 指令](https://nginx.org/en/docs/ngx_core_module.html#env)引用系统和用户配置的环境变量。

将密钥保存到环境变量。若在 Docker 中运行 APISIX，需在启动容器时使用 `-e` 标志设置环境变量。

```shell
export JACK_JWT_SECRET=jack-hs256-secret-that-is-very-long
```

<Tabs
groupId="api"
defaultValue="dashboard"
values={[
{label: 'Admin API', value: 'dashboard'},
{label: 'ADC', value: 'adc'}
]}>

<TabItem value="dashboard">

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭据，并引用环境变量：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "$env://JACK_JWT_SECRET"
      }
    }
  }'
```

创建启用了 `jwt-auth` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-route",
    "uri": "/get",
    "plugins": {
      "jwt-auth": {}
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

<TabItem value="adc">

创建引用环境变量的 `jwt-auth` 凭据的消费者和启用了 `jwt-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: jwt-auth
        type: jwt-auth
        config:
          key: jack-key
          secret: $env://JACK_JWT_SECRET
services:
  - name: jwt-auth-service
    routes:
      - name: jwt-route
        uris:
          - /get
        plugins:
          jwt-auth: {}
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

</Tabs>

如需为 `jack` 签发 JWT，可以使用 [JWT.io 的 JWT 编码器](https://jwt.io)或其他工具。若使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下步骤：

* 将算法填写为 `HS256`。
* 在 __Valid secret__ 部分将密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 在 payload 中填入消费者密钥 `jack-key`，并以 UNIX 时间戳格式添加 `exp` 或 `nbf`。

payload 应类似如下所示：

```json
{
  "key": "jack-key",
  "nbf": 1729132271
}
```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

携带 JWT 在请求头中发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jwt_token}"
```

你应收到 `HTTP/1.1 200 OK` 响应。

### 在 Secret Manager 中管理密钥

以下示例演示如何在 [HashiCorp Vault](https://www.vaultproject.io) 中管理 `jwt-auth` 消费者密钥，并在插件配置中引用。

在 Docker 中启动 Vault 开发服务器：

```shell
docker run -d \
  --name vault \
  -p 8200:8200 \
  --cap-add IPC_LOCK \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  vault:1.9.0 \
  vault server -dev
```

APISIX 目前支持 [Vault KV 引擎第 1 版](https://developer.hashicorp.com/vault/docs/secrets/kv#kv-version-1)。在 Vault 中启用它：

```shell
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault secrets enable -path=kv -version=1 kv"
```

你应收到类似如下的响应：

```text
Success! Enabled the kv secrets engine at: kv/
```

<Tabs
groupId="api"
defaultValue="dashboard"
values={[
{label: 'Admin API', value: 'dashboard'},
{label: 'ADC', value: 'adc'}
]}>

<TabItem value="dashboard">

创建 [Secret](../terminology/secret.md) 并配置 Vault 地址及其他连接信息，请根据实际情况调整 Vault 地址：

```shell
curl "http://127.0.0.1:9180/apisix/admin/secrets/vault/jwt" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "http://127.0.0.1:8200",
    "prefix": "kv/apisix",
    "token": "root"
  }'
```

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭据，并引用 Secret：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jwt-vault-key",
        "secret": "$secret://vault/jwt/jack/jwt-secret"
      }
    }
  }'
```

创建启用了 `jwt-auth` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-route",
    "uri": "/get",
    "plugins": {
      "jwt-auth": {}
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

<TabItem value="adc">

创建 Secret 并配置 Vault 地址，请根据实际情况调整 Vault 地址：

```yaml title="adc.yaml"
secrets:
  - name: vault-jwt
    vault:
      url: http://127.0.0.1:8200
      prefix: kv/apisix
      token: root
consumers:
  - username: jack
    credentials:
      - name: jwt-auth
        type: jwt-auth
        config:
          key: jwt-vault-key
          secret: $secret://vault-jwt/jack/jwt-secret
services:
  - name: jwt-auth-service
    routes:
      - name: jwt-route
        uris:
          - /get
        plugins:
          jwt-auth: {}
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

</Tabs>

在 Vault 中设置 `jwt-auth` 密钥值为 `vault-hs256-secret-that-is-very-long`：

```shell
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/jack jwt-secret=vault-hs256-secret-that-is-very-long"
```

你应收到类似如下的响应：

```text
Success! Data written to: kv/apisix/jack
```

如需签发 JWT，可以使用 [JWT.io 的 JWT 编码器](https://jwt.io)或其他工具。若使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下步骤：

* 将算法填写为 `HS256`。
* 在 __Valid secret__ 部分将密钥更新为 `vault-hs256-secret-that-is-very-long`。
* 在 payload 中填入消费者密钥 `jwt-vault-key`，并以 UNIX 时间戳格式添加 `exp` 或 `nbf`。

payload 应类似如下所示：

```json
{
  "key": "jwt-vault-key",
  "nbf": 1729132271
}
```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqd3QtdmF1bHQta2V5IiwibmJmIjoxNzI5MTMyMjcxfQ.i2pLj7QcQvnlSjB7iV5V522tIV43boQRtee7L0rwlkQ
```

携带令牌在请求头中发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jwt_token}"
```

你应收到 `HTTP/1.1 200 OK` 响应。

### 使用 RS256 算法签名 JWT

以下示例演示如何使用 RS256 等非对称算法对 JWT 进行签名和验证。你将使用 [openssl](https://openssl-library.org/source/) 生成 RSA 密钥对，并使用 [JWT.io](https://jwt.io) 生成 JWT，以便更好地理解 JWT 的组成。

生成 2048 位 RSA 私钥并提取对应的 PEM 格式公钥：

```shell
openssl genrsa -out jwt-rsa256-private.pem 2048
openssl rsa -in jwt-rsa256-private.pem -pubout -out jwt-rsa256-public.pem
```

你应在当前工作目录中看到生成的 `jwt-rsa256-private.pem` 和 `jwt-rsa256-public.pem` 文件。

访问 [JWT.io 的 JWT 编码器](https://jwt.io)并执行以下步骤：

* 将算法填写为 `RS256`。
* 将私钥内容复制粘贴到 __SIGN JWT: PRIVATE KEY__ 部分。
* 在 payload 中填入消费者密钥 `jack-key`，并以 UNIX 时间戳格式添加 `exp` 或 `nbf`。

payload 应类似如下所示：

```json
{
  "key": "jack-key",
  "nbf": 1729132271
}
```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.K-I13em84kAcyH1jfIJl7ls_4jlwg1GzEzo5_xrDu-3wt3Xa3irS6naUsWpxX-a-hmcZZxRa9zqunqQjUP4kvn5e3xg2f_KyCR-_ZbwqYEPk3bXeFV1l4iypv6z5L7W1Niharun-dpMU03b1Tz64vhFx6UwxNL5UIZ7bunDAo_BXZ7Xe8rFhNHvIHyBFsDEXIBgx8lNYMq8QJk3iKxZhZZ5Om7lgYjOOKRgew4WkhBAY0v1AkO77nTlvSK0OEeeiwhkROyntggyx-S-U222ykMQ6mBLxkP4Cq5qHwXD8AUcLk5mhEij-3QhboYnt7yhKeZ3wDSpcjDvvL2aasC25ng
```

<Tabs
groupId="api"
defaultValue="dashboard"
values={[
{label: 'Admin API', value: 'dashboard'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'ingress'}
]}>

<TabItem value="dashboard">

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `jwt-auth` 凭据，并配置 RSA 密钥。公钥的起始行与结束行之后需要添加换行符，例如 `-----BEGIN PUBLIC KEY-----\n......\n-----END PUBLIC KEY-----`，密钥内容可以直接拼接。

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "algorithm": "RS256",
        "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoTxe7ZPycrEP0SK4OBA2\n0OUQsDN9gSFSHVvx/t++nZNrFxzZnV6q6/TRsihNXUIgwaOu5icFlIcxPL9Mf9UJ\na5/XCQExp1TxpuSmjkhIFAJ/x5zXrC8SGTztP3SjkhYnQO9PKVXI6ljwgakVCfpl\numuTYqI+ev7e45NdK8gJoJxPp8bPMdf8/nHfLXZuqhO/btrDg1x+j7frDNrEw+6B\nCK2SsuypmYN+LwHfaH4Of7MQFk3LNIxyBz0mdbsKJBzp360rbWnQeauWtDymZxLT\nATRNBVyl3nCNsURRTkc7eyknLaDt2N5xTIoUGHTUFYSdE68QWmukYMVGcEHEEPkp\naQIDAQAB\n-----END PUBLIC KEY-----"
      }
    }
  }'
```

创建带有 `jwt-auth` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-route",
    "uri": "/headers",
    "plugins": {
      "jwt-auth": {}
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

<TabItem value="adc">

创建使用 RS256 算法的 `jwt-auth` 凭据的消费者和启用了 `jwt-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: jwt-auth
        type: jwt-auth
        config:
          key: jack-key
          algorithm: RS256
          public_key: |
            -----BEGIN PUBLIC KEY-----
            MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoTxe7ZPycrEP0SK4OBA2
            0OUQsDN9gSFSHVvx/t++nZNrFxzZnV6q6/TRsihNXUIgwaOu5icFlIcxPL9Mf9UJ
            a5/XCQExp1TxpuSmjkhIFAJ/x5zXrC8SGTztP3SjkhYnQO9PKVXI6ljwgakVCfpl
            umuTYqI+ev7e45NdK8gJoJxPp8bPMdf8/nHfLXZuqhO/btrDg1x+j7frDNrEw+6B
            CK2SsuypmYN+LwHfaH4Of7MQFk3LNIxyBz0mdbsKJBzp360rbWnQeauWtDymZxLT
            ATRNBVyl3nCNsURRTkc7eyknLaDt2N5xTIoUGHTUFYSdE68QWmukYMVGcEHEEPkp
            aQIDAQAB
            -----END PUBLIC KEY-----
services:
  - name: jwt-auth-service
    routes:
      - name: jwt-route
        uris:
          - /headers
        plugins:
          jwt-auth: {}
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

<TabItem value="ingress">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

创建使用 RS256 算法的 `jwt-auth` 凭据的消费者和启用了 `jwt-auth` 插件的路由：

```yaml title="jwt-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: jwt-auth
      name: primary-cred
      config:
        key: jack-key
        algorithm: RS256
        public_key: |
          -----BEGIN PUBLIC KEY-----
          MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoTxe7ZPycrEP0SK4OBA2
          0OUQsDN9gSFSHVvx/t++nZNrFxzZnV6q6/TRsihNXUIgwaOu5icFlIcxPL9Mf9UJ
          a5/XCQExp1TxpuSmjkhIFAJ/x5zXrC8SGTztP3SjkhYnQO9PKVXI6ljwgakVCfpl
          umuTYqI+ev7e45NdK8gJoJxPp8bPMdf8/nHfLXZuqhO/btrDg1x+j7frDNrEw+6B
          CK2SsuypmYN+LwHfaH4Of7MQFk3LNIxyBz0mdbsKJBzp360rbWnQeauWtDymZxLT
          ATRNBVyl3nCNsURRTkc7eyknLaDt2N5xTIoUGHTUFYSdE68QWmukYMVGcEHEEPkp
          aQIDAQAB
          -----END PUBLIC KEY-----
---
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
  name: jwt-auth-plugin-config
spec:
  plugins:
    - name: jwt-auth
      config:
        _meta:
          disable: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: jwt-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /headers
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: jwt-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f jwt-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

ApisixConsumer CRD 存在一个已知问题，配置时会错误地要求提供 `private_key`。该问题将在后续版本中修复。目前，此示例无法通过 APISIX CRD 完成。

</TabItem>

</Tabs>

</TabItem>

</Tabs>

验证时，携带 JWT 在 `Authorization` 请求头中向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

你应收到 `HTTP/1.1 200 OK` 响应。

### 在请求头中添加消费者自定义 ID

以下示例演示如何在已验证请求的 `Consumer-Custom-Id` 请求头中附加消费者自定义 ID，以便根据需要实现额外逻辑。

<Tabs
groupId="api"
defaultValue="dashboard"
values={[
{label: 'Admin API', value: 'dashboard'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'ingress'}
]}>

<TabItem value="dashboard">

创建带有自定义 ID 标签的消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

为消费者创建 `jwt-auth` 凭据：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret-that-is-very-long"
      }
    }
  }'
```

创建带有 `jwt-auth` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-auth-route",
    "uri": "/anything",
    "plugins": {
      "jwt-auth": {}
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

<TabItem value="adc">

创建带有 `jwt-auth` 凭据的消费者和启用了 `jwt-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    labels:
      custom_id: "495aec6a"
    credentials:
      - name: jwt-auth
        type: jwt-auth
        config:
          key: jack-key
          secret: jack-hs256-secret-that-is-very-long
services:
  - name: jwt-auth-service
    routes:
      - name: jwt-auth-route
        uris:
          - /anything
        plugins:
          jwt-auth: {}
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

<TabItem value="ingress">

通过 Ingress Controller 配置资源时，目前不支持消费者自定义标签，请求中也不会包含 `X-Consumer-Custom-Id` 请求头。目前，此示例无法通过 Ingress Controller 完成。

</TabItem>

</Tabs>

如需为 `jack` 签发 JWT，可以使用 [JWT.io 的 JWT 编码器](https://jwt.io)或其他工具。若使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下步骤：

* 将算法填写为 `HS256`。
* 在 __Valid secret__ 部分将密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 在 payload 中填入消费者密钥 `jack-key`，并以 UNIX 时间戳格式添加 `exp` 或 `nbf`。

payload 应类似如下所示：

```json
{
  "key": "jack-key",
  "nbf": 1729132271
}
```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

验证时，携带 JWT 在 `Authorization` 请求头中向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/headers" -H "Authorization: ${jwt_token}"
```

你应看到类似如下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "headers": {
    "Accept": "*/*",
    "Authorization": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-6873b19d-329331db76e5e7194c942b47",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-jwt-auth",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

### 使用匿名消费者进行限速

以下示例演示如何为普通消费者和匿名消费者配置不同的限速策略，其中匿名消费者无需身份验证，但配额较少。

<Tabs
groupId="api"
defaultValue="dashboard"
values={[
{label: 'Admin API', value: 'dashboard'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'ingress'}
]}>

<TabItem value="dashboard">

创建普通消费者 `jack`，并配置 `limit-count` 插件，允许在 30 秒窗口内最多请求 3 次：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

为消费者 `jack` 创建 `jwt-auth` 凭据：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jack-key",
        "secret": "jack-hs256-secret-that-is-very-long"
      }
    }
  }'
```

创建匿名用户 `anonymous`，并配置 `limit-count` 插件，允许在 30 秒窗口内最多请求 1 次：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "anonymous",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

创建路由，并配置 `jwt-auth` 插件允许匿名消费者 `anonymous` 绕过身份验证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "jwt-auth-route",
    "uri": "/anything",
    "plugins": {
      "jwt-auth": {
        "anonymous_consumer": "anonymous"
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

<TabItem value="adc">

配置具有不同限速策略的消费者和允许匿名用户的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    plugins:
      limit-count:
        count: 3
        time_window: 30
        rejected_code: 429
        policy: local
    credentials:
      - name: jwt-auth
        type: jwt-auth
        config:
          key: jack-key
          secret: jack-hs256-secret-that-is-very-long
  - username: anonymous
    plugins:
      limit-count:
        count: 1
        time_window: 30
        rejected_code: 429
        policy: local
services:
  - name: anonymous-rate-limit-service
    routes:
      - name: jwt-auth-route
        uris:
          - /anything
        plugins:
          jwt-auth:
            anonymous_consumer: anonymous
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

<TabItem value="ingress">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

配置具有不同限速策略的消费者和允许匿名用户的路由：

```yaml title="jwt-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: jwt-auth
      name: primary-key
      config:
        key: jack-key
        secret: jack-hs256-secret-that-is-very-long
  plugins:
    - name: limit-count
      config:
        count: 3
        time_window: 30
        rejected_code: 429
        policy: local
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: anonymous
spec:
  gatewayRef:
    name: apisix
  plugins:
    - name: limit-count
      config:
        count: 1
        time_window: 30
        rejected_code: 429
        policy: local
---
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
  name: jwt-auth-plugin-config
spec:
  plugins:
    - name: jwt-auth
      config:
        anonymous_consumer: aic_anonymous  # namespace_consumername
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: jwt-auth-route
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
            name: jwt-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f jwt-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

ApisixConsumer CRD 目前不支持在消费者上配置插件（`authParameter` 中允许的认证插件除外）。此示例无法通过 APISIX CRD 完成。

</TabItem>

</Tabs>

</TabItem>

</Tabs>

如需为 `jack` 签发 JWT，可以使用 [JWT.io 的 JWT 编码器](https://jwt.io)或其他工具。若使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下步骤：

* 将算法填写为 `HS256`。
* 在 __Valid secret__ 部分将密钥更新为 `jack-hs256-secret-that-is-very-long`。
* 在 payload 中填入消费者密钥 `jack-key`，并以 UNIX 时间戳格式添加 `exp` 或 `nbf`。

payload 应类似如下所示：

```json
{
  "key": "jack-key",
  "nbf": 1729132271
}
```

复制生成的 JWT 并保存到变量：

```shell
export jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJqYWNrLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.UEPXy5jpid624T1XpfjM0PLY73LZPjV3Qt8yZ92kVuU
```

验证限速效果，连续发送 5 次携带 `jack` JWT 的请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H "Authorization: ${jwt_token}" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

你应看到如下响应，说明 5 次请求中有 3 次成功（状态码 200），其余被拒绝（状态码 429）：

```text
200:    3, 429:    2
```

发送 5 次匿名请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

你应看到如下响应，说明只有 1 次请求成功：

```text
200:    1, 429:    4
```
