---
title: hmac-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - HMAC Authentication
  - hmac-auth
description: hmac-auth 插件支持 HMAC 认证，保证请求的完整性，防止传输过程中的修改，增强 API 的安全性。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/hmac-auth" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`hmac-auth` 插件支持 HMAC（基于哈希的消息认证码）认证，作为一种确保请求完整性的机制，防止它们在传输过程中被修改。要使用该插件，您需要在 [Consumers](../terminology/consumer.md) 上配置 HMAC 密钥，并在 Routes 或 Services 上启用该插件。

当 Consumer 成功通过身份验证后，APISIX 会在将请求代理到上游服务之前向请求添加其他标头，例如 `X-Consumer-Username`、`X-Credential-Identifier` 和其他 Consumer 自定义标头（如果已配置）。上游服务将能够区分 Consumer 并根据需要实现其他逻辑。如果这些值中的任何一个不可用，则不会添加相应的标头。

## 实现原理

启用后，插件会验证请求 `Authorization: Signature ...` 中携带的签名，以确认请求内容未被篡改且来自持有对应密钥的调用方。具体来说，APISIX 会先从 `Authorization` 标头中解析 `keyId`、`algorithm`、`signature` 和 `headers` 等参数，再根据 `keyId` 查找对应的 Consumer 或 Credential 配置并获取密钥。随后，插件会按照 `headers` 列表中声明的顺序拼接 signing string，其中可包含 `@request-target` 以及其他参与签名的请求标头，然后使用指定算法和密钥生成 HMAC，并将结果与 `signature` 参数经 base64 解码后的值进行比较。只有两者一致时，请求才会通过身份验证并转发到上游服务。

`Date` 标头主要用于 clock skew（时钟偏移）校验；只有当它被显式包含在 `headers` 列表中时，才会作为 signing string 的一部分参与签名计算。
插件实现基于 [draft-cavage-http-signatures](https://www.ietf.org/archive/id/draft-cavage-http-signatures-12.txt)。

## 属性

以下属性可用于 Consumers 或 Credentials 的配置。

| 名称       | 类型   | 必选项 | 默认值 | 有效值 | 描述                                                                                                                                           |
|------------|--------|--------|--------|--------|------------------------------------------------------------------------------------------------------------------------------------------------|
| key_id     | string | 是     |        |        | 用于标识 HMAC 密钥/凭证的 keyId，并用于查找关联的 Consumer/Credential。                                                                        |
| secret_key | string | 是     |        |        | 用于生成 HMAC 的密钥。此字段支持使用 [APISIX Secret](../terminology/secret.md) 资源将值保存在 Secret Manager 中。                              |

注意：schema 中还定义了 `encrypt_fields = {"secret_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

以下属性可用于 Routes 或 Services 的配置。

| 名称                  | 类型          | 必选项 | 默认值                                         | 有效值                                                              | 描述                                                                                                                                                                                                                                                                                                                                                    |
|-----------------------|---------------|--------|------------------------------------------------|---------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| allowed_algorithms    | array[string] | 否     | `["hmac-sha1", "hmac-sha256", "hmac-sha512"]`  | `"hmac-sha1"`、`"hmac-sha256"` 和 `"hmac-sha512"` 的组合           | 允许的 HMAC 算法列表。                                                                                                                                                                                                                                                                                                                                   |
| clock_skew            | integer       | 否     | 300                                            | >=1                                                                 | 客户端请求的时间戳与 APISIX 服务器当前时间之间允许的最大时间差（以秒为单位）。这有助于解决客户端和服务器之间的时间同步差异，并防止重放攻击。时间戳将根据 `Date` 头中的时间（必须为 GMT 格式）进行计算。                                                                                                                                                  |
| signed_headers        | array[string] | 否     |                                                |                                                                     | 客户端请求的 HMAC 签名中应包含的标头列表。                                                                                                                                                                                                                                                                                                               |
| validate_request_body | boolean       | 否     | false                                          |                                                                     | 如果为 true，则验证请求正文的完整性，以确保在传输过程中没有被篡改。具体来说，插件会创建一个 SHA-256 的 base64 编码 digest，并将其与 `Digest` 头进行比较。如果 `Digest` 头丢失或 digest 不匹配，验证将失败。                                                                                                                                                |
| hide_credentials      | boolean       | 否     | false                                          |                                                                     | 如果为 true，则不会将授权请求头传递给上游服务。                                                                                                                                                                                                                                                                                                          |
| anonymous_consumer    | string        | 否     |                                                |                                                                     | 匿名 Consumer 名称。如果已配置，则允许匿名用户绕过身份验证。                                                                                                                                                                                                                                                                                             |
| realm                 | string        | 否     | `hmac`                                         |                                                                     | 在身份验证失败时，[`WWW-Authenticate`](https://datatracker.ietf.org/doc/html/rfc7235#section-4.1) 响应标头中返回的域，状态码为 `401 Unauthorized`。                                                                                                                                                                                                      |

## 示例

下面的示例说明了如何在不同场景中使用 `hmac-auth` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
```

:::

### 在 Route 上实现 HMAC 身份验证

以下示例演示如何在 Route 上实现 HMAC 身份验证。您还将在 `X-Consumer-Custom-Id` 标头中将 Consumer 自定义 ID 附加到经过身份验证的请求，该 ID 可用于根据需要实现其他逻辑。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建一个带有自定义 ID 标签的 Consumer `john`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

为 Consumer 创建 `hmac-auth` Credential：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

使用 `hmac-auth` 插件的默认配置创建 Route：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {}
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

创建带有 `hmac-auth` Credential 的 Consumer 以及配置了 `hmac-auth` 插件的 Route：

```yaml title="adc.yaml"
consumers:
  - username: john
    labels:
      custom_id: "495aec6a"
    credentials:
      - name: hmac-auth
        type: hmac-auth
        config:
          key_id: john-key
          secret_key: john-secret-key
services:
  - name: hmac-auth-service
    routes:
      - name: hmac-auth-route
        uris:
          - /get
        methods:
          - GET
        plugins:
          hmac-auth: {}
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

通过 Ingress Controller 配置资源时，目前不支持 Consumer 自定义标签。因此，`X-Consumer-Custom-Id` 标头不会包含在请求中。

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="hmac-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: john
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: hmac-auth
      name: primary-cred
      config:
        key_id: john-key
        secret_key: john-secret-key
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
  name: hmac-auth-plugin-config
spec:
  plugins:
    - name: hmac-auth
      config:
        _meta:
          disable: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: hmac-auth-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
          method: GET
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: hmac-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f hmac-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="hmac-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: john
spec:
  ingressClassName: apisix
  authParameter:
    hmacAuth:
      value:
        key_id: john-key
        secret_key: john-secret-key
---
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
kind: ApisixRoute
metadata:
  namespace: aic
  name: hmac-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: hmac-auth-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: hmac-auth
        enable: true
```

将配置应用到集群：

```shell
kubectl apply -f hmac-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

生成签名。您可以使用以下 Python 代码片段或其他技术栈：

```python title="hmac-sig-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # key id
secret_key = b"john-secret-key"    # secret key
request_method = "GET"             # HTTP method
request_path = "/get"              # Route URI
algorithm= "hmac-sha256"           # can use other algorithms in allowed_algorithms

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s)
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
  f"{key_id}\n"
  f"{request_method} {request_path}\n"
  f"date: {gmt_time}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# construct the request headers
headers = {
  "Date": gmt_time,
  "Authorization": (
    f'Signature keyId="{key_id}",algorithm="{algorithm}",'
    f'headers="@request-target date",'
    f'signature="{signature_base64}"'
  )
}

# print headers
print(headers)
```

运行脚本：

```shell
python3 hmac-sig-header-gen.py
```

您应该看到打印的请求标头：

```text
{'Date': 'Fri, 06 Sep 2024 06:41:29 GMT', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'}
```

使用生成的标头，向 Route 发送请求：

```shell
curl -X GET "http://127.0.0.1:9080/get" \
  -H "Date: Fri, 06 Sep 2024 06:41:29 GMT" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Signature keyId=\"john-key\",algorithm=\"hmac-sha256\",headers=\"@request-target date\",signature=\"wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM=\"",
    "Date": "Fri, 06 Sep 2024 06:41:29 GMT",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d96513-2e52d4f35c9b6a2772d667ea",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/get"
}
```

### 对上游隐藏授权信息

如[上一个示例](#在-route-上实现-hmac-身份验证)所示，传递给上游的 `Authorization` 标头包含签名和所有其他详细信息。这可能会带来安全风险。

本示例继续上一个示例，演示如何阻止将这些信息发送到上游服务。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

更新插件配置，将 `hide_credentials` 设置为 `true`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/hmac-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "hmac-auth": {
      "hide_credentials": true
    }
  }
}'
```

</TabItem>

<TabItem value="adc">

更新插件配置：

```yaml title="adc.yaml"
consumers:
  - username: john
    labels:
      custom_id: "495aec6a"
    credentials:
      - name: hmac-auth
        type: hmac-auth
        config:
          key_id: john-key
          secret_key: john-secret-key
services:
  - name: hmac-auth-service
    routes:
      - name: hmac-auth-route
        uris:
          - /get
        methods:
          - GET
        plugins:
          hmac-auth:
            hide_credentials: true
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
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

更新 PluginConfig，将 `hide_credentials` 设置为 `true`：

```yaml title="hmac-auth-ic.yaml"
# other configs
# ---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: hmac-auth-plugin-config
spec:
  plugins:
    - name: hmac-auth
      config:
        _meta:
          disable: false
        hide_credentials: true
```

将配置应用到集群：

```shell
kubectl apply -f hmac-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

更新 ApisixRoute，将 `hide_credentials` 设置为 `true`：

```yaml title="hmac-auth-ic.yaml"
# other configs
# ---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: hmac-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: hmac-auth-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: hmac-auth
        enable: true
        config:
          hide_credentials: true
```

将配置应用到集群：

```shell
kubectl apply -f hmac-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向 Route 发送请求：

```shell
curl -X GET "http://127.0.0.1:9080/get" \
  -H "Date: Fri, 06 Sep 2024 06:41:29 GMT" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="wWfKQvPDr0wHQ4IHdluB4IzeNZcj0bGJs2wvoCOT5rM="'
```

您应该会看到 `HTTP/1.1 200 OK` 响应，且注意 `Authorization` 标头已被完全移除：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d96513-2e52d4f35c9b6a2772d667ea",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/get"
}
```

### 启用请求正文验证

以下示例演示如何启用请求正文验证以确保请求正文的完整性。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建 Consumer `john`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

为 Consumer 创建 `hmac-auth` Credential：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

创建带有 `hmac-auth` 插件的 Route：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/post",
    "methods": ["POST"],
    "plugins": {
      "hmac-auth": {
        "validate_request_body": true
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

创建带有 `hmac-auth` Credential 的 Consumer 以及配置了 `hmac-auth` 插件的 Route：

```yaml title="adc.yaml"
consumers:
  - username: john
    credentials:
      - name: hmac-auth
        type: hmac-auth
        config:
          key_id: john-key
          secret_key: john-secret-key
services:
  - name: hmac-auth-service
    routes:
      - name: hmac-auth-route
        uris:
          - /post
        methods:
          - POST
        plugins:
          hmac-auth:
            validate_request_body: true
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
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="hmac-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: john
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: hmac-auth
      name: primary-cred
      config:
        key_id: john-key
        secret_key: john-secret-key
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
  name: hmac-auth-plugin-config
spec:
  plugins:
    - name: hmac-auth
      config:
        _meta:
          disable: false
        validate_request_body: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: hmac-auth-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /post
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: hmac-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f hmac-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="hmac-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: john
spec:
  ingressClassName: apisix
  authParameter:
    hmacAuth:
      value:
        key_id: john-key
        secret_key: john-secret-key
---
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
kind: ApisixRoute
metadata:
  namespace: aic
  name: hmac-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: hmac-auth-route
      match:
        paths:
          - /post
        methods:
          - POST
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: hmac-auth
        enable: true
        config:
          validate_request_body: true
```

将配置应用到集群：

```shell
kubectl apply -f hmac-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

生成签名。您可以使用以下 Python 代码片段或其他技术栈：

```python title="hmac-sig-digest-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                 # key id
secret_key = b"john-secret-key"     # secret key
request_method = "POST"             # HTTP method
request_path = "/post"              # Route URI
algorithm= "hmac-sha256"            # can use other algorithms in allowed_algorithms
body = '{"name": "world"}'          # example request body

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s).
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
    f"{key_id}\n"
    f"{request_method} {request_path}\n"
    f"date: {gmt_time}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# create the SHA-256 digest of the request body and base64 encode it
body_digest = hashlib.sha256(body.encode('utf-8')).digest()
body_digest_base64 = base64.b64encode(body_digest).decode('utf-8')

# construct the request headers
headers = {
    "Date": gmt_time,
    "Digest": f"SHA-256={body_digest_base64}",
    "Authorization": (
        f'Signature keyId="{key_id}",algorithm="hmac-sha256",'
        f'headers="@request-target date",'
        f'signature="{signature_base64}"'
    )
}

# print headers
print(headers)
```

运行脚本：

```shell
python3 hmac-sig-digest-header-gen.py
```

您应该看到打印的请求标头：

```text
{'Date': 'Fri, 06 Sep 2024 09:16:16 GMT', 'Digest': 'SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE="'}
```

使用生成的标头，向 Route 发送请求：

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H "Date: Fri, 06 Sep 2024 09:16:16 GMT" \
  -H "Digest: SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE="' \
  -d '{"name": "world"}'
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "{\"name\": \"world\"}": ""
  },
  "headers": {
    "Accept": "*/*",
    "Authorization": "Signature keyId=\"john-key\",algorithm=\"hmac-sha256\",headers=\"@request-target date\",signature=\"rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE=\"",
    "Content-Length": "17",
    "Content-Type": "application/x-www-form-urlencoded",
    "Date": "Fri, 06 Sep 2024 09:16:16 GMT",
    "Digest": "SHA-256=78qzJuLwSpZ8HacsTdFCQJWxzPMOf8bYctRk2ySLpS8=",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d978c3-49f929ad5237da5340bbbeb4",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "origin": "192.168.65.1, 34.0.34.160",
  "url": "http://127.0.0.1/post"
}
```

如果您发送的请求没有 digest 或 digest 无效：

```shell
curl "http://127.0.0.1:9080/post" -X POST \
  -H "Date: Fri, 06 Sep 2024 09:16:16 GMT" \
  -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="rjS6NxOBKmzS8CZL05uLiAfE16hXdIpMD/L/HukOTYE="' \
  -d '{"name": "world"}'
```

您应该看到一个 `HTTP/1.1 401 Unauthorized` 响应，其中包含以下消息：

```text
{"message":"client request can't be validated"}
```

### 强制签名标头

以下示例演示了如何强制在请求的 HMAC 签名中对某些标头进行签名。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建 Consumer `john`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

为 Consumer 创建 `hmac-auth` Credential：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

使用 `hmac-auth` 插件创建 Route，该插件要求 HMAC 签名中存在三个标头：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {
        "signed_headers": ["date","x-custom-header-a", "x-custom-header-b"]
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

创建带有 `hmac-auth` Credential 的 Consumer 以及配置了 `hmac-auth` 插件的 Route：

```yaml title="adc.yaml"
consumers:
  - username: john
    credentials:
      - name: hmac-auth
        type: hmac-auth
        config:
          key_id: john-key
          secret_key: john-secret-key
services:
  - name: hmac-auth-service
    routes:
      - name: hmac-auth-route
        uris:
          - /get
        methods:
          - GET
        plugins:
          hmac-auth:
            signed_headers:
              - date
              - x-custom-header-a
              - x-custom-header-b
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
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="hmac-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: john
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: hmac-auth
      name: primary-cred
      config:
        key_id: john-key
        secret_key: john-secret-key
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
  name: hmac-auth-plugin-config
spec:
  plugins:
    - name: hmac-auth
      config:
        _meta:
          disable: false
        signed_headers:
          - date
          - x-custom-header-a
          - x-custom-header-b
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: hmac-auth-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
          method: GET
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: hmac-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f hmac-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="hmac-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: john
spec:
  ingressClassName: apisix
  authParameter:
    hmacAuth:
      value:
        key_id: john-key
        secret_key: john-secret-key
---
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
kind: ApisixRoute
metadata:
  namespace: aic
  name: hmac-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: hmac-auth-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: hmac-auth
        enable: true
        config:
          signed_headers:
            - date
            - x-custom-header-a
            - x-custom-header-b
```

将配置应用到集群：

```shell
kubectl apply -f hmac-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

生成签名。您可以使用以下 Python 代码片段或其他技术栈：

```python title="hmac-sig-req-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # key id
secret_key = b"john-secret-key"    # secret key
request_method = "GET"             # HTTP method
request_path = "/get"              # Route URI
algorithm= "hmac-sha256"           # can use other algorithms in allowed_algorithms
custom_header_a = "hello123"       # required custom header
custom_header_b = "world456"       # required custom header

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s)
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
    f"{key_id}\n"
    f"{request_method} {request_path}\n"
    f"date: {gmt_time}\n"
    f"x-custom-header-a: {custom_header_a}\n"
    f"x-custom-header-b: {custom_header_b}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# construct the request headers
headers = {
    "Date": gmt_time,
    "Authorization": (
        f'Signature keyId="{key_id}",algorithm="hmac-sha256",'
        f'headers="@request-target date x-custom-header-a x-custom-header-b",'
        f'signature="{signature_base64}"'
    ),
    "x-custom-header-a": custom_header_a,
    "x-custom-header-b": custom_header_b
}

# print headers
print(headers)
```

运行脚本：

```shell
python3 hmac-sig-req-header-gen.py
```

您应该看到打印的请求标头：

```text
{'Date': 'Fri, 06 Sep 2024 09:58:49 GMT', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date x-custom-header-a x-custom-header-b",signature="MwJR8JOhhRLIyaHlJ3Snbrf5hv0XwdeeRiijvX3A3yE="', 'x-custom-header-a': 'hello123', 'x-custom-header-b': 'world456'}
```

使用生成的标头，向 Route 发送请求：

```shell
curl -X GET "http://127.0.0.1:9080/get" \
     -H "Date: Fri, 06 Sep 2024 09:58:49 GMT" \
     -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date x-custom-header-a x-custom-header-b",signature="MwJR8JOhhRLIyaHlJ3Snbrf5hv0XwdeeRiijvX3A3yE="' \
     -H "x-custom-header-a: hello123" \
     -H "x-custom-header-b: world456"
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Signature keyId=\"john-key\",algorithm=\"hmac-sha256\",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"MwJR8JOhhRLIyaHlJ3Snbrf5hv0XwdeeRiijvX3A3yE=\"",
    "Date": "Fri, 06 Sep 2024 09:58:49 GMT",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66d98196-64a58db25ece71c077999ecd",
    "X-Consumer-Username": "john",
    "X-Credential-Identifier": "cred-john-hmac-auth",
    "X-Custom-Header-A": "hello123",
    "X-Custom-Header-B": "world456",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 103.97.2.206",
  "url": "http://127.0.0.1/get"
}
```

### 匿名 Consumer 的速率限制

以下示例演示了如何为常规 Consumer 和匿名 Consumer 配置不同的速率限制策略，其中匿名 Consumer 不需要进行身份验证，配额较少。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建常规 Consumer `john`，并配置 `limit-count` 插件，以允许 30 秒内的配额为 3：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429,
        "policy": "local"
      }
    }
  }'
```

为 Consumer `john` 创建 `hmac-auth` Credential：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-hmac-auth",
    "plugins": {
      "hmac-auth": {
        "key_id": "john-key",
        "secret_key": "john-secret-key"
      }
    }
  }'
```

创建匿名用户 `anonymous`，并配置 `limit-count` 插件，以允许 30 秒内配额为 1：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "anonymous",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "policy": "local"
      }
    }
  }'
```

创建 Route 并配置 `hmac-auth` 插件以接受匿名 Consumer `anonymous` 绕过身份验证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "hmac-auth-route",
    "uri": "/get",
    "methods": ["GET"],
    "plugins": {
      "hmac-auth": {
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

配置具有不同速率限制的 Consumer 以及接受匿名用户的 Route：

```yaml title="adc.yaml"
consumers:
  - username: john
    plugins:
      limit-count:
        count: 3
        time_window: 30
        rejected_code: 429
        policy: local
    credentials:
      - name: hmac-auth
        type: hmac-auth
        config:
          key_id: john-key
          secret_key: john-secret-key
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
      - name: hmac-auth-route
        uris:
          - /get
        methods:
          - GET
        plugins:
          hmac-auth:
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

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

配置具有不同速率限制的 Consumer 以及接受匿名用户的 Route：

```yaml title="hmac-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: john
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: hmac-auth
      name: primary-cred
      config:
        key_id: john-key
        secret_key: john-secret-key
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
  name: hmac-auth-plugin-config
spec:
  plugins:
    - name: hmac-auth
      config:
        anonymous_consumer: aic_anonymous  # namespace_consumername
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: hmac-auth-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
          method: GET
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: hmac-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f hmac-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

ApisixConsumer CRD 目前不支持在 Consumer 上配置插件，`authParameter` 中允许的认证插件除外。此示例无法通过 APISIX CRD 完成。

</TabItem>

</Tabs>

</TabItem>

</Tabs>

生成签名。您可以使用以下 Python 代码片段或其他技术栈：

```python title="hmac-sig-header-gen.py"
import hmac
import hashlib
import base64
from datetime import datetime, timezone

key_id = "john-key"                # key id
secret_key = b"john-secret-key"    # secret key
request_method = "GET"             # HTTP method
request_path = "/get"              # Route URI
algorithm= "hmac-sha256"           # can use other algorithms in allowed_algorithms

# get current datetime in GMT
# note: the signature will become invalid after the clock skew (default 300s)
# you can regenerate the signature after it becomes invalid, or increase the clock
# skew to prolong the validity within the advised security boundary
gmt_time = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')

# construct the signing string (ordered)
# the date and any subsequent custom headers should be lowercased and separated by a
# single space character, i.e. `<key>:<space><value>`
# https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12#section-2.1.6
signing_string = (
  f"{key_id}\n"
  f"{request_method} {request_path}\n"
  f"date: {gmt_time}\n"
)

# create signature
signature = hmac.new(secret_key, signing_string.encode('utf-8'), hashlib.sha256).digest()
signature_base64 = base64.b64encode(signature).decode('utf-8')

# construct the request headers
headers = {
  "Date": gmt_time,
  "Authorization": (
    f'Signature keyId="{key_id}",algorithm="{algorithm}",'
    f'headers="@request-target date",'
    f'signature="{signature_base64}"'
  )
}

# print headers
print(headers)
```

运行脚本：

```shell
python3 hmac-sig-header-gen.py
```

您应该看到打印的请求标头：

```text
{'Date': 'Mon, 21 Oct 2024 17:31:18 GMT', 'Authorization': 'Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="ztFfl9w7LmCrIuPjRC/DWSF4gN6Bt8dBBz4y+u1pzt8="'}
```

使用生成的标头发送五个连续的请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H "Date: Mon, 21 Oct 2024 17:31:18 GMT" -H 'Authorization: Signature keyId="john-key",algorithm="hmac-sha256",headers="@request-target date",signature="ztFfl9w7LmCrIuPjRC/DWSF4gN6Bt8dBBz4y+u1pzt8="' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

您应该看到以下响应，显示在 5 个请求中，3 个请求成功（状态代码 200），而其他请求被拒绝（状态代码 429）：

```text
200:    3, 429:    2
```

发送五个匿名请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

您应该看到以下响应，表明只有一个请求成功：

```text
200:    1, 429:    4
```
