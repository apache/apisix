---
title: Forward Authentication (forward-auth)
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Forward Authentication
  - forward-auth
description: The forward-auth Plugin integrates with external authorization services, enhancing API security and access control.
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

## Description

The `forward-auth` Plugin supports the integration with an external authorization service for authentication and authorization. If the authentication fails, a customizable error message will be returned to the client. If the authentication succeeds, the request will be forwarded to the Upstream service along with the following request headers that APISIX added:

- `X-Forwarded-Proto`: scheme
- `X-Forwarded-Method`: HTTP method
- `X-Forwarded-Host`: host
- `X-Forwarded-Uri`: URI
- `X-Forwarded-For`: source IP

## Attributes

| Name              | Type          | Required | Default | Valid values              | Description                                                                                                                                                                                                                                                                                 |
| ----------------- | ------------- | -------- | ------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| uri               | string        | True     |         |                           | URI of the external authorization service.                                                                                                                                                                                                                                                  |
| ssl_verify        | boolean       | False    | true    |                           | If true, verify the authorization service's SSL certificate.                                                                                                                                                                                                                                |
| request_method    | string        | False    | GET     | `GET` or `POST`           | HTTP method APISIX uses to send requests to the external authorization service. When set to `POST`, APISIX will send POST requests along with the request body to the external authorization service. If the authorization decision depends on request parameters from a POST body, it is recommended to extract the necessary fields using `$post_arg.*` and pass them via the `extra_headers` field instead. |
| request_headers   | array         | False    |         |                           | Client request headers that should be forwarded to the external authorization service. If not configured, only headers added by APISIX are forwarded, such as `X-Forwarded-*`.                                                                                                              |
| upstream_headers  | array         | False    |         |                           | External authorization service response headers that should be forwarded to the Upstream service. If not configured, no headers are forwarded to the Upstream service.                                                                                                                      |
| client_headers    | array         | False    |         |                           | External authorization service response headers that should be forwarded to the client when authentication fails. If not configured, no headers are forwarded to the client.                                                                                                                |
| extra_headers     | object        | False    |         |                           | Additional headers to send to the authorization service. Support [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) in values.                                                                                                                                     |
| timeout           | integer       | False    | 3000    | between 1 and 60000 inclusive | Timeout for the external authorization service HTTP call in milliseconds.                                                                                                                                                                                                               |
| keepalive         | boolean       | False    | true    |                           | If true, keep the connections open for multiple requests.                                                                                                                                                                                                                                   |
| keepalive_timeout | integer       | False    | 60000   | >= 1000                   | Idle time in milliseconds after which the established HTTP connections will be closed.                                                                                                                                                                                                      |
| keepalive_pool    | integer       | False    | 5       | >= 1                      | Maximum number of connections in the connection pool.                                                                                                                                                                                                                                       |
| allow_degradation | boolean       | False    | false   |                           | If true, allow APISIX to continue handling requests without the Plugin when the Plugin or its dependencies become unavailable.                                                                                                                                                               |
| status_on_error   | integer       | False    | 403     | between 200 and 599 inclusive | HTTP status code to return to the client when there is a network error with the external authorization service.                                                                                                                                                                         |

## Examples

The examples below demonstrate how you can use `forward-auth` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
```

:::

To follow along the first two examples, please have your external authorization service set up, or create a mock auth service using the [serverless-pre-function](./serverless.md) Plugin as shown below:

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

Synchronize the configuration to the gateway:

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

Apply the configuration to your cluster:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f forward-auth-mock-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

### Forward Designated Headers to Upstream Resource

The following example demonstrates how to set up `forward-auth` on a Route to regulate client access to the resources Upstream based on a value in the request header. It also allows passing a specific header from the authorization service to the Upstream resource.

Create a Route with the `forward-auth` Plugin as such:

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

Synchronize the configuration to the gateway:

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

Apply the configuration to your cluster:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f forward-auth-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

Send a request to the Route with authorization detail in the header:

```shell
curl "http://127.0.0.1:9080/headers" -H 'Authorization: 123'
```

You should see an `HTTP/1.1 200 OK` response of the following:

```json
{
  "headers": {
    "Accept": "*/*",
    "Authorization": "123",
    ...
  }
}
```

To verify if the `X-User-ID` header set by the authorization service will be forwarded to the Upstream service, send a request to the Route with the corresponding authorization detail:

```shell
curl "http://127.0.0.1:9080/headers" -H 'Authorization: 321'
```

You should see an `HTTP/1.1 200 OK` response of the following, showing the header is forwarded to the Upstream:

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

### Return Designated Headers to Clients on Authentication Failure

The following example demonstrates how you can configure `forward-auth` on a Route to regulate client access to the Upstream resources. It also passes a specific header returned by the authorization service to the client when the authentication fails.

Create a Route with the `forward-auth` Plugin as such:

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

Synchronize the configuration to the gateway:

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

Apply the configuration to your cluster:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f forward-auth-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

Send a request without any authentication information:

```shell
curl -i "http://127.0.0.1:9080/headers"
```

You should receive an `HTTP/1.1 403 Forbidden` response:

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

### Authorize Based on POST Body

This example demonstrates how to configure the `forward-auth` Plugin to control access based on POST body data, pass values as headers to the authorization service, and reject the request when authorization fails per the body data.

Please have your external authorization service set up, or create a mock auth service using the [serverless-pre-function](./serverless.md) Plugin. The function checks if the `tenant_id` header is `123` and returns `200 OK` if it is, otherwise it returns 403 with an error message.

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

Synchronize the configuration to the gateway:

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

Apply the configuration to your cluster:

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
                  local tid = tenant_id or "<missing>"
                  core.response.exit(403, "tenant_id is " .. tostring(tenant_id) .. " but expecting 123")
                end
              end
```

Apply the configuration to your cluster:

```shell
kubectl apply -f forward-auth-post-mock-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

Create a Route with the `forward-auth` Plugin as such:

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


Synchronize the configuration to the gateway:

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

Apply the configuration to your cluster:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f forward-auth-post-ic.yaml
```

</TabItem>
</Tabs>

</TabItem>
</Tabs>

Send a POST request with `tenant_id` in the body:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'tenant_id=123'
```

You should receive an `HTTP/1.1 200 OK` response.

Send a POST request with `tenant_id` in the body:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST -d '
{
  "tenant_id": "000"
}'
```

You should receive an `HTTP/1.1 403 Forbidden` response of the following:

```text
tenant_id is 000 but expecting 123
```
