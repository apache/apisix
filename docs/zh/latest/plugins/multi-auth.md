---
title: multi-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Multi Auth
  - multi-auth
description: multi-auth 插件支持使用不同认证方式的消费者共享同一路由或服务，简化 API 生命周期管理。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/multi-auth" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`multi-auth` 插件允许使用不同认证方式的消费者共享同一路由或服务。它支持配置多个认证插件，只要请求通过其中任意一种认证方式即可放行。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| auth_plugins | array | 是 | | | 至少包含两个认证插件的数组。 |

## 使用示例

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 在同一路由上允许不同的认证方式

以下示例演示如何让一个消费者使用 basic 认证，另一个消费者使用 key 认证，两者共享同一路由。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建两个 Consumer：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username":"consumer1"
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username":"consumer2"
  }'
```

为 `consumer1` 配置 basic 认证凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/consumer1/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "basic-auth": {
        "username":"consumer1",
        "password":"consumer1_pwd"
      }
    }
  }'
```

为 `consumer2` 配置 key 认证凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/consumer2/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "key-auth": {
        "key":"consumer2_pwd"
      }
    }
  }'
```

创建一个带有 `multi-auth` 的路由，并配置消费者使用的两个认证插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "multi-auth-route",
    "uri": "/anything",
    "plugins": {
      "multi-auth":{
        "auth_plugins":[
          {
            "basic-auth":{}
          },
          {
            "key-auth":{
              "hide_credentials":true,
              "header":"apikey",
              "query":"apikey"
            }
          }
        ]
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

创建两个带有各自凭证的消费者以及一个带有 `multi-auth` 的路由：

```yaml title="adc.yaml"
consumers:
  - username: consumer1
    credentials:
      - name: cred-consumer1-basic-auth
        type: basic-auth
        config:
          username: consumer1
          password: consumer1_pwd
  - username: consumer2
    credentials:
      - name: cred-consumer2-key-auth
        type: key-auth
        config:
          key: consumer2_pwd
services:
  - name: multi-auth-service
    routes:
      - name: multi-auth-route
        uris:
          - /anything
        plugins:
          multi-auth:
            auth_plugins:
              - basic-auth: {}
              - key-auth:
                  hide_credentials: true
                  header: apikey
                  query: apikey
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

```yaml title="multi-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: consumer1
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: basic-auth
      name: cred-consumer1-basic-auth
      config:
        username: consumer1
        password: consumer1_pwd
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: consumer2
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: cred-consumer2-key-auth
      config:
        key: consumer2_pwd
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
  name: multi-auth-plugin-config
spec:
  plugins:
    - name: multi-auth
      config:
        auth_plugins:
          - basic-auth: {}
          - key-auth:
              hide_credentials: true
              header: apikey
              query: apikey
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: multi-auth-route
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
            name: multi-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f multi-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="multi-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: consumer1
spec:
  ingressClassName: apisix
  authParameter:
    basicAuth:
      value:
        username: consumer1
        password: consumer1_pwd
---
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: consumer2
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: consumer2_pwd
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
  name: multi-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: multi-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: multi-auth
        enable: true
        config:
          auth_plugins:
            - basic-auth: {}
            - key-auth:
                hide_credentials: true
                header: apikey
                query: apikey
```

将配置应用到集群：

```shell
kubectl apply -f multi-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向路由发送带有 `consumer1` basic 认证凭据的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -u consumer1:consumer1_pwd
```

你应该收到 `HTTP/1.1 200 OK` 响应。

向路由发送带有 `consumer2` key 认证凭证的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: consumer2_pwd'
```

你同样应该收到 `HTTP/1.1 200 OK` 响应。

向路由发送不带任何凭证的请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

你应该收到 `HTTP/1.1 401 Unauthorized` 响应。

以上验证了使用不同认证方式的消费者能够通过认证并访问同一路由后端的资源。
