---
title: forward-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Forward Authentication
  - forward-auth
description: forward-auth 插件集成外部授权服务，增强 API 安全性和访问控制。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/forward-auth" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`forward-auth` 插件支持与外部授权服务集成，用于身份验证和授权。如果认证失败，将向客户端返回可自定义的错误消息。如果认证成功，请求将连同以下由 APISIX 添加的请求头一起转发到上游服务：

- `X-Forwarded-Proto`：协议
- `X-Forwarded-Method`：HTTP 方法
- `X-Forwarded-Host`：主机
- `X-Forwarded-Uri`：URI
- `X-Forwarded-For`：源 IP

## 属性

| 名称              | 类型    | 必选项 | 默认值  | 有效值                        | 描述                                                                                                                                                                                                                                                       |
| ----------------- | ------- | ------ | ------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| uri               | string  | 是     |         |                               | 外部授权服务的 URI。                                                                                                                                                                                                                                        |
| ssl_verify        | boolean | 否     | true    |                               | 如果为 true，则验证授权服务的 SSL 证书。                                                                                                                                                                                                                   |
| request_method    | string  | 否     | GET     | `GET` 或 `POST`               | APISIX 向外部授权服务发送请求时使用的 HTTP 方法。当设置为 `POST` 时，APISIX 将连同请求体一起向外部授权服务发送 POST 请求。如果授权决策依赖 POST 正文中的请求参数，建议使用 `$post_arg.*` 提取必要字段并通过 `extra_headers` 字段传递，而不是发送完整请求体。 |
| request_headers   | array   | 否     |         |                               | 需要转发给外部授权服务的客户端请求头。如果未配置，则只转发 APISIX 添加的请求头，例如 `X-Forwarded-*`。                                                                                                                                                     |
| upstream_headers  | array   | 否     |         |                               | 认证通过时，需要转发到 Upstream 服务的外部授权服务响应头。如果未配置，则不转发任何请求头。                                                                                                                                                                 |
| client_headers    | array   | 否     |         |                               | 认证失败时，需要转发给客户端的外部授权服务响应头。如果未配置，则不转发任何响应头。                                                                                                                                                                         |
| extra_headers     | object  | 否     |         |                               | 发送给授权服务的额外请求头，支持在值中使用 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。                                                                                                                                         |
| timeout           | integer | 否     | 3000    | 1 到 60000 之间（含）         | 外部授权服务 HTTP 调用的超时时间（毫秒）。                                                                                                                                                                                                                 |
| keepalive         | boolean | 否     | true    |                               | 如果为 true，则保持连接以处理多个请求。                                                                                                                                                                                                                    |
| keepalive_timeout | integer | 否     | 60000   | >= 1000                       | 已建立的 HTTP 连接在关闭前的空闲时间（毫秒）。                                                                                                                                                                                                             |
| keepalive_pool    | integer | 否     | 5       | >= 1                          | 连接池中的最大连接数。                                                                                                                                                                                                                                     |
| allow_degradation | boolean | 否     | false   |                               | 如果为 true，则允许在插件或其依赖项不可用时，APISIX 继续处理请求而不使用该插件。                                                                                                                                                                           |
| status_on_error   | integer | 否     | 403     | 200 到 599 之间（含）         | 与外部授权服务出现网络错误时返回给客户端的 HTTP 状态码。                                                                                                                                                                                                   |

## 使用示例

以下示例演示了如何针对不同场景使用 `forward-auth`。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

要跟随前两个示例操作，请提前搭建好外部授权服务，或使用 [serverless-pre-function](./serverless.md) 插件创建如下所示的模拟认证服务：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "auth-mock",
    "uri": "/auth",
    "plugins": {
      "serverless-pre-function": {
        "phase": "rewrite",
        "functions": [
          "return function (conf, ctx)
            local core = require(\"apisix.core\");
            local authorization = core.request.header(ctx, \"Authorization\");
            if authorization == \"123\" then
              core.response.exit(200);
            elseif authorization == \"321\" then
              core.response.set_header(\"X-User-ID\", \"i-am-user\");
              core.response.exit(200);
            else core.response.set_header(\"X-Forward-Auth\", \"Fail\");
              core.response.exit(403);
            end
          end"
        ]
      }
    }
  }'
```

</TabItem>

<TabItem value="adc" label="ADC">

```yaml title="adc-auth-mock.yaml"
services:
  - name: auth-mock-service
    routes:
      - name: auth-mock-route
        uris:
          - /auth
        plugins:
          serverless-pre-function:
            phase: rewrite
            functions:
              - |
                return function(conf, ctx)
                  local core = require("apisix.core")
                  local authorization = core.request.header(ctx, "Authorization")
                  if authorization == "123" then
                    core.response.exit(200)
                  elseif authorization == "321" then
                    core.response.set_header("X-User-ID", "i-am-user")
                    core.response.exit(200)
                  else
                    core.response.set_header("X-Forward-Auth", "Fail")
                    core.response.exit(403)
                  end
                end
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步到网关：

```shell
adc sync -f adc-auth-mock.yaml
```

</TabItem>

<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="forward-auth-mock-ic.yaml"
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
  name: auth-mock-plugin-config
spec:
  plugins:
    - name: serverless-pre-function
      config:
        phase: rewrite
        functions:
          - |
            return function(conf, ctx)
              local core = require("apisix.core")
              local authorization = core.request.header(ctx, "Authorization")
              if authorization == "123" then
                core.response.exit(200)
              elseif authorization == "321" then
                core.response.set_header("X-User-ID", "i-am-user")
                core.response.exit(200)
              else
                core.response.set_header("X-Forward-Auth", "Fail")
                core.response.exit(403)
              end
            end
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: auth-mock-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /auth
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: auth-mock-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f forward-auth-mock-ic.yaml
```

</TabItem>

<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="forward-auth-mock-ic.yaml"
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
  name: auth-mock-route
spec:
  ingressClassName: apisix
  http:
    - name: auth-mock-route
      match:
        paths:
          - /auth
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: serverless-pre-function
        enable: true
        config:
          phase: rewrite
          functions:
            - |
              return function(conf, ctx)
                local core = require("apisix.core")
                local authorization = core.request.header(ctx, "Authorization")
                if authorization == "123" then
                  core.response.exit(200)
                elseif authorization == "321" then
                  core.response.set_header("X-User-ID", "i-am-user")
                  core.response.exit(200)
                else
                  core.response.set_header("X-Forward-Auth", "Fail")
                  core.response.exit(403)
                end
              end
```

将配置应用到集群：

```shell
kubectl apply -f forward-auth-mock-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

### 将指定请求头转发至上游资源

以下示例演示了如何在路由上配置 `forward-auth`，根据请求头中的值控制客户端对上游资源的访问，并将授权服务设置的特定请求头转发至上游资源。

按如下方式创建带有 `forward-auth` 插件的路由：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "forward-auth-route",
    "uri": "/headers",
    "plugins": {
      "forward-auth": {
        "uri": "http://127.0.0.1:9080/auth",
        "request_headers": ["Authorization"],
        "upstream_headers": ["X-User-ID"]
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

<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: forward-auth-service
    routes:
      - name: forward-auth-route
        uris:
          - /headers
        plugins:
          forward-auth:
            uri: http://127.0.0.1:9080/auth
            request_headers:
              - Authorization
            upstream_headers:
              - X-User-ID
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

<TabItem value="ingress-controller" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="forward-auth-ic.yaml"
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
  name: forward-auth-plugin-config
spec:
  plugins:
    - name: forward-auth
      config:
        uri: http://apisix-gateway.aic.svc.cluster.local/auth
        request_headers:
          - Authorization
        upstream_headers:
          - X-User-ID
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: forward-auth-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /headers
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: forward-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f forward-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller" label="APISIX Ingress Controller">

```yaml title="forward-auth-ic.yaml"
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
  name: forward-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: forward-auth-route
      match:
        paths:
          - /headers
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: forward-auth
        enable: true
        config:
          uri: http://apisix-gateway.aic.svc.cluster.local/auth
          request_headers:
            - Authorization
          upstream_headers:
            - X-User-ID
```

将配置应用到集群：

```shell
kubectl apply -f forward-auth-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

向路由发送包含认证信息的请求：

```shell
curl "http://127.0.0.1:9080/headers" -H 'Authorization: 123'
```

你应该看到 `HTTP/1.1 200 OK` 响应如下：

```json
{
  "headers": {
    "Accept": "*/*",
    "Authorization": "123",
    ...
  }
}
```

要验证授权服务设置的 `X-User-ID` 请求头是否会转发给上游服务，请使用对应的认证信息向路由发送请求：

```shell
curl "http://127.0.0.1:9080/headers" -H 'Authorization: 321'
```

你应该看到 `HTTP/1.1 200 OK` 响应如下，显示请求头已被转发至上游：

```json
{
  "headers": {
    "Accept": "*/*",
    "Authorization": "123",
    "X-User-ID": "i-am-user",
    ...
  }
}
```

### 认证失败时向客户端返回指定请求头

以下示例演示了如何在路由上配置 `forward-auth`，控制客户端对上游资源的访问，并在认证失败时将授权服务返回的特定请求头传递给客户端。

按如下方式创建带有 `forward-auth` 插件的路由：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "forward-auth-route",
    "uri": "/headers",
    "plugins": {
      "forward-auth": {
        "uri": "http://127.0.0.1:9080/auth",
        "request_headers": ["Authorization"],
        "client_headers": ["X-Forward-Auth"]
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

<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: forward-auth-service
    routes:
      - name: forward-auth-route
        uris:
          - /headers
        plugins:
          forward-auth:
            uri: http://127.0.0.1:9080/auth
            request_headers:
              - Authorization
            client_headers:
              - X-Forward-Auth
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

<TabItem value="ingress-controller" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="forward-auth-ic.yaml"
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
  name: forward-auth-plugin-config
spec:
  plugins:
    - name: forward-auth
      config:
        uri: http://apisix-gateway.aic.svc.cluster.local/auth
        request_headers:
          - Authorization
        client_headers:
          - X-Forward-Auth
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: forward-auth-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /headers
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: forward-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```


将配置应用到集群：

```shell
kubectl apply -f forward-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller" label="APISIX Ingress Controller">

```yaml title="forward-auth-ic.yaml"
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
  name: forward-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: forward-auth-route
      match:
        paths:
          - /headers
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: forward-auth
        enable: true
        config:
          uri: http://apisix-gateway.aic.svc.cluster.local/auth
          request_headers:
            - Authorization
          client_headers:
            - X-Forward-Auth
```


将配置应用到集群：

```shell
kubectl apply -f forward-auth-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

不携带任何认证信息发送请求：

```shell
curl -i "http://127.0.0.1:9080/headers"
```

你应该收到 `HTTP/1.1 403 Forbidden` 响应：

```text
...
X-Forward-Auth: Fail
Server: APISIX/3.x.x

<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>openresty</center>
<p><em>Powered by <a href="https://apisix.apache.org/">APISIX</a>.</em></p></body>
</html>
```

### 基于 POST 请求体进行授权

本示例演示如何配置 `forward-auth` 插件，根据 POST 请求体数据控制访问，将值以请求头的形式传递给授权服务，并在授权失败时拒绝请求。

请提前搭建好外部授权服务，或使用 [serverless-pre-function](./serverless.md) 插件创建模拟认证服务。该函数检查 `tenant_id` 请求头是否为 `123`，如果是则返回 `200 OK`，否则返回 403 和错误消息。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "auth-mock",
    "uri": "/auth",
    "plugins": {
      "serverless-pre-function": {
        "phase": "rewrite",
        "functions": [
          "return function(conf, ctx)
            local core = require(\"apisix.core\")
            local tenant_id = core.request.header(ctx, \"tenant_id\")
            if tenant_id == \"123\" then
              core.response.exit(200);
          else
            core.response.exit(403, \"tenant_id is \"..tenant_id .. \" but expecting 123\");
          end
        end"
        ]
      }
    }
  }'
```

</TabItem>

<TabItem value="adc" label="ADC">

```yaml title="adc-auth-mock.yaml"
services:
  - name: auth-mock-service
    routes:
      - name: auth-mock-route
        uris:
          - /auth
        plugins:
          serverless-pre-function:
            phase: rewrite
            functions:
              - |
                return function(conf, ctx)
                  local core = require("apisix.core")
                  local tenant_id = core.request.header(ctx, "tenant_id")
                  if tenant_id == "123" then
                    core.response.exit(200)
                  else
                    local tid = tenant_id or "<missing>"
                    core.response.exit(403, "tenant_id is " .. tenant_id .. " but expecting 123")
                  end
                end
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将配置同步到网关：

```shell
adc sync -f adc-auth-mock.yaml
```

</TabItem>

<TabItem value="ingress-controller" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="forward-auth-post-mock-ic.yaml"
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
  name: auth-mock-plugin-config
spec:
  plugins:
    - name: serverless-pre-function
      config:
        phase: rewrite
        functions:
          - |
            return function(conf, ctx)
              local core = require("apisix.core")
              local tenant_id = core.request.header(ctx, "tenant_id")
              if tenant_id == "123" then
                core.response.exit(200)
              else
                local tid = tenant_id or "<missing>"
                core.response.exit(403, "tenant_id is " .. tostring(tenant_id) .. " but expecting 123")
              end
            end
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: auth-mock-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /auth
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: auth-mock-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f forward-auth-post-mock-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller" label="APISIX Ingress Controller">

```yaml title="forward-auth-post-mock-ic.yaml"
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
  name: auth-mock-route
spec:
  ingressClassName: apisix
  http:
    - name: auth-mock-route
      match:
        paths:
          - /auth
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: serverless-pre-function
        enable: true
        config:
          phase: rewrite
          functions:
            - |
              return function(conf, ctx)
                local core = require("apisix.core")
                local tenant_id = core.request.header(ctx, "tenant_id")
                if tenant_id == "123" then
                  core.response.exit(200)
                else
                  core.response.exit(403, "tenant_id is " .. tostring(tenant_id) .. " but expecting 123")
                end
              end
```

将配置应用到集群：

```shell
kubectl apply -f forward-auth-post-mock-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

按如下方式创建带有 `forward-auth` 插件的路由：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "forward-auth-route",
    "uri": "/post",
    "methods": ["POST"],
    "plugins": {
      "forward-auth": {
        "uri": "http://127.0.0.1:9080/auth",
        "request_method": "GET",
        "extra_headers": {"tenant_id": "$post_arg.tenant_id"}
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

<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: forward-auth-service
    routes:
      - name: forward-auth-route
        uris:
          - /post
        methods:
          - POST
        plugins:
          forward-auth:
            uri: http://127.0.0.1:9080/auth
            request_method: GET
            extra_headers:
              tenant_id: "$post_arg.tenant_id"
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

<TabItem value="ingress-controller" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="forward-auth-post-ic.yaml"
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
  name: forward-auth-post-plugin-config
spec:
  plugins:
    - name: forward-auth
      config:
        uri: http://apisix-gateway.aic.svc.cluster.local/auth
        request_method: GET
        extra_headers:
          tenant_id: "$post_arg.tenant_id"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: forward-auth-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /post
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: forward-auth-post-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f forward-auth-post-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller" label="APISIX Ingress Controller">

```yaml title="forward-auth-post-ic.yaml"
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
  name: forward-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: forward-auth-route
      match:
        paths:
          - /post
        methods:
          - POST
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: forward-auth
        enable: true
        config:
          uri: http://apisix-gateway.aic.svc.cluster.local/auth
          request_method: GET
          extra_headers:
            tenant_id: "$post_arg.tenant_id"
```

将配置应用到集群：

```shell
kubectl apply -f forward-auth-post-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

在请求体中携带 `tenant_id` 发送 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'tenant_id=123'
```

你应该收到 `HTTP/1.1 200 OK` 响应。

在请求体中携带错误的 `tenant_id` 发送 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST -d '
{
  "tenant_id": "000"
}'
```

你应该收到 `HTTP/1.1 403 Forbidden` 响应，内容如下：

```text
tenant_id is 000 but expecting 123
```
