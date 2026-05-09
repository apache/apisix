---
title: exit-transformer
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - exit-transformer
  - 错误响应转换
description: exit-transformer 插件拦截 APISIX 生成的错误响应，并通过用户自定义的 Lua 函数对其进行转换后再发送给客户端。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/exit-transformer" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`exit-transformer` 插件拦截由 APISIX 自身生成的响应——例如认证失败、限流拒绝或上游错误——并在发送给客户端之前，通过用户自定义的 Lua 函数对其进行转换。

该插件通过注册回调函数的方式工作：当 `core.response.exit()` 被调用时，回调函数依次执行，接收响应的 `(状态码, 响应体, 响应头)` 作为参数，并返回（可能已修改的）值。多个函数可以链式执行，前一个函数的输出作为下一个函数的输入。

:::note

该插件仅转换由 APISIX 自身 `core.response.exit()` 机制产生的响应，**不会**转换来自上游服务的响应。

:::

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 描述 |
|------|------|--------|--------|------|
| functions | array[string] | 是 | | Lua 函数源码字符串数组。每个字符串必须是一个完整的 Lua 代码块，该代码块须返回一个函数。函数接收 `(status_code, body, headers)` 三个参数，并必须返回 `status_code, body, headers`（修改后的或原始值）。若函数抛出异常，错误将被记录到日志，原始值将被传递给下一个函数。 |

每个 Lua 函数字符串必须是一个可求值为函数的代码块，函数签名如下：

```lua
return (function(code, body, header)
    -- 按需修改 code、body 或 header
    return code, body, header
end)(...)
```

## 示例

以下示例演示了如何在不同场景中使用 `exit-transformer` 插件。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 重映射状态码

以下示例演示如何将 `401 Unauthorized` 响应重映射为 `403 Forbidden`。

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
    "id": "exit-transformer-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {},
      "exit-transformer": {
        "functions": [
          "return (function(code, body, header) if code == 401 then return 403, body, header end return code, body, header end)(...)"
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
      - name: exit-transformer-route
        uris:
          - /anything
        plugins:
          key-auth: {}
          exit-transformer:
            functions:
              - "return (function(code, body, header) if code == 401 then return 403, body, header end return code, body, header end)(...)"
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

```yaml title="exit-transformer-ic.yaml"
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
  name: exit-transformer-plugin-config
spec:
  plugins:
    - name: key-auth
      config: {}
    - name: exit-transformer
      config:
        functions:
          - "return (function(code, body, header) if code == 401 then return 403, body, header end return code, body, header end)(...)"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: exit-transformer-route
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
            name: exit-transformer-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="exit-transformer-ic.yaml"
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
  name: exit-transformer-route
spec:
  ingressClassName: apisix
  http:
    - name: exit-transformer-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
        config: {}
      - name: exit-transformer
        enable: true
        config:
          functions:
            - "return (function(code, body, header) if code == 401 then return 403, body, header end return code, body, header end)(...)"
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f exit-transformer-ic.yaml
```

</TabItem>

</Tabs>

发送一个不带 API Key 的请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

将收到 `403 Forbidden` 响应，而非默认的 `401 Unauthorized`。

### 统一错误响应格式

以下示例演示如何将所有错误响应体重写为统一的 JSON 格式，并添加自定义响应头。

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
    "id": "exit-transformer-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {},
      "exit-transformer": {
        "functions": [
          "return (function(code, body, header) if code and code >= 400 then header = header or {} header[\"X-Error-Code\"] = tostring(code) body = {error = true, status = code, message = (type(body) == \"table\" and body.message) or \"request failed\"} end return code, body, header end)(...)"
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
      - name: exit-transformer-route
        uris:
          - /anything
        plugins:
          key-auth: {}
          exit-transformer:
            functions:
              - "return (function(code, body, header) if code and code >= 400 then header = header or {} header[\"X-Error-Code\"] = tostring(code) body = {error = true, status = code, message = (type(body) == \"table\" and body.message) or \"request failed\"} end return code, body, header end)(...)"
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

```yaml title="exit-transformer-ic.yaml"
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
  name: exit-transformer-plugin-config
spec:
  plugins:
    - name: key-auth
      config: {}
    - name: exit-transformer
      config:
        functions:
          - "return (function(code, body, header) if code and code >= 400 then header = header or {} header[\"X-Error-Code\"] = tostring(code) body = {error = true, status = code, message = (type(body) == \"table\" and body.message) or \"request failed\"} end return code, body, header end)(...)"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: exit-transformer-route
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
            name: exit-transformer-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="exit-transformer-ic.yaml"
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
  name: exit-transformer-route
spec:
  ingressClassName: apisix
  http:
    - name: exit-transformer-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
        config: {}
      - name: exit-transformer
        enable: true
        config:
          functions:
            - "return (function(code, body, header) if code and code >= 400 then header = header or {} header[\"X-Error-Code\"] = tostring(code) body = {error = true, status = code, message = (type(body) == \"table\" and body.message) or \"request failed\"} end return code, body, header end)(...)"
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f exit-transformer-ic.yaml
```

</TabItem>

</Tabs>

发送一个不带 API Key 的请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

将收到带有统一 JSON 格式响应体和 `X-Error-Code: 401` 响应头的 `401` 响应：

```json
{"error":true,"status":401,"message":"Missing API key found in request"}
```
