---
title: cors
keywords:
  - Apache APISIX
  - API 网关
  - CORS
description: cors 插件允许你启用跨域资源共享 (CORS，Cross-Origin Resource Sharing)。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/cors" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`cors` 插件允许你启用[跨域资源共享 (CORS，Cross-Origin Resource Sharing)](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Guides/CORS)。CORS 是一种基于 HTTP 头的机制，它允许服务器指定除自身以外的任意源（域、协议或端口），并指示浏览器允许从这些源加载资源。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|---|---|---|---|---|---|
| allow_origins | string | 否 | `"*"` | | 允许跨域访问的 Origin，格式为 `scheme://host:port`，示例如 `https://somedomain.com:8081`。如果有多个 Origin，请使用 `,` 分隔。当 `allow_credential` 为 `false` 时，可以使用 `*` 表示允许所有 Origin 通过。开启 `allow_credential` 后可使用 `**` 强制允许所有 Origin，但存在安全隐患。 |
| allow_methods | string | 否 | `"*"` | | 允许跨域访问的 HTTP 请求方法，比如 `GET`、`POST`。如果有多个方法，请使用 `,` 分隔。当 `allow_credential` 为 `false` 时，可以使用 `*` 表示允许所有方法通过。开启 `allow_credential` 后可使用 `**` 强制允许所有方法，但存在安全隐患。 |
| allow_headers | string | 否 | `"*"` | | 允许跨域访问时请求方携带哪些非 CORS 规范以外的 Header。如果有多个 Header，请使用 `,` 分隔。当 `allow_credential` 为 `false` 时，可以使用 `*` 表示允许所有 Header 通过。开启 `allow_credential` 后可使用 `**` 强制允许所有 Header，但存在安全隐患。 |
| expose_headers | string | 否 | | | 允许跨域访问时响应方携带哪些非 CORS 规范以外的 Header。如果有多个 Header，请使用 `,` 分隔。当 `allow_credential` 为 `false` 时，可以使用 `*` 表示允许任意 Header。如果不设置，插件不会修改 `Access-Control-Expose-Headers` 头，详情请参考 [Access-Control-Expose-Headers - MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Expose-Headers)。 |
| max_age | integer | 否 | 5 | | 浏览器缓存 CORS 预检请求结果的最大时间，单位为秒。在此时间范围内，浏览器会复用上一次的检查结果。设置为 `-1` 表示禁用缓存。请注意各浏览器允许的最大时间不同，详情请参考 [Access-Control-Max-Age - MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age#directives)。 |
| allow_credential | boolean | 否 | false | | 是否允许跨域访问的请求方携带凭据（如 Cookie 等）。根据 CORS 规范，如果设置该选项为 `true`，那么将不能在其他属性中使用 `*`。 |
| allow_origins_by_regex | array | 否 | | | 使用正则表达式匹配允许跨域访问的 Origin，如 `[".*\.test.com$"]` 可以匹配 `test.com` 的所有子域名。配置后，仅匹配正则表达式的域名会被允许，`allow_origins` 的配置将被忽略。 |
| allow_origins_by_metadata | array | 否 | | | 通过引用插件元数据的 `allow_origins` 配置允许跨域访问的 Origin。比如当插件元数据为 `"allow_origins": {"EXAMPLE": "https://example.com"}` 时，配置 `["EXAMPLE"]` 将允许 Origin `https://example.com` 的访问。 |
| timing_allow_origins | string | 否 | | | 允许访问资源时序信息的 Origin 列表，多个 Origin 使用 `,` 分隔。详情请参考 [Timing-Allow-Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Timing-Allow-Origin)。 |
| timing_allow_origins_by_regex | array | 否 | | | 使用正则表达式匹配允许访问资源时序信息的 Origin，如 `[".*\.test.com"]` 可以匹配 `test.com` 的所有子域名。配置后，仅匹配正则表达式的域名会被允许，`timing_allow_origins` 的配置将被忽略。 |

:::info IMPORTANT

1. `allow_credential` 是一个很敏感的选项，请谨慎开启。开启之后，其他参数默认的 `*` 将失效，你必须显式指定它们的值。
2. 在使用 `**` 时，需要清楚该参数引入的一些安全隐患，比如 CSRF，并确保这样的安全等级符合自己预期。

:::

## 元数据

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|---|---|---|---|---|---|
| allow_origins | object | 否 | | | 定义允许跨域访问的 Origin 映射表；其键为 `allow_origins_by_metadata` 使用的引用键，值则为允许跨域访问的 Origin，其语义与属性中的 `allow_origins` 相同。 |

## 示例

以下示例展示了如何针对不同场景配置 `cors` 插件。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 为路由启用 CORS

以下示例展示如何在路由上启用 CORS，允许来自指定 Origin 列表的资源加载。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建带有 `cors` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cors-route",
    "uri": "/anything",
    "plugins": {
      "cors": {
        "allow_origins": "http://sub.domain.com,http://sub2.domain.com",
        "allow_methods": "GET,POST",
        "allow_headers": "headr1,headr2",
        "expose_headers": "ex-headr1,ex-headr2",
        "max_age": 50,
        "allow_credential": true
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: cors-service
    routes:
      - name: cors-route
        uris:
          - /anything
        plugins:
          cors:
            allow_origins: "http://sub.domain.com,http://sub2.domain.com"
            allow_methods: "GET,POST"
            allow_headers: "headr1,headr2"
            expose_headers: "ex-headr1,ex-headr2"
            max_age: 50
            allow_credential: true
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步至 APISIX：

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

```yaml title="cors-ic.yaml"
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
  name: cors-plugin-config
spec:
  plugins:
    - name: cors
      config:
        allow_origins: "http://sub.domain.com,http://sub2.domain.com"
        allow_methods: "GET,POST"
        allow_headers: "headr1,headr2"
        expose_headers: "ex-headr1,ex-headr2"
        max_age: 50
        allow_credential: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: cors-route
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
            name: cors-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f cors-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="cors-ic.yaml"
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
  name: cors-route
spec:
  ingressClassName: apisix
  http:
    - name: cors-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: cors
        enable: true
        config:
          allow_origins: "http://sub.domain.com,http://sub2.domain.com"
          allow_methods: "GET,POST"
          allow_headers: "headr1,headr2"
          expose_headers: "ex-headr1,ex-headr2"
          max_age: 50
          allow_credential: true
```

将配置应用到集群：

```shell
kubectl apply -f cors-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向路由发送一个来自允许的 Origin 的请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://sub2.domain.com" -I
```

你应该会收到 `HTTP/1.1 200 OK` 响应，并能看到 CORS 相关 Header：

```text
...
Access-Control-Allow-Origin: http://sub2.domain.com
Access-Control-Allow-Credentials: true
Server: APISIX/3.8.0
Vary: Origin
Access-Control-Allow-Methods: GET,POST
Access-Control-Max-Age: 50
Access-Control-Expose-Headers: ex-headr1,ex-headr2
Access-Control-Allow-Headers: headr1,headr2
```

向路由发送一个来自不被允许的 Origin 的请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://sub3.domain.com" -I
```

你应该会收到 `HTTP/1.1 200 OK` 响应，但不含任何 CORS Header：

```text
...
Server: APISIX/3.8.0
Vary: Origin
```

### 使用正则表达式匹配 Origin

以下示例展示如何使用 `allow_origins_by_regex` 属性，通过正则表达式匹配允许的 Origin。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建带有 `cors` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cors-route",
    "uri": "/anything",
    "plugins": {
      "cors": {
        "allow_methods": "GET,POST",
        "allow_headers": "headr1,headr2",
        "expose_headers": "ex-headr1,ex-headr2",
        "max_age": 50,
        "allow_origins_by_regex": [ ".*\\.test.com$" ]
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: cors-service
    routes:
      - name: cors-route
        uris:
          - /anything
        plugins:
          cors:
            allow_methods: "GET,POST"
            allow_headers: "headr1,headr2"
            expose_headers: "ex-headr1,ex-headr2"
            max_age: 50
            allow_origins_by_regex:
              - ".*\\.test.com$"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步至 APISIX：

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

```yaml title="cors-ic.yaml"
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
  name: cors-regex-plugin-config
spec:
  plugins:
    - name: cors
      config:
        allow_methods: "GET,POST"
        allow_headers: "headr1,headr2"
        expose_headers: "ex-headr1,ex-headr2"
        max_age: 50
        allow_origins_by_regex:
          - ".*\\.test.com$"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: cors-route
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
            name: cors-regex-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f cors-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="cors-ic.yaml"
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
  name: cors-route
spec:
  ingressClassName: apisix
  http:
    - name: cors-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: cors
        enable: true
        config:
          allow_methods: "GET,POST"
          allow_headers: "headr1,headr2"
          expose_headers: "ex-headr1,ex-headr2"
          max_age: 50
          allow_origins_by_regex:
            - ".*\\.test.com$"
```

将配置应用到集群：

```shell
kubectl apply -f cors-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向路由发送一个来自匹配的 Origin 的请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://a.test.com" -I
```

你应该会收到 `HTTP/1.1 200 OK` 响应，并能看到 CORS 相关 Header：

```text
...
Access-Control-Allow-Origin: http://a.test.com
Server: APISIX/3.8.0
Vary: Origin
Access-Control-Allow-Methods: GET,POST
Access-Control-Max-Age: 50
Access-Control-Expose-Headers: ex-headr1,ex-headr2
Access-Control-Allow-Headers: headr1,headr2
```

向路由发送一个来自不匹配的 Origin 的请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://a.test2.com" -I
```

你应该会收到 `HTTP/1.1 200 OK` 响应，但不含任何 CORS Header：

```text
...
Server: APISIX/3.8.0
Vary: Origin
```

### 在插件元数据中配置 Origin

以下示例展示如何在[插件元数据](https://apisix.apache.org/zh/docs/apisix/terminology/plugin/)中配置允许的 Origin，并通过 `allow_origins_by_metadata` 在 `cors` 插件中引用。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

配置 `cors` 插件的元数据：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/cors" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "allow_origins": {
      "key_1": "https://domain.com",
      "key_2": "https://sub.domain.com,https://sub2.domain.com",
      "key_3": "*"
    }
  }'
```

使用 `allow_origins_by_metadata` 创建带有 `cors` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cors-route",
    "uri": "/anything",
    "plugins": {
      "cors": {
        "allow_methods": "GET,POST",
        "allow_headers": "headr1,headr2",
        "expose_headers": "ex-headr1,ex-headr2",
        "max_age": 50,
        "allow_origins_by_metadata": ["key_1"]
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
plugin_metadata:
  cors:
    allow_origins:
      key_1: "https://domain.com"
      key_2: "https://sub.domain.com,https://sub2.domain.com"
      key_3: "*"
services:
  - name: cors-service
    routes:
      - name: cors-route
        uris:
          - /anything
        plugins:
          cors:
            allow_methods: "GET,POST"
            allow_headers: "headr1,headr2"
            expose_headers: "ex-headr1,ex-headr2"
            max_age: 50
            allow_origins_by_metadata:
              - "key_1"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步至 APISIX：

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

更新 GatewayProxy 清单以配置插件元数据：

```yaml title="gatewayproxy.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: GatewayProxy
metadata:
  namespace: aic
  name: apisix-config
spec:
  provider:
    type: ControlPlane
    controlPlane:
      # 你的控制面连接配置
  pluginMetadata:
    cors:
      allow_origins:
        key_1: "https://domain.com"
        key_2: "https://sub.domain.com,https://sub2.domain.com"
        key_3: "*"
```

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

使用 `allow_origins_by_metadata` 创建路由：

```yaml title="cors-ic.yaml"
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
  name: cors-metadata-plugin-config
spec:
  plugins:
    - name: cors
      config:
        allow_methods: "GET,POST"
        allow_headers: "headr1,headr2"
        expose_headers: "ex-headr1,ex-headr2"
        max_age: 50
        allow_origins_by_metadata:
          - "key_1"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: cors-route
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
            name: cors-metadata-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f gatewayproxy.yaml -f cors-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

使用 `allow_origins_by_metadata` 创建路由：

```yaml title="cors-ic.yaml"
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
  name: cors-route
spec:
  ingressClassName: apisix
  http:
    - name: cors-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: cors
        enable: true
        config:
          allow_methods: "GET,POST"
          allow_headers: "headr1,headr2"
          expose_headers: "ex-headr1,ex-headr2"
          max_age: 50
          allow_origins_by_metadata:
            - "key_1"
```

将配置应用到集群：

```shell
kubectl apply -f gatewayproxy.yaml -f cors-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向路由发送一个来自元数据中允许的 Origin 的请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: https://domain.com" -I
```

你应该会收到 `HTTP/1.1 200 OK` 响应，并能看到 CORS 相关 Header：

```text
...
Access-Control-Allow-Origin: https://domain.com
Server: APISIX/3.8.0
Vary: Origin
Access-Control-Allow-Methods: GET,POST
Access-Control-Max-Age: 50
Access-Control-Expose-Headers: ex-headr1,ex-headr2
Access-Control-Allow-Headers: headr1,headr2
```

向路由发送一个不在元数据中的 Origin 的请求：

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://a.test2.com" -I
```

你应该会收到 `HTTP/1.1 200 OK` 响应，但不含任何 CORS Header：

```text
...
Server: APISIX/3.8.0
Vary: Origin
```
