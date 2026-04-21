---
title: consumer-restriction
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - consumer-restriction
description: consumer-restriction 插件基于消费者名称、路由 ID、服务 ID 或消费者组 ID 实现访问控制，增强 API 安全性。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/consumer-restriction" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`consumer-restriction` 插件基于消费者名称、路由 ID、服务 ID 或消费者组 ID 实现访问控制。

该插件需要与认证插件配合使用，例如 [`key-auth`](./key-auth.md) 和 [`jwt-auth`](./jwt-auth.md)，这意味着在使用场景中至少需要创建一个[消费者](../terminology/consumer.md)。详情请参见下方示例。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| type | string | 否 | consumer_name | consumer_name, service_id, route_id, consumer_group_id | 限制的依据。决定对白名单或黑名单检查哪个值。 |
| whitelist | array[string] | 否 | | | 允许访问的值列表。`whitelist`、`blacklist` 和 `allowed_by_methods` 中至少需要配置一个。 |
| blacklist | array[string] | 否 | | | 拒绝访问的值列表。`whitelist`、`blacklist` 和 `allowed_by_methods` 中至少需要配置一个。 |
| allowed_by_methods | array[object] | 否 | | | 指定每个消费者允许的 HTTP 方法的对象列表。`whitelist`、`blacklist` 和 `allowed_by_methods` 中至少需要配置一个。 |
| allowed_by_methods[].user | string | 否 | | | 消费者名称。 |
| allowed_by_methods[].methods | array[string] | 否 | | GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE, PURGE | 该消费者允许的 HTTP 方法列表。 |
| rejected_code | integer | 否 | 403 | >= 200 | 请求被拒绝时返回的 HTTP 状态码。 |
| rejected_msg | string | 否 | | | 请求被拒绝时返回给客户端的消息。 |

## 示例

以下示例演示了如何针对不同场景配置 `consumer-restriction` 插件。

示例中使用 [`key-auth`](./key-auth.md) 作为认证方式，你可以根据需要灵活调整为其他认证插件。

:::note

你可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
```

:::

### 通过消费者名称限制访问

以下示例演示如何在路由上使用 `consumer-restriction` 插件，按消费者名称限制消费者访问，消费者通过 [`key-auth`](./key-auth.md) 进行认证。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建消费者 `JohnDoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JohnDoe"
  }'
```

为该消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JohnDoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

创建第二个消费者 `JaneDoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JaneDoe"
  }'
```

为该消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JaneDoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jane-key"
      }
    }
  }'
```

创建启用 key 认证的路由，并配置 `consumer-restriction` 仅允许消费者 `JaneDoe` 访问：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "consumer-restricted-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "consumer-restriction": {
        "whitelist": ["JaneDoe"]
      }
    },
    "upstream" : {
      "nodes": {
        "httpbin.org":1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
consumers:
  - username: JohnDoe
    credentials:
      - name: cred-john-key-auth
        type: key-auth
        config:
          key: john-key
  - username: JaneDoe
    credentials:
      - name: cred-jane-key-auth
        type: key-auth
        config:
          key: jane-key
services:
  - name: consumer-restriction-service
    routes:
      - name: consumer-restricted-route
        uris:
          - /get
        plugins:
          key-auth: {}
          consumer-restriction:
            whitelist:
              - "JaneDoe"
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

通过 Ingress Controller 配置消费者时，消费者名称格式为 `namespace_consumername`。例如，`aic` 命名空间中名为 `janedoe` 的消费者，其名称变为 `aic_janedoe`。在 `consumer-restriction` 的 `whitelist` 或 `blacklist` 中请使用此格式。

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="consumer-restriction-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: john-key-auth
      config:
        key: john-key
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: janedoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: jane-key-auth
      config:
        key: jane-key
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
  name: consumer-restriction-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: consumer-restriction
      config:
        whitelist:
          - "aic_janedoe"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: consumer-restriction-route
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
            name: consumer-restriction-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="consumer-restriction-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: johndoe
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: john-key
---
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: janedoe
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jane-key
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
  name: consumer-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: consumer-restriction-route
      match:
        paths:
          - /get
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
      - name: consumer-restriction
        enable: true
        config:
          whitelist:
            - "aic_janedoe"
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f consumer-restriction-ic.yaml
```

</TabItem>

</Tabs>

以消费者 `JohnDoe` 的身份向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

你应收到 `HTTP/1.1 403 Forbidden` 响应，包含以下消息：

```text
{"message":"The consumer_name is forbidden."}
```

再以消费者 `JaneDoe` 的身份发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jane-key'
```

你应收到 `HTTP/1.1 200 OK` 响应，表示该消费者访问被允许。

### 通过消费者名称和 HTTP 方法限制访问

以下示例演示如何在路由上使用 `consumer-restriction` 插件，按消费者名称和 HTTP 方法限制消费者访问，消费者通过 [`key-auth`](./key-auth.md) 进行认证。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建消费者 `JohnDoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JohnDoe"
  }'
```

为该消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JohnDoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

创建第二个消费者 `JaneDoe`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JaneDoe"
  }'
```

为该消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JaneDoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jane-key"
      }
    }
  }'
```

创建启用 key 认证的路由，并使用 `consumer-restriction` 仅允许消费者使用所配置的 HTTP 方法：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "consumer-restricted-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {},
      "consumer-restriction": {
        "allowed_by_methods":[
          {
            "user": "JohnDoe",
            "methods": ["GET"]
          },
          {
            "user": "JaneDoe",
            "methods": ["POST"]
          }
        ]
      }
    },
    "upstream" : {
      "nodes": {
        "httpbin.org":1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
consumers:
  - username: JohnDoe
    credentials:
      - name: cred-john-key-auth
        type: key-auth
        config:
          key: john-key
  - username: JaneDoe
    credentials:
      - name: cred-jane-key-auth
        type: key-auth
        config:
          key: jane-key
services:
  - name: consumer-restriction-service
    routes:
      - name: consumer-restricted-route
        uris:
          - /anything
        plugins:
          key-auth: {}
          consumer-restriction:
            allowed_by_methods:
              - user: "JohnDoe"
                methods:
                  - "GET"
              - user: "JaneDoe"
                methods:
                  - "POST"
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

```yaml title="consumer-restriction-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: john-key-auth
      config:
        key: john-key
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: janedoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: jane-key-auth
      config:
        key: jane-key
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
  name: consumer-restriction-methods-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: consumer-restriction
      config:
        allowed_by_methods:
          - user: "aic_johndoe"
            methods:
              - "GET"
          - user: "aic_janedoe"
            methods:
              - "POST"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: consumer-restriction-route
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
            name: consumer-restriction-methods-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f consumer-restriction-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="consumer-restriction-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: johndoe
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: john-key
---
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: janedoe
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jane-key
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
  name: consumer-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: consumer-restriction-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
      - name: consumer-restriction
        enable: true
        config:
          allowed_by_methods:
            - user: "aic_johndoe"
              methods:
                - "GET"
            - user: "aic_janedoe"
              methods:
                - "POST"
```

将配置应用到集群：

```shell
kubectl apply -f consumer-restriction-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

以消费者 `JohnDoe` 的身份发送 POST 请求到路由：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST -H 'apikey: john-key'
```

你应收到 `HTTP/1.1 403 Forbidden` 响应，包含以下消息：

```text
{"message":"The consumer_name is forbidden."}
```

再以消费者 `JohnDoe` 的身份发送 GET 请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X GET -H 'apikey: john-key'
```

你应收到 `HTTP/1.1 200 OK` 响应，表示该消费者访问被允许。

你还可以以消费者 `JaneDoe` 的身份发送请求，验证配置是否与路由上 `consumer-restriction` 插件中的设置一致。

### 通过服务 ID 限制访问

以下示例演示如何使用 `consumer-restriction` 插件按服务 ID 限制消费者访问，消费者通过 [`key-auth`](./key-auth.md) 进行认证。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建两个示例服务：

```shell
curl "http://127.0.0.1:9180/apisix/admin/services" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "srv-1",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org":1
      }
    }
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/services" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "srv-2",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "mock.api7.ai":1
      }
    }
  }'
```

创建一个使用 `key-auth` 的消费者，并配置 `consumer-restriction` 仅允许访问 `srv-1` 服务：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JohnDoe",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      },
      "consumer-restriction": {
        "type": "service_id",
        "whitelist": ["srv-1"]
      }
    }
  }'
```

分别创建两条路由，各绑定到上面创建的一个服务：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "srv-1-route",
    "uri": "/anything",
    "service_id": "srv-1"
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "srv-2-route",
    "uri": "/srv-2",
    "service_id": "srv-2"
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
consumers:
  - username: JohnDoe
    plugins:
      key-auth:
        key: john-key
      consumer-restriction:
        type: service_id
        whitelist:
          - "srv-1"
services:
  - name: srv-1
    routes:
      - name: srv-1-route
        uris:
          - /anything
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
  - name: srv-2
    routes:
      - name: srv-2-route
        uris:
          - /srv-2
    upstream:
      type: roundrobin
      nodes:
        - host: mock.api7.ai
          port: 80
          weight: 1
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

通过 Ingress Controller 配置路由时，APISIX 服务 ID 会自动生成为 `{namespace}_{routeName}_{ruleIndex}` 的哈希值，无法预先确定。建议改用基于消费者名称的限制方式。

</TabItem>

</Tabs>

向 `srv-1` 服务中的路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: john-key'
```

你应收到 `HTTP/1.1 200 OK` 响应，表示该消费者访问被允许。

向 `srv-2` 服务中的路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/srv-2" -H 'apikey: john-key'
```

你应收到 `HTTP/1.1 403 Forbidden` 响应，包含以下消息：

```text
{"message":"The request is rejected, please check the service_id for this request"}
```
