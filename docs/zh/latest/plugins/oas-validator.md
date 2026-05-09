---
title: oas-validator
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - oas-validator
  - OpenAPI
  - 请求校验
description: oas-validator 插件根据 OpenAPI Specification（OAS）3.x 文档校验入站 HTTP 请求，在请求到达上游服务前拒绝不合规的请求。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/oas-validator" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`oas-validator` 插件在请求转发至上游服务之前，根据 [OpenAPI Specification（OAS）3.x](https://swagger.io/specification/) 文档对入站 HTTP 请求进行校验。可校验内容包括请求方法、路径、查询参数、请求头以及请求体。

OpenAPI 规范可以以内联 JSON 字符串的形式提供，也可以从远程 URL 获取并配置缓存。校验失败时返回可配置的 HTTP 错误状态码，并可选择在响应体中包含详细的错误信息。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| spec | string | 否* | | | 内联 OpenAPI 3.x 规范（JSON 格式）。未设置 `spec_url` 时必填。 |
| spec_url | string | 否* | | `^https?://` | 获取 OpenAPI 规范的 URL。未设置 `spec` 时必填。 |
| spec_url_request_headers | object | 否 | | | 获取 `spec_url` 时附带的自定义 HTTP 请求头，适用于需要鉴权的规范接口。 |
| ssl_verify | boolean | 否 | false | | 获取 `spec_url` 时是否校验 TLS 证书。 |
| timeout | integer | 否 | 10000 | [1000, 60000] | 获取 `spec_url` 的 HTTP 请求超时时间（毫秒）。 |
| verbose_errors | boolean | 否 | false | | 为 `true` 时，在响应体中返回详细的校验错误信息。 |
| skip_request_body_validation | boolean | 否 | false | | 跳过请求体校验。 |
| skip_request_header_validation | boolean | 否 | false | | 跳过请求头校验。 |
| skip_query_param_validation | boolean | 否 | false | | 跳过查询参数校验。 |
| skip_path_params_validation | boolean | 否 | false | | 跳过路径参数校验。 |
| reject_if_not_match | boolean | 否 | true | | 为 `true` 时，拒绝校验失败的请求；为 `false` 时，仅记录校验失败日志并放行请求。 |
| rejection_status_code | integer | 否 | 400 | [400, 599] | 请求校验失败时返回的 HTTP 状态码。 |

\* `spec` 与 `spec_url` 必须且只能设置其中一个。

### 插件元数据

以下元数据属性通过插件元数据 API 进行配置，作用于插件级别：

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| spec_url_ttl | integer | 否 | 3600 | ≥ 1 | 从 `spec_url` 获取的规范的缓存时间（秒）。 |

## 示例

以下示例演示了如何在不同场景中使用 `oas-validator` 插件。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 使用内联规范校验请求

以下示例演示如何使用内联 OpenAPI 3.x 规范校验请求。不符合规范的请求将以 `400` 响应被拒绝。

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
    "id": "oas-validator-route",
    "uri": "/api/v3/*",
    "plugins": {
      "oas-validator": {
        "spec": "{\"openapi\":\"3.0.2\",\"info\":{\"title\":\"Pet API\",\"version\":\"1.0.0\"},\"paths\":{\"/api/v3/pet\":{\"post\":{\"requestBody\":{\"required\":true,\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"},\"status\":{\"type\":\"string\"}}}}}},\"responses\":{\"200\":{\"description\":\"OK\"}}}}}}",
        "verbose_errors": true
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
      - name: oas-validator-route
        uris:
          - /api/v3/*
        plugins:
          oas-validator:
            spec: '{"openapi":"3.0.2","info":{"title":"Pet API","version":"1.0.0"},"paths":{"/api/v3/pet":{"post":{"requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"object","required":["name"],"properties":{"name":{"type":"string"},"status":{"type":"string"}}}}}},"responses":{"200":{"description":"OK"}}}}}}'
            verbose_errors: true
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

```yaml title="oas-validator-ic.yaml"
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
  name: oas-validator-plugin-config
spec:
  plugins:
    - name: oas-validator
      config:
        spec: '{"openapi":"3.0.2","info":{"title":"Pet API","version":"1.0.0"},"paths":{"/api/v3/pet":{"post":{"requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"object","required":["name"],"properties":{"name":{"type":"string"},"status":{"type":"string"}}}}}},"responses":{"200":{"description":"OK"}}}}}}'
        verbose_errors: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: oas-validator-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/v3/
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: oas-validator-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="oas-validator-ic.yaml"
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
  name: oas-validator-route
spec:
  ingressClassName: apisix
  http:
    - name: oas-validator-route
      match:
        paths:
          - /api/v3/*
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: oas-validator
        enable: true
        config:
          spec: '{"openapi":"3.0.2","info":{"title":"Pet API","version":"1.0.0"},"paths":{"/api/v3/pet":{"post":{"requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"object","required":["name"],"properties":{"name":{"type":"string"},"status":{"type":"string"}}}}}},"responses":{"200":{"description":"OK"}}}}}}'
          verbose_errors: true
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f oas-validator-ic.yaml
```

</TabItem>

</Tabs>

发送一个包含必填 `name` 字段的合法请求：

```shell
curl -i "http://127.0.0.1:9080/api/v3/pet" -X POST \
  -H "Content-Type: application/json" \
  -d '{"name": "doggie", "status": "available"}'
```

将收到来自上游的 `200` 响应。

发送一个缺少必填 `name` 字段的非法请求：

```shell
curl -i "http://127.0.0.1:9080/api/v3/pet" -X POST \
  -H "Content-Type: application/json" \
  -d '{"status": "available"}'
```

将收到包含校验错误信息的 `400` 响应。

### 使用远程规范 URL 校验请求

以下示例演示如何从远程 URL 获取 OpenAPI 规范。规范在首次获取后会被缓存，缓存时长由插件元数据的 `spec_url_ttl` 参数决定。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

配置插件元数据以设置远程规范的缓存时间：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/oas-validator" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "spec_url_ttl": 600
  }'
```

创建带有 `oas-validator` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "oas-validator-url-route",
    "uri": "/api/v3/*",
    "plugins": {
      "oas-validator": {
        "spec_url": "https://petstore3.swagger.io/api/v3/openapi.json",
        "ssl_verify": false,
        "verbose_errors": true
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
      - name: oas-validator-url-route
        uris:
          - /api/v3/*
        plugins:
          oas-validator:
            spec_url: "https://petstore3.swagger.io/api/v3/openapi.json"
            ssl_verify: false
            verbose_errors: true
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

```yaml title="oas-validator-url-ic.yaml"
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
  name: oas-validator-url-plugin-config
spec:
  plugins:
    - name: oas-validator
      config:
        spec_url: "https://petstore3.swagger.io/api/v3/openapi.json"
        ssl_verify: false
        verbose_errors: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: oas-validator-url-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/v3/
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: oas-validator-url-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="oas-validator-url-ic.yaml"
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
  name: oas-validator-url-route
spec:
  ingressClassName: apisix
  http:
    - name: oas-validator-url-route
      match:
        paths:
          - /api/v3/*
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: oas-validator
        enable: true
        config:
          spec_url: "https://petstore3.swagger.io/api/v3/openapi.json"
          ssl_verify: false
          verbose_errors: true
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f oas-validator-url-ic.yaml
```

</TabItem>

</Tabs>

发送一个不符合 Petstore 规范的请求：

```shell
curl -i "http://127.0.0.1:9080/api/v3/pet" -X POST \
  -H "Content-Type: application/json" \
  -d '{"invalid": "body"}'
```

由于 `verbose_errors` 设置为 `true`，将收到包含详细校验错误信息的 `400` 响应。
