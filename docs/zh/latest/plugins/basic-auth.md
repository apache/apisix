---
title: basic-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Basic Auth
  - basic-auth
description: basic-auth 插件为消费者添加了基本访问身份验证，以便消费者在访问上游资源之前进行身份验证。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/basic-auth" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`basic-auth` 插件为[消费者](../terminology/consumer.md)添加了[基本访问身份验证](https://en.wikipedia.org/wiki/Basic_access_authentication)，以便消费者在访问上游资源之前进行身份验证。

当消费者成功通过身份验证后，APISIX 会在将请求代理到上游服务之前向请求添加其他标头，例如 `X-Consumer-Username`、`X-Credential-Identifier` 和其他消费者自定义标头（如果已配置）。上游服务将能够区分消费者并根据需要实现其他逻辑。如果这些值中的任何一个不可用，则不会添加相应的标头。

## 属性

Consumer/Credentials 端：

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| username | string | 是 | | | 消费者的唯一基本认证用户名。 |
| password | string | 是 | | | 消费者的基本认证密码。密码在存储到 etcd 之前会使用 AES 加密。您也可以将其存储在环境变量中并使用 `env://` 前缀引用，或存储在 HashiCorp Vault 等密钥管理器中并使用 `secret://` 前缀引用。 |

Route 端：

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| hide_credentials | boolean | 否 | false | | 若为 `true`，则不将 Authorization 请求标头传递给上游服务。 |
| anonymous_consumer | string | 否 | | | 匿名消费者名称。如果已配置，则允许匿名用户绕过身份验证。 |
| realm | string | 否 | basic | | 在身份验证失败时，`401 Unauthorized` 响应中 [`WWW-Authenticate`](https://datatracker.ietf.org/doc/html/rfc7235#section-4.1) 标头的域值。该参数在 Apache APISIX 3.15.0 及以上版本中可用。 |

## 示例

以下示例演示了如何在不同场景中使用 `basic-auth` 插件。

:::note

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 在路由上实现基本身份验证

以下示例演示如何在路由上实现基本身份验证。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建消费者 `johndoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe"
  }'
```

为消费者创建 `basic-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

创建一个带有 `basic-auth` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {}
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

创建带有 `basic-auth` 凭证的消费者以及配置了 `basic-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: johndoe
    credentials:
      - name: basic-auth
        type: basic-auth
        config:
          username: johndoe
          password: john-key
services:
  - name: basic-auth-service
    routes:
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth: {}
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

创建带有 `basic-auth` 凭证的消费者以及配置了 `basic-auth` 插件的路由：

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: basic-auth
      name: primary-cred
      config:
        username: johndoe
        password: john-key
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
  name: basic-auth-plugin-config
spec:
  plugins:
    - name: basic-auth
      config:
        _meta:
          disable: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: basic-auth-route
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
            name: basic-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: johndoe
spec:
  ingressClassName: apisix
  authParameter:
    basicAuth:
      value:
        username: johndoe
        password: john-key
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
  name: basic-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: basic-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: basic-auth
        enable: true
```

将配置应用到集群：

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

#### 使用有效凭证进行验证

使用有效凭证发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

您应该会看到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66e5107c-5bb3e24f2de5baf733aec1cc",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything"
}
```

#### 使用无效凭证进行验证

使用无效凭证发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:invalid-password
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Invalid user authorization"}
```

#### 不使用凭证进行验证

发送不携带凭证的请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Missing authorization in request"}
```

### 隐藏上游的身份验证信息

以下示例演示了如何通过配置 `hide_credentials` 来防止客户端凭证（`Authorization` 标头）被发送到上游服务。APISIX 默认情况下会将包含客户端凭证的 `Authorization` 标头转发到上游服务，这在某些情况下可能会导致安全风险，您应该考虑按本示例更新 `hide_credentials`。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建消费者 `johndoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe"
  }'
```

为消费者创建 `basic-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

#### 不隐藏凭据

使用 `basic-auth` 创建路由，并将 `hide_credentials` 配置为 `false`（默认配置）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "basic-auth-route",
  "uri": "/anything",
  "plugins": {
    "basic-auth": {
      "hide_credentials": false
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

创建带有 `basic-auth` 凭证的消费者以及配置了 `basic-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: johndoe
    credentials:
      - name: basic-auth
        type: basic-auth
        config:
          username: johndoe
          password: john-key
services:
  - name: basic-auth-service
    routes:
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth:
            hide_credentials: false
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

创建带有 `basic-auth` 凭证的消费者以及配置了 `basic-auth` 插件的路由：

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: basic-auth
      name: primary-cred
      config:
        username: johndoe
        password: john-key
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
  name: basic-auth-plugin-config
spec:
  plugins:
    - name: basic-auth
      config:
        _meta:
          disable: false
        hide_credentials: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: basic-auth-route
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
            name: basic-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: johndoe
spec:
  ingressClassName: apisix
  authParameter:
    basicAuth:
      value:
        username: johndoe
        password: john-key
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
  name: basic-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: basic-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: basic-auth
        enable: true
        config:
          hide_credentials: false
```

将配置应用到集群：

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

发送带有有效凭证的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

您应该看到以下 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66cc2195-22bd5f401b13480e63c498c6",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 43.228.226.23",
  "url": "http://127.0.0.1/anything"
}
```

请注意，凭证以 base64 编码格式对上游服务可见。您也可以使用 `Authorization` 标头在请求中传递 base64 编码的凭据：

```shell
curl -i "http://127.0.0.1:9080/anything" -H "Authorization: Basic am9obmRvZTpqb2huLWtleQ=="
```

#### 隐藏凭据

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

将插件的 `hide_credentials` 更新为 `true`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/basic-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "basic-auth": {
      "hide_credentials": true
    }
  }
}'
```

</TabItem>

<TabItem value="adc">

更新路由配置：

```yaml title="adc.yaml"
# 其他配置
# ...
services:
  - name: basic-auth-service
    routes:
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth:
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
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

更新 PluginConfig，将 `hide_credentials` 设置为 `true`：

```yaml title="basic-auth-ic.yaml"
# 其他配置
# ---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: basic-auth-plugin-config
spec:
  plugins:
    - name: basic-auth
      config:
        _meta:
          disable: false
        hide_credentials: true
```

将配置应用到集群：

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

更新 ApisixRoute，将 `hide_credentials` 设置为 `true`：

```yaml title="basic-auth-ic.yaml"
# 其他配置
# ---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: basic-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: basic-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: basic-auth
        enable: true
        config:
          hide_credentials: true
```

将配置应用到集群：

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

发送带有有效凭证的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

您应该看到以下 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66cc21a7-4f6ac87946e25f325167d53a",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 43.228.226.23",
  "url": "http://127.0.0.1/anything"
}
```

请注意，上游服务不再可见这些凭据。

### 将消费者自定义 ID 添加到标头

以下示例演示了如何在 `Consumer-Custom-Id` 标头中将消费者自定义 ID 附加到经过身份验证的请求，该 ID 可用于根据需要实现其他逻辑。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建带有自定义 ID 标签的消费者 `johndoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

为消费者创建 `basic-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

创建一个带有 `basic-auth` 的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {}
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

创建带有 `basic-auth` 凭证的消费者以及启用 `basic-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: johndoe
    labels:
      custom_id: "495aec6a"
    credentials:
      - name: basic-auth
        type: basic-auth
        config:
          username: johndoe
          password: john-key
services:
  - name: basic-auth-service
    routes:
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth: {}
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

通过 Ingress Controller 配置资源时，目前不支持消费者自定义标签，请求中不会包含 `X-Consumer-Custom-Id` 标头。暂时无法通过 Ingress Controller 完成此示例。

</TabItem>

</Tabs>

使用有效凭证向路由发送请求进行验证：

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

您应该看到一个带有 `X-Consumer-Custom-Id` 的 `HTTP/1.1 200 OK` 响应，类似于以下内容：

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea8d64-33df89052ae198a706e18c2a",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything"
}
```

### 匿名消费者的速率限制

以下示例演示了如何为普通消费者和匿名消费者配置不同的速率限制策略，其中匿名消费者不需要进行身份验证，并且配额较少。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建普通消费者 `johndoe` 并配置 `limit-count` 插件以允许 30 秒内的配额为 3：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
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

为消费者 `johndoe` 创建 `basic-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
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

创建一个路由并配置 `basic-auth` 插件来接受匿名消费者 `anonymous` 绕过身份验证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {
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

配置具有不同速率限制的消费者以及接受匿名用户的路由：

```yaml title="adc.yaml"
consumers:
  - username: johndoe
    plugins:
      limit-count:
        count: 3
        time_window: 30
        rejected_code: 429
        policy: local
    credentials:
      - name: basic-auth
        type: basic-auth
        config:
          username: johndoe
          password: john-key
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
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth:
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
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

配置具有不同速率限制的消费者以及接受匿名用户的路由：

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: basic-auth
      name: primary-key
      config:
        username: johndoe
        password: john-key
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
  name: basic-auth-plugin-config
spec:
  plugins:
    - name: basic-auth
      config:
        anonymous_consumer: aic_anonymous  # namespace_consumername
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: basic-auth-route
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
            name: basic-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

ApisixConsumer CRD 目前不支持在消费者上配置插件（`authParameter` 中允许的身份验证插件除外）。此示例无法通过 APISIX CRD 完成。

</TabItem>

</Tabs>

</TabItem>

</Tabs>

为了验证，请使用 `johndoe` 的凭证发送五个连续的请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -u johndoe:john-key -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

您应该看到以下响应，显示在 5 个请求中，3 个请求成功（状态代码 200），而其他请求被拒绝（状态代码 429）。

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
