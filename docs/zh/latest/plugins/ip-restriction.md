---
title: ip-restriction
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - IP restriction
  - ip-restriction
description: ip-restriction 插件支持通过配置 IP 地址白名单或黑名单来限制 IP 地址对上游资源的访问。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ip-restriction" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`ip-restriction` 插件支持通过配置 IP 地址白名单或黑名单来限制 IP 地址对上游资源的访问。限制 IP 对资源的访问有助于防止未经授权的访问并加强 API 安全性。

## 属性

| 名称          | 类型          | 必选项 | 默认值                           | 有效值    | 描述                                                                     |
|---------------|---------------|--------|----------------------------------|-----------|--------------------------------------------------------------------------|
| whitelist     | array[string] | 否     |                                  |           | 允许访问的 IP 或 CIDR 范围列表。`whitelist` 和 `blacklist` 必须且只能配置其中一个。 |
| blacklist     | array[string] | 否     |                                  |           | 拒绝访问的 IP 或 CIDR 范围列表。`whitelist` 和 `blacklist` 必须且只能配置其中一个。 |
| message       | string        | 否     | "Your IP address is not allowed" | [1, 1024] | IP 被拒绝时返回给客户端的消息。                                           |
| response_code | integer       | 否     | 403                              | [403, 404] | 因 IP 地址限制而拒绝请求时返回的 HTTP 响应码。                            |

## 示例

以下示例演示了如何针对不同场景配置 `ip-restriction` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 通过白名单限制访问

以下示例演示了如何将有权访问上游资源的 IP 地址列表列入白名单，并自定义拒绝访问的错误消息。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

使用 `ip-restriction` 插件创建路由，将一系列 IP 列入白名单，并自定义拒绝访问时的错误消息：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ip-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ip-restriction": {
        "whitelist": [
          "192.168.0.1/24"
        ],
        "message": "Access denied"
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

```yaml title="adc.yaml"
services:
  - name: ip-restriction-service
    routes:
      - name: ip-restriction-route
        uris:
          - /anything
        plugins:
          ip-restriction:
            whitelist:
              - "192.168.0.1/24"
            message: "Access denied"
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
{label: 'APISIX Ingress Controller', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-plugin-config
spec:
  plugins:
    - name: ip-restriction
      config:
        whitelist:
          - "192.168.0.1/24"
        message: "Access denied"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ip-restriction-route
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
            name: ip-restriction-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: ip-restriction-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: ip-restriction
        enable: true
        config:
          whitelist:
            - "192.168.0.1/24"
          message: "Access denied"
```

将配置应用到集群：

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

如果您的 IP 被允许，您应该会收到 `HTTP/1.1 200 OK` 响应。如果不允许，您应该会收到 `HTTP/1.1 403 Forbidden` 响应，并显示以下错误消息：

```text
{"message":"Access denied"}
```

### 使用修改后的 IP 限制访问

以下示例演示了如何使用 `real-ip` 插件修改用于 IP 限制的 IP。如果 APISIX 位于反向代理之后，并且 APISIX 无法获得真实客户端 IP，则此功能特别有用。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

使用 `ip-restriction` 插件创建路由，将特定 IP 地址列入白名单，并从 URL 参数 `realip` 获取客户端 IP 地址：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ip-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ip-restriction": {
        "whitelist": [
          "192.168.1.241"
        ]
      },
      "real-ip": {
        "source": "arg_realip"
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

```yaml title="adc.yaml"
services:
  - name: ip-restriction-service
    routes:
      - name: ip-restriction-route
        uris:
          - /anything
        plugins:
          ip-restriction:
            whitelist:
              - "192.168.1.241"
          real-ip:
            source: arg_realip
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
{label: 'APISIX Ingress Controller', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-realip-plugin-config
spec:
  plugins:
    - name: ip-restriction
      config:
        whitelist:
          - "192.168.1.241"
    - name: real-ip
      config:
        source: arg_realip
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ip-restriction-route
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
            name: ip-restriction-realip-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: ip-restriction-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: ip-restriction
        enable: true
        config:
          whitelist:
            - "192.168.1.241"
      - name: real-ip
        enable: true
        config:
          source: arg_realip
```

将配置应用到集群：

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything?realip=192.168.1.241"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

使用不同的 IP 地址发送另一个请求：

```shell
curl -i "http://127.0.0.1:9080/anything?realip=192.168.10.24"
```

您应该会收到 `HTTP/1.1 403 Forbidden` 响应。
