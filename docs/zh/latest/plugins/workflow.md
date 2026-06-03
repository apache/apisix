---
title: workflow
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - workflow
  - 流量控制
description: workflow 插件支持根据给定的一组规则有条件地执行对客户端流量的用户定义操作。这提供了一种实现复杂流量管理的细粒度方法。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/workflow" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`workflow` 插件支持根据给定的规则集有条件地执行对客户端流量的用户定义操作，这些规则集使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) 定义。这为流量管理提供了一种细粒度的方法。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| rules | array[object] | 是 | | | 一对或多对匹配条件和要执行的操作组成的数组。 |
| rules.case | array[array] | 否 | | | 一个或多个匹配条件的数组，形式为 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)，例如 `{"arg_name", "==", "json"}`。 |
| rules.actions | array[array] | 是 | | | 条件匹配成功后要执行的操作的数组。目前数组只支持一个操作，必须是 `return`、`limit-count` 或 `limit-conn`。当操作配置为 `return` 时，可以配置条件匹配成功时返回给客户端的 HTTP 状态码。当操作配置为 `limit-count` 时，可以配置 [`limit-count`](./limit-count.md) 插件除 `group` 之外的所有选项。当操作配置为 `limit-conn` 时，可以配置 [`limit-conn`](./limit-conn.md) 插件的所有选项。 |

## 示例

以下示例演示了如何在不同场景中使用 `workflow` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 有条件地返回响应 HTTP 状态码

以下示例演示了一个简单的规则，其中包含一个匹配条件和一个关联操作，用于有条件地返回 HTTP 状态码。

使用 `workflow` 插件创建路由：

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
    "id": "workflow-route",
    "uri": "/anything/*",
    "plugins": {
      "workflow":{
        "rules":[
          {
            "case":[
              ["uri", "==", "/anything/rejected"]
            ],
            "actions":[
              [
                "return",
                {"code": 403}
              ]
            ]
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

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - uris:
          - /anything/*
        name: workflow-route
        plugins:
          workflow:
            rules:
              - case:
                  - ["uri", "==", "/anything/rejected"]
                actions:
                  - - return
                    - code: 403
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

```yaml title="workflow-ic.yaml"
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
  name: workflow-plugin-config
spec:
  plugins:
    - name: workflow
      config:
        rules:
          - case:
              - ["uri", "==", "/anything/rejected"]
            actions:
              - - return
                - code: 403
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: workflow-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything/
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: workflow-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="workflow-ic.yaml"
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
  name: workflow-route
spec:
  ingressClassName: apisix
  http:
    - name: workflow-route
      match:
        paths:
          - /anything/*
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: workflow
        enable: true
        config:
          rules:
            - case:
                - ["uri", "==", "/anything/rejected"]
              actions:
                - - return
                  - code: 403
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f workflow-ic.yaml
```

</TabItem>

</Tabs>

发送与任何规则都不匹配的请求：

```shell
curl -i "http://127.0.0.1:9080/anything/anything"
```

您应该收到 `HTTP/1.1 200 OK` 响应。

发送与配置的规则匹配的请求：

```shell
curl -i "http://127.0.0.1:9080/anything/rejected"
```

您应该收到以下 `HTTP/1.1 403 Forbidden` 响应：

```text
{"error_msg":"rejected by workflow"}
```

### 通过 URI 和查询参数有条件地应用速率限制

以下示例演示了一条具有两个匹配条件和一个关联操作的规则，用于有条件地限制请求速率。

使用 `workflow` 插件创建路由：

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
    "id": "workflow-route",
    "uri": "/anything/*",
    "plugins":{
      "workflow":{
        "rules":[
          {
            "case":[
              ["uri", "==", "/anything/rate-limit"],
              ["arg_env", "==", "v1"]
            ],
            "actions":[
              [
                "limit-count",
                {
                  "count":1,
                  "time_window":60,
                  "rejected_code":429
                }
              ]
            ]
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

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - uris:
          - /anything/*
        name: workflow-route
        plugins:
          workflow:
            rules:
              - case:
                  - ["uri", "==", "/anything/rate-limit"]
                  - ["arg_env", "==", "v1"]
                actions:
                  - - limit-count
                    - count: 1
                      time_window: 60
                      rejected_code: 429
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

```yaml title="workflow-ic.yaml"
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
  name: workflow-plugin-config
spec:
  plugins:
    - name: workflow
      config:
        rules:
          - case:
              - ["uri", "==", "/anything/rate-limit"]
              - ["arg_env", "==", "v1"]
            actions:
              - - limit-count
                - count: 1
                  time_window: 60
                  rejected_code: 429
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: workflow-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything/
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: workflow-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="workflow-ic.yaml"
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
  name: workflow-route
spec:
  ingressClassName: apisix
  http:
    - name: workflow-route
      match:
        paths:
          - /anything/*
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: workflow
        enable: true
        config:
          rules:
            - case:
                - ["uri", "==", "/anything/rate-limit"]
                - ["arg_env", "==", "v1"]
              actions:
                - - limit-count
                  - count: 1
                    time_window: 60
                    rejected_code: 429
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f workflow-ic.yaml
```

</TabItem>

</Tabs>

生成两个符合规则的连续请求：

```shell
curl -i "http://127.0.0.1:9080/anything/rate-limit?env=v1"
```

您应该收到 `HTTP/1.1 200 OK` 响应和 `HTTP 429 Too Many Requests` 响应。

生成不符合条件的请求：

```shell
curl -i "http://127.0.0.1:9080/anything/anything?env=v1"
```

您应该收到所有请求的 `HTTP/1.1 200 OK` 响应，因为它们不受速率限制。

### 按消费者有条件地应用速率限制

以下示例演示了如何配置插件以根据以下规范执行速率限制：

* 消费者 `john` 在 30 秒内应有 5 个请求的配额
* 消费者 `jane` 在 30 秒内应有 3 个请求的配额
* 所有其他消费者在 30 秒内应有 2 个请求的配额

虽然此示例将使用 [`key-auth`](./key-auth.md)，但您可以轻松地将其替换为其他身份验证插件。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建消费者 `john`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
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

创建第二个消费者 `jane`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jane"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jane/credentials" -X PUT \
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

创建第三个消费者 `jimmy`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jimmy"
  }'
```

为消费者创建 `key-auth` 凭证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jimmy/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jimmy-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jimmy-key"
      }
    }
  }'
```

使用 `workflow` 和 `key-auth` 插件创建路由，并设置所需的速率限制规则：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "workflow-route",
    "uri": "/anything",
    "plugins":{
      "key-auth": {},
      "workflow":{
        "rules":[
          {
            "actions": [
              [
                "limit-count",
                {
                  "count": 5,
                  "key": "consumer_john",
                  "key_type": "constant",
                  "rejected_code": 429,
                  "time_window": 30,
                  "policy": "local"
                }
              ]
            ],
            "case": [
              [
                "consumer_name",
                "==",
                "john"
              ]
            ]
          },
          {
            "actions": [
              [
                "limit-count",
                {
                  "count": 3,
                  "key": "consumer_jane",
                  "key_type": "constant",
                  "rejected_code": 429,
                  "time_window": 30,
                  "policy": "local"
                }
              ]
            ],
            "case": [
              [
                "consumer_name",
                "==",
                "jane"
              ]
            ]
          },
          {
            "actions": [
              [
                "limit-count",
                {
                  "count": 2,
                  "key": "$consumer_name",
                  "key_type": "var",
                  "rejected_code": 429,
                  "time_window": 30,
                  "policy": "local"
                }
              ]
            ]
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

创建三个消费者以及启用按消费者速率限制的路由：

```yaml title="adc.yaml"
consumers:
  - username: john
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: john-key
  - username: jane
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jane-key
  - username: jimmy
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jimmy-key
services:
  - name: httpbin
    routes:
      - uris:
          - /anything
        name: workflow-route
        plugins:
          key-auth: {}
          workflow:
            rules:
              - case:
                  - ["consumer_name", "==", "john"]
                actions:
                  - - limit-count
                    - count: 5
                      key: consumer_john
                      key_type: constant
                      rejected_code: 429
                      time_window: 30
                      policy: local
              - case:
                  - ["consumer_name", "==", "jane"]
                actions:
                  - - limit-count
                    - count: 3
                      key: consumer_jane
                      key_type: constant
                      rejected_code: 429
                      time_window: 30
                      policy: local
              - actions:
                  - - limit-count
                    - count: 2
                      key: "$consumer_name"
                      key_type: var
                      rejected_code: 429
                      time_window: 30
                      policy: local
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

创建三个消费者以及启用按消费者速率限制的路由。当使用 Ingress Controller 配置消费者时，消费者名称以 `namespace_consumername` 格式生成。因此，`workflow` 插件中的 `consumer_name` 逻辑应以此格式匹配消费者名称。

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="workflow-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: john
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-key
      config:
        key: john-key
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jane
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-key
      config:
        key: jane-key
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jimmy
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-key
      config:
        key: jimmy-key
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
  name: workflow-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: workflow
      config:
        rules:
          - case:
              - ["consumer_name", "==", "aic_john"]
            actions:
              - - limit-count
                - count: 5
                  key: consumer_john
                  key_type: constant
                  rejected_code: 429
                  time_window: 30
                  policy: local
          - case:
              - ["consumer_name", "==", "aic_jane"]
            actions:
              - - limit-count
                - count: 3
                  key: consumer_jane
                  key_type: constant
                  rejected_code: 429
                  time_window: 30
                  policy: local
          - actions:
              - - limit-count
                - count: 2
                  key: "$consumer_name"
                  key_type: var
                  rejected_code: 429
                  time_window: 30
                  policy: local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: workflow-route
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
            name: workflow-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="workflow-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: john
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
  name: jane
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jane-key
---
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: jimmy
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jimmy-key
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
  name: workflow-route
spec:
  ingressClassName: apisix
  http:
    - name: workflow-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
      - name: workflow
        enable: true
        config:
          rules:
            - case:
                - ["consumer_name", "==", "aic_john"]
              actions:
                - - limit-count
                  - count: 5
                    key: consumer_john
                    key_type: constant
                    rejected_code: 429
                    time_window: 30
                    policy: local
            - case:
                - ["consumer_name", "==", "aic_jane"]
              actions:
                - - limit-count
                  - count: 3
                    key: consumer_jane
                    key_type: constant
                    rejected_code: 429
                    time_window: 30
                    policy: local
            - actions:
                - - limit-count
                  - count: 2
                    key: "$consumer_name"
                    key_type: var
                    rejected_code: 429
                    time_window: 30
                    policy: local
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f workflow-ic.yaml
```

</TabItem>

</Tabs>

为了验证，请使用 `john` 的密钥发送 6 个连续请求：

```shell
resp=$(seq 6 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: john-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

您应该看到以下响应，显示在 6 个请求中，5 个请求成功（状态码 200），而其他请求被拒绝（状态码 429）。

```text
200:    5, 429:    1
```

使用 `jane` 的密钥发送 6 个连续请求：

```shell
resp=$(seq 6 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jane-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

您应该看到以下响应，显示在 6 个请求中，3 个请求成功（状态码 200），而其他请求被拒绝（状态码 429）。

```text
200:    3, 429:    3
```

使用 `jimmy` 的密钥发送 3 个连续请求：

```shell
resp=$(seq 3 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jimmy-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

您应该看到以下响应，显示在 3 个请求中，2 个请求成功（状态码 200），而其他请求被拒绝（状态码 429）。

```text
200:    2, 429:    1
```
