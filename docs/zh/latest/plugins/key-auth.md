---
title: key-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Key Auth
  - key-auth
description: key-auth 插件支持使用身份验证密钥作为客户端在访问上游资源之前进行身份验证的机制。
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
    <link rel="canonical" href="https://docs.api7.ai/hub/key-auth" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`key-auth` 插件支持使用身份验证密钥作为客户端在访问上游资源之前进行身份验证的机制。

要使用该插件，您需要在[消费者](../terminology/consumer.md)上配置身份验证密钥，并在路由或服务上启用该插件。密钥可以包含在请求 URL 查询字符串或请求标头中。APISIX 将验证密钥以确定是否应允许或拒绝请求访问上游资源。

当消费者成功通过身份验证后，APISIX 会在将请求代理到上游服务之前向请求添加其他标头，例如 `X-Consumer-Username`、`X-Credential-Identifier` 和其他消费者自定义标头（如果已配置）。上游服务将能够区分消费者并根据需要实现其他逻辑。如果这些值中的任何一个不可用，则不会添加相应的标头。

## 属性

Consumer/Credential 端：

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| key | string | 是 | | | 标识消费者凭证的唯一密钥。密钥在存储到 etcd 之前会使用 AES 加密。您也可以将其存储在环境变量中并使用 `env://` 前缀引用，或存储在 HashiCorp Vault 等密钥管理器中并使用 `secret://` 前缀引用。 |

Route 端：

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| header | string | 否 | apikey | | 获取密钥的请求标头名称。 |
| query | string | 否 | apikey | | 获取密钥的查询字符串参数名称，优先级低于 `header`。 |
| hide_credentials | boolean | 否 | false | | 若为 `true`，则不将含有认证信息的标头或查询字符串传递给上游服务。 |
| anonymous_consumer | string | 否 | | | 匿名消费者名称。如果已配置，则允许匿名用户绕过身份验证。 |
| realm | string | 否 | key | | 在身份验证失败时，`401 Unauthorized` 响应中 [`WWW-Authenticate`](https://datatracker.ietf.org/doc/html/rfc7235#section-4.1) 标头的域值。该参数在 Apache APISIX 3.15.0 及以上版本中可用。 |

## 示例

以下示例演示了如何在不同场景中使用 `key-auth` 插件。

:::note

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 在路由上实现密钥认证

以下示例演示如何在路由上实现密钥认证并将密钥包含在请求标头中。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建一个消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

使用 `key-auth` 创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {}
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

创建带有 `key-auth` 凭证的消费者以及配置了 `key-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jack-key
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth: {}
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

创建带有 `key-auth` 凭证的消费者以及配置了 `key-auth` 插件的路由：

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-cred
      config:
        key: jack-key
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
  name: key-auth-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: key-auth-route
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
            name: key-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: jack
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jack-key
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
  name: key-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: key-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
```

将配置应用到集群：

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

#### 使用有效密钥进行验证

使用有效密钥发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: jack-key'
```

您应该收到 `HTTP/1.1 200 OK` 响应。

#### 使用无效密钥进行验证

使用无效密钥发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: wrong-key'
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Invalid API key in request"}
```

#### 无需密钥即可验证

无需密钥即可发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Missing API key found in request"}
```

### 隐藏上游的身份验证信息

以下示例首先演示默认行为（身份验证密钥被转发到上游服务），然后展示如何通过配置 `hide_credentials` 来防止密钥被发送。将身份验证密钥转发到上游服务在某些情况下可能会导致安全风险。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建一个消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

#### 不隐藏凭据

使用 `key-auth` 创建路由，并将 `hide_credentials` 配置为 `false`（默认配置）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "key-auth-route",
  "uri": "/anything",
  "plugins": {
    "key-auth": {
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

创建带有 `key-auth` 凭证的消费者以及配置了 `key-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jack-key
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth:
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

创建带有 `key-auth` 凭证的消费者以及配置了 `key-auth` 插件的路由：

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-cred
      config:
        key: jack-key
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
  name: key-auth-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
        hide_credentials: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: key-auth-route
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
            name: key-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: jack
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jack-key
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
  name: key-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: key-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
        config:
          hide_credentials: false
```

将配置应用到集群：

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

发送带有有效密钥的请求：

```shell
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
```

您应该看到以下 `HTTP/1.1 200 OK` 响应：

```json
{
  "args": {
    "apikey": "jack-key"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Amzn-Trace-Id": "Root=1-6502d8a5-2194962a67aa21dd33f94bb2",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 103.248.35.179",
  "url": "http://127.0.0.1/anything?apikey=jack-key"
}
```

注意凭证 `jack-key` 对于上游服务是可见的。

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
curl "http://127.0.0.1:9180/apisix/admin/routes/key-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "key-auth": {
      "hide_credentials": true
    }
  }
}'
```

</TabItem>

<TabItem value="adc">

更新路由配置：

```yaml title="adc.yaml"
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth:
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

```yaml title="key-auth-ic.yaml"
# 其他配置
# ---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: key-auth-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
        hide_credentials: true
```

将配置应用到集群：

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

更新 ApisixRoute，将 `hide_credentials` 设置为 `true`：

```yaml title="key-auth-ic.yaml"
# 其他配置
# ---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: key-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: key-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
        config:
          hide_credentials: true
```

将配置应用到集群：

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

发送带有有效密钥的请求：

```shell
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
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
    "User-Agent": "curl/8.2.1",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Amzn-Trace-Id": "Root=1-6502d85c-16f34dbb5629a5960183e803",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 103.248.35.179",
  "url": "http://127.0.0.1/anything"
}
```

注意凭证 `jack-key` 对上游服务不再可见。

### 演示标头和查询中的密钥优先级

以下示例演示了如何在路由上实现消费者的密钥身份验证，并自定义应包含密钥的 URL 参数。该示例还显示，当在标头和查询字符串中都配置了 API 密钥时，请求标头具有更高的优先级。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建消费者 `jack`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

使用 `key-auth` 创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "key-auth-route",
  "uri": "/anything",
  "plugins": {
    "key-auth": {
      "query": "auth"
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

创建带有 `key-auth` 凭证的消费者以及配置了 `key-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jack-key
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth:
            query: auth
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

创建带有 `key-auth` 凭证的消费者以及配置了 `key-auth` 插件的路由：

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-cred
      config:
        key: jack-key
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
  name: key-auth-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
        query: auth
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: key-auth-route
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
            name: key-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: jack
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jack-key
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
  name: key-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: key-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
        config:
          query: auth
```

将配置应用到集群：

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

#### 使用有效密钥进行验证

使用有效密钥发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything?auth=jack-key"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

#### 使用无效密钥进行验证

使用无效密钥发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything?auth=wrong-key"
```

您应该看到以下 `HTTP/1.1 401 Unauthorized` 响应：

```text
{"message":"Invalid API key in request"}
```

#### 使用查询字符串中的有效密钥进行验证

但是，如果您在标头中包含有效密钥，而 URL 查询字符串中仍包含无效密钥：

```shell
curl -i "http://127.0.0.1:9080/anything?auth=wrong-key" -H 'apikey: jack-key'
```

您应该会看到 `HTTP/1.1 200 OK` 响应。这表明标头中包含的密钥始终具有更高的优先级。

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

创建一个带有自定义 ID 标签的消费者 `jack`：

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

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

使用 `key-auth` 创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {}
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

创建带有 `key-auth` 凭证的消费者以及启用 `key-auth` 插件的路由：

```yaml title="adc.yaml"
consumers:
  - username: jack
    labels:
      custom_id: "495aec6a"
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jack-key
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth: {}
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

为了验证，请使用有效密钥向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
```

您应该看到一个带有 `X-Consumer-Custom-Id` 的 `HTTP/1.1 200 OK` 响应，类似于以下内容：

```json
{
  "args": {
    "apikey": "jack-key"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea8d64-33df89052ae198a706e18c2a",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything?apikey=jack-key"
}
```

### 匿名消费者的速率限制

以下示例演示了如何为常规消费者和匿名消费者配置不同的速率限制策略，其中匿名消费者不需要进行身份验证，并且配额较少。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建常规消费者 `jack` 并配置 `limit-count` 插件以允许 30 秒内的配额为 3：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
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

为消费者 `jack` 创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
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

创建路由并配置 `key-auth` 插件以接受匿名消费者 `anonymous` 绕过身份验证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {
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
  - username: jack
    plugins:
      limit-count:
        count: 3
        time_window: 30
        rejected_code: 429
        policy: local
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jack-key
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
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth:
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

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-key
      config:
        key: jack-key
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
  name: key-auth-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        anonymous_consumer: aic_anonymous  # namespace_consumername
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: key-auth-route
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
            name: key-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

ApisixConsumer CRD 目前不支持在消费者上配置插件（`authParameter` 中允许的身份验证插件除外）。此示例无法通过 APISIX CRD 完成。

</TabItem>

</Tabs>

</TabItem>

</Tabs>

为了验证，请使用 `jack` 的密钥发送五个连续的请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jack-key' -o /dev/null -s -w "%{http_code}\n") && \
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
