---
title: traffic-label
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - traffic-label
  - 流量染色
  - 灰度发布
description: traffic-label 插件根据可配置的匹配规则和权重分发设置请求头，实现流量染色与灰度发布。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/traffic-label" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`traffic-label` 插件根据可配置的匹配规则为请求设置头部信息。与 [workflow](./workflow.md) 插件类似，该插件按顺序对规则进行求值，并对第一个匹配的规则执行动作。两者的关键区别在于：`traffic-label` 支持在每条规则的动作列表中设置**权重分发**，从而实现按比例的流量染色，适用于灰度发布和 A/B 测试场景。

每条规则由以下两部分组成：

- **`match`** — 使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 定义的可选匹配条件。省略时该规则匹配所有请求。
- **`actions`** — 规则命中时要执行的动作数组。每个动作可设置请求头，并带有可选的权重。流量按权重使用加权轮询算法分发到各动作。

规则按数组顺序逐条求值，命中第一条后停止。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| rules | array[object] | 是 | | | 匹配规则列表，按数组顺序求值，第一个命中的规则生效。 |
| rules[].match | array | 否 | `[]` | | 使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 语法定义的匹配条件。每个元素为表达式数组 `[变量, 运算符, 值]`，或字符串 `"OR"` / `"AND"` 用于控制逻辑分组。省略时匹配所有请求。 |
| rules[].actions | array[object] | 是 | | | 规则命中时要执行的动作数组。流量按各动作的 `weight` 进行分发。 |
| rules[].actions[].set_headers | object | 否 | | | 要设置的请求头。已存在同名头部时覆盖，不存在时新增。值支持 NGINX 变量，如 `$remote_addr`。格式：`{"头部名称": "值"}`。 |
| rules[].actions[].weight | integer | 否 | 1 | ≥ 1 | 该动作的相对权重。流量占比 = 该动作权重 / 规则中所有动作权重之和。仅设置 `weight` 而不配置其他动作，表示该比例的流量不做任何修改直接通过。 |

:::note

- 规则按顺序求值，仅执行第一个命中的规则，后续规则不再匹配。
- 目前 `set_headers` 是唯一支持的动作类型。

:::

## 示例

以下示例演示了如何在不同场景中使用 `traffic-label` 插件。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 按请求条件为流量打标签

以下示例演示如何根据 `?version` 查询参数，将请求头 `X-Server-Id` 设置为不同的值。

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
    "id": "traffic-label-route",
    "uri": "/anything",
    "plugins": {
      "traffic-label": {
        "rules": [
          {
            "match": [["arg_version", "==", "v1"]],
            "actions": [{"set_headers": {"X-Server-Id": "100"}}]
          },
          {
            "match": [["arg_version", "==", "v2"]],
            "actions": [{"set_headers": {"X-Server-Id": "200"}}]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {"httpbin.org:80": 1}
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: traffic-label-route
        uris:
          - /anything
        plugins:
          traffic-label:
            rules:
              - match:
                  - ["arg_version", "==", "v1"]
                actions:
                  - set_headers:
                      X-Server-Id: "100"
              - match:
                  - ["arg_version", "==", "v2"]
                actions:
                  - set_headers:
                      X-Server-Id: "200"
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

```yaml title="traffic-label-ic.yaml"
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
  name: traffic-label-plugin-config
spec:
  plugins:
    - name: traffic-label
      config:
        rules:
          - match:
              - ["arg_version", "==", "v1"]
            actions:
              - set_headers:
                  X-Server-Id: "100"
          - match:
              - ["arg_version", "==", "v2"]
            actions:
              - set_headers:
                  X-Server-Id: "200"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: traffic-label-route
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
            name: traffic-label-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="traffic-label-ic.yaml"
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
  name: traffic-label-route
spec:
  ingressClassName: apisix
  http:
    - name: traffic-label-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: traffic-label
        enable: true
        config:
          rules:
            - match:
                - ["arg_version", "==", "v1"]
              actions:
                - set_headers:
                    X-Server-Id: "100"
            - match:
                - ["arg_version", "==", "v2"]
              actions:
                - set_headers:
                    X-Server-Id: "200"
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f traffic-label-ic.yaml
```

</TabItem>

</Tabs>

发送带 `?version=v1` 的请求：

```shell
curl "http://127.0.0.1:9080/anything?version=v1"
```

上游服务将收到 `X-Server-Id: 100`。发送 `?version=v2` 的请求时，上游服务将收到 `X-Server-Id: 200`。不带 `version` 参数的请求不命中任何规则，将直接透传。

### 按权重将流量分发到不同动作

以下示例演示使用 `traffic-label` 进行加权分发。当请求命中规则时，流量按动作的 `weight` 按比例分配：

- 30% 的请求：设置 `X-Server-Id: 100`
- 20% 的请求：设置 `X-API-Version: v2`
- 50% 的请求：直接通过，不做任何修改

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
    "id": "traffic-label-route",
    "uri": "/anything",
    "plugins": {
      "traffic-label": {
        "rules": [
          {
            "match": [["uri", "==", "/anything"]],
            "actions": [
              {
                "set_headers": {"X-Server-Id": "100"},
                "weight": 3
              },
              {
                "set_headers": {"X-API-Version": "v2"},
                "weight": 2
              },
              {
                "weight": 5
              }
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {"httpbin.org:80": 1}
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: traffic-label-route
        uris:
          - /anything
        plugins:
          traffic-label:
            rules:
              - match:
                  - ["uri", "==", "/anything"]
                actions:
                  - set_headers:
                      X-Server-Id: "100"
                    weight: 3
                  - set_headers:
                      X-API-Version: v2
                    weight: 2
                  - weight: 5
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

```yaml title="traffic-label-ic.yaml"
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
  name: traffic-label-plugin-config
spec:
  plugins:
    - name: traffic-label
      config:
        rules:
          - match:
              - ["uri", "==", "/anything"]
            actions:
              - set_headers:
                  X-Server-Id: "100"
                weight: 3
              - set_headers:
                  X-API-Version: v2
                weight: 2
              - weight: 5
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: traffic-label-route
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
            name: traffic-label-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="traffic-label-ic.yaml"
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
  name: traffic-label-route
spec:
  ingressClassName: apisix
  http:
    - name: traffic-label-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: traffic-label
        enable: true
        config:
          rules:
            - match:
                - ["uri", "==", "/anything"]
              actions:
                - set_headers:
                    X-Server-Id: "100"
                  weight: 3
                - set_headers:
                    X-API-Version: v2
                  weight: 2
                - weight: 5
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f traffic-label-ic.yaml
```

</TabItem>

</Tabs>

权重总和为 `3 + 2 + 5 = 10`。每 10 个请求中，约有 3 个将带有 `X-Server-Id: 100`，2 个将带有 `X-API-Version: v2`，5 个将不带任何新增请求头直接通过。
