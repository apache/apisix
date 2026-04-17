---
title: opa
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Open Policy Agent
  - opa
description: opa 插件与 Open Policy Agent 集成，支持在 API 操作中统一定义和执行授权策略。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/opa" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`opa` 插件支持与 [Open Policy Agent (OPA)](https://www.openpolicyagent.org) 集成，OPA 是一个统一的策略引擎和框架，可用于定义和执行授权策略。授权逻辑以 [Rego](https://www.openpolicyagent.org/docs/latest/policy-language/) 语言编写并存储在 OPA 中。

配置后，OPA 引擎将根据定义的策略评估客户端对受保护 Route 的请求，以决定是否允许其访问 Upstream 资源。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| host | string | 是 | | | OPA 服务器地址。 |
| policy | string | 是 | | | 要评估的策略。例如，如需评估名为 `rbac` 的包中的所有规则，将 policy 配置为 `rbac`。如需评估包中的特定规则，可在包名后指定规则名，如 `rbac/allow`。 |
| ssl_verify | boolean | 否 | true | | 若为 true，则验证 OPA 服务器的 SSL 证书。 |
| timeout | integer | 否 | 3000 | [1, 60000] | HTTP 调用超时时间（毫秒）。 |
| keepalive | boolean | 否 | true | | 若为 true，则为多个请求保持连接活跃。 |
| keepalive_timeout | integer | 否 | 60000 | >= 1000 | 连接空闲后关闭的等待时间（毫秒）。 |
| keepalive_pool | integer | 否 | 5 | >= 1 | 空闲连接数。 |
| with_route | boolean | 否 | | | 若为 true，发送当前 Route 的信息。 |
| with_service | boolean | 否 | | | 若为 true，发送当前 Service 的信息。 |
| with_consumer | boolean | 否 | | | 若为 true，发送当前 Consumer 的信息。注意，Consumer 信息可能包含 API key 等敏感信息，仅在确认安全的情况下将此选项设为 `true`。 |
| send_headers_upstream | array[string] | 否 | | >= 1 | 请求被允许时，需要从 OPA 响应转发到 Upstream 服务的请求头名称列表。 |

## 数据定义

### APISIX 向 OPA 发送信息

下述示例展示了 APISIX 向 OPA 服务发送的数据格式：

```json
{
    "type": "http",
    "request": {
        "scheme": "http",
        "path": "\/get",
        "headers": {
            "user-agent": "curl\/7.68.0",
            "accept": "*\/*",
            "host": "127.0.0.1:9080"
        },
        "query": {},
        "port": 9080,
        "method": "GET",
        "host": "127.0.0.1"
    },
    "var": {
        "timestamp": 1701234567,
        "server_addr": "127.0.0.1",
        "server_port": "9080",
        "remote_port": "port",
        "remote_addr": "ip address"
    },
    "route": {},
    "service": {},
    "consumer": {}
}
```

各字段说明如下：

- `type` 表示请求类型（`http` 或 `stream`）。
- `request` 在 `type` 为 `http` 时使用，包含基本的请求信息（URL、请求头等）。
- `var` 包含请求连接的基本信息（IP、端口、请求时间戳等）。
- `route`、`service` 和 `consumer` 包含与 APISIX 中存储的相同数据，仅在这些对象上配置了 `opa` 插件时才会发送。

### OPA 向 APISIX 返回数据

下述示例展示了 OPA 服务对 APISIX 的响应数据格式：

```json
{
    "result": {
        "allow": true,
        "reason": "test",
        "headers": {
            "an": "header"
        },
        "status_code": 401
    }
}
```

各字段说明如下：

- `allow` 是必填字段，表示请求是否允许通过 APISIX 转发。
- `reason`、`headers` 和 `status_code` 是可选字段，仅在配置了自定义响应时返回。

## 使用示例

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
```

:::

在开始之前，您需要一个运行中的 OPA 服务器。可以通过 Docker 启动或部署到 Kubernetes：

<Tabs
groupId="opa-setup"
defaultValue="docker"
values={[
{label: 'Docker', value: 'docker'},
{label: 'Kubernetes', value: 'kubernetes'}
]}>

<TabItem value="docker">

```shell
docker run -d --name opa-server -p 8181:8181 openpolicyagent/opa:1.6.0 run --server --addr :8181 --log-level debug
```

验证 OPA 服务器安装正常且端口已正确暴露：

```shell
curl http://127.0.0.1:8181 | grep Version
```

您应该看到类似如下的响应：

```text
Version: 1.6.0
```

</TabItem>

<TabItem value="kubernetes">

在集群中创建 OPA 的 Deployment 和 Service：

```yaml title="opa-server.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: aic
  name: opa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: opa
  template:
    metadata:
      labels:
        app: opa
    spec:
      containers:
        - name: opa
          image: openpolicyagent/opa:1.6.0
          args:
            - run
            - --server
            - --addr=:8181
            - --log-level=debug
          ports:
            - containerPort: 8181
---
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: opa
spec:
  selector:
    app: opa
  ports:
    - port: 8181
      targetPort: 8181
```

将配置应用到集群：

```shell
kubectl apply -f opa-server.yaml
```

等待 OPA Pod 就绪。就绪后，OPA 服务器将在集群内通过 `http://opa.aic.svc.cluster.local:8181` 访问。如需从集群外部推送策略，请设置端口转发：

```shell
kubectl port-forward -n aic svc/opa 8181:8181 &
```

</TabItem>

</Tabs>

### 实现基本策略

以下示例在 OPA 中实现一个仅允许 GET 请求的基本授权策略。

创建一个仅允许 HTTP GET 请求的 OPA 策略：

```shell
curl "http://127.0.0.1:8181/v1/policies/getonly" -X PUT  \
  -H "Content-Type: text/plain" \
  -d '
package getonly

default allow = false

allow if {
    input.request.method == "GET"
}'
```

创建带有 `opa` 插件的 Route：

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
    "id": "opa-route",
    "uri": "/anything",
    "plugins": {
      "opa": {
        "host": "http://192.168.2.104:8181",
        "policy": "getonly"
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

将 `host` 替换为您的 OPA 服务器地址，`policy` 设置为 `getonly`。

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: opa-service
    routes:
      - name: opa-route
        uris:
          - /anything
        plugins:
          opa:
            host: "http://192.168.2.104:8181"
            policy: getonly
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

将 `host` 替换为您的 OPA 服务器地址，`policy` 设置为 `getonly`。

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

```yaml title="opa-ic.yaml"
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
  name: opa-plugin-config
spec:
  plugins:
    - name: opa
      config:
        host: "http://opa.aic.svc.cluster.local:8181"
        policy: getonly
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: opa-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: opa-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="opa-ic.yaml"
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
  name: opa-route
spec:
  ingressClassName: apisix
  http:
    - name: opa-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: opa
          enable: true
          config:
            host: "http://opa.aic.svc.cluster.local:8181"
            policy: getonly
```

将配置应用到集群：

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向 Route 发送 GET 请求以验证策略：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该收到 `HTTP/1.1 200 OK` 响应。

使用 PUT 方法向 Route 发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X PUT
```

您应该收到 `HTTP/1.1 403 Forbidden` 响应。

### 了解数据格式

以下示例帮助您了解 APISIX 推送给 OPA 的数据格式，以便编写授权逻辑。该示例基于[上一个示例](#实现基本策略)中的策略和 Route。

更新之前创建的 Route 上的插件，使其包含 Route 信息：

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
curl "http://127.0.0.1:9180/apisix/admin/routes/opa-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "opa": {
        "with_route": true
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

更新 `adc.yaml`，添加 `with_route: true`：

```yaml title="adc.yaml"
services:
  - name: opa-service
    routes:
      - name: opa-route
        uris:
          - /anything
        plugins:
          opa:
            host: "http://192.168.2.104:8181"
            policy: getonly
            with_route: true
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

更新 `opa-ic.yaml`，添加 `with_route: true`：

```yaml title="opa-ic.yaml"
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
  name: opa-plugin-config
spec:
  plugins:
    - name: opa
      config:
        host: "http://opa.aic.svc.cluster.local:8181"
        policy: getonly
        with_route: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: opa-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: opa-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将更新后的配置应用到集群：

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

更新 `opa-ic.yaml`，添加 `with_route: true`：

```yaml title="opa-ic.yaml"
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
  name: opa-route
spec:
  ingressClassName: apisix
  http:
    - name: opa-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: opa
          enable: true
          config:
            host: "http://opa.aic.svc.cluster.local:8181"
            policy: getonly
            with_route: true
```

将更新后的配置应用到集群：

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向 Route 发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

在 OPA 服务器日志（启用 `--log-level debug`）中，`req_body` 将在请求和变量字段之外还包含 Route 信息。

### 返回自定义响应

以下示例演示如何在请求未授权时返回自定义响应码和消息。

创建一个仅允许 HTTP GET 请求、并在未授权时返回 `302` 及自定义消息的 OPA 策略：

```shell
curl "http://127.0.0.1:8181/v1/policies/customresp" -X PUT \
  -H "Content-Type: text/plain" \
  -d '
package customresp

default allow = false

allow if {
  input.request.method == "GET"
}

reason := "The resource has temporarily moved. Please follow the new URL." if {
  not allow
}

headers := {
  "Location": "http://example.com/auth"
} if {
  not allow
}

status_code := 302 if {
  not allow
}
'
```

创建带有 `opa` 插件的 Route：

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
    "id": "opa-route",
    "uri": "/anything",
    "plugins": {
      "opa": {
        "host": "http://192.168.2.104:8181",
        "policy": "customresp"
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
  - name: opa-service
    routes:
      - name: opa-route
        uris:
          - /anything
        plugins:
          opa:
            host: "http://192.168.2.104:8181"
            policy: customresp
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

```yaml title="opa-ic.yaml"
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
  name: opa-customresp-plugin-config
spec:
  plugins:
    - name: opa
      config:
        host: "http://opa.aic.svc.cluster.local:8181"
        policy: customresp
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: opa-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: opa-customresp-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="opa-ic.yaml"
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
  name: opa-route
spec:
  ingressClassName: apisix
  http:
    - name: opa-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: opa
          enable: true
          config:
            host: "http://opa.aic.svc.cluster.local:8181"
            policy: customresp
```

将配置应用到集群：

```shell
kubectl apply -f opa-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向 Route 发送 GET 请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该收到 `HTTP/1.1 200 OK` 响应。

向 Route 发送 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST
```

您应该收到 `HTTP/1.1 302 Moved Temporarily` 响应：

```text
HTTP/1.1 302 Moved Temporarily
...
Location: http://example.com/auth

The resource has temporarily moved. Please follow the new URL.
```

### 实现 RBAC

以下示例演示如何结合 `jwt-auth` 和 `opa` 插件实现认证和 RBAC，其中：

* `user` 角色仅能读取 Upstream 资源。
* `admin` 角色可以读取和写入 Upstream 资源。

为示例 Consumer `john`（`user` 角色）和 `jane`（`admin` 角色）创建 OPA RBAC 策略：

```shell
curl "http://127.0.0.1:8181/v1/policies/rbac" -X PUT \
  -H "Content-Type: text/plain" \
  -d '
package rbac

# Assign roles to users
user_roles := {
  "john": ["user"],
  "jane": ["admin"]
}

# Map permissions to HTTP methods
permission_methods := {
  "read": "GET",
  "write": "POST"
}

# Assign role permissions
role_permissions := {
  "user": ["read"],
  "admin": ["read", "write"]
}

# Get JWT authorization token
bearer_token := t if {
  t := input.request.headers.authorization
}

# Decode the token to get role and permission
token := {"payload": payload} if {
  [_, payload, _] := io.jwt.decode(bearer_token)
}

# Normalize permission to a list
normalized_permissions := ps if {
  ps := token.payload.permission
  not is_string(ps)
}

normalized_permissions := [ps] if {
  ps := token.payload.permission
  is_string(ps)
}

# Implement RBAC logic
default allow = false

allow if {
  # Look up the list of roles for the user
  roles := user_roles[input.consumer.username]

  # For each role in that list
  r := roles[_]

  # Look up the permissions list for the role
  permissions := role_permissions[r]

  # For each permission
  p := permissions[_]

  # Check if the permission matches the request method
  permission_methods[p] == input.request.method

  # Check if the normalized permissions include the permission
  p in normalized_permissions
}
'
```

在 APISIX 中创建 Consumer `john` 和 `jane`，并配置 `jwt-auth` Credential：

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
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT -d '
{
  "username": "john"
}'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT -d '
{
  "username": "jane"
}'
```

为 Consumer 配置 `jwt-auth` Credential，使用默认算法 `HS256`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "john-key",
        "secret": "john-hs256-secret-that-is-very-long"
      }
    }
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jane/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-jwt-auth",
    "plugins": {
      "jwt-auth": {
        "key": "jane-key",
        "secret": "jane-hs256-secret-that-is-very-long"
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
consumers:
  - username: john
    credentials:
      - name: cred-john-jwt-auth
        type: jwt-auth
        config:
          key: john-key
          secret: john-hs256-secret-that-is-very-long
  - username: jane
    credentials:
      - name: cred-jane-jwt-auth
        type: jwt-auth
        config:
          key: jane-key
          secret: jane-hs256-secret-that-is-very-long
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

```yaml title="opa-consumers-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: john
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: jwt-auth
      name: cred-john-jwt-auth
      config:
        key: john-key
        secret: john-hs256-secret-that-is-very-long
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
    - type: jwt-auth
      name: cred-jane-jwt-auth
      config:
        key: jane-key
        secret: jane-hs256-secret-that-is-very-long
```

将配置应用到集群：

```shell
kubectl apply -f opa-consumers-ic.yaml
```

使用 Ingress Controller 时，APISIX 会在 Consumer 名称前加上 Kubernetes 命名空间前缀。例如，`aic` 命名空间中名为 `john` 的 Consumer 会变为 `aic_john`。请相应更新 OPA RBAC 策略中的用户名。

</TabItem>

<TabItem value="apisix-ingress-controller">

ApisixConsumer CRD 存在已知问题，`private_key` 在配置时被错误地设为必填项。该问题将在未来版本中修复。目前无法通过 APISIX CRD 完成此示例。

</TabItem>

</Tabs>

</TabItem>

</Tabs>

创建 Route 并配置 `jwt-auth` 和 `opa` 插件：

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
    "id": "opa-route",
    "methods": ["GET", "POST"],
    "uris": ["/get","/post"],
    "plugins": {
      "jwt-auth": {},
      "opa": {
        "host": "http://192.168.2.104:8181",
        "policy": "rbac",
        "with_consumer": true
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

更新 `adc.yaml`，添加带有 `jwt-auth` 和 `opa` 插件的 Route：

```yaml title="adc.yaml"
consumers:
  - username: john
    credentials:
      - name: cred-john-jwt-auth
        type: jwt-auth
        config:
          key: john-key
          secret: john-hs256-secret-that-is-very-long
  - username: jane
    credentials:
      - name: cred-jane-jwt-auth
        type: jwt-auth
        config:
          key: jane-key
          secret: jane-hs256-secret-that-is-very-long
services:
  - name: opa-service
    routes:
      - name: opa-route
        uris:
          - /get
          - /post
        methods:
          - GET
          - POST
        plugins:
          jwt-auth: {}
          opa:
            host: "http://192.168.2.104:8181"
            policy: rbac
            with_consumer: true
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

```yaml title="opa-route-ic.yaml"
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
  name: opa-rbac-plugin-config
spec:
  plugins:
    - name: jwt-auth
      config:
        _meta:
          disable: false
    - name: opa
      config:
        host: "http://opa.aic.svc.cluster.local:8181"
        policy: rbac
        with_consumer: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: opa-rbac-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
          method: GET
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: opa-rbac-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
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
            name: opa-rbac-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f opa-route-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

ApisixConsumer CRD 存在已知问题，`private_key` 在配置时被错误地设为必填项。该问题将在未来版本中修复。目前无法通过 APISIX CRD 完成此示例。

</TabItem>

</Tabs>

</TabItem>

</Tabs>

#### 以 `john` 身份验证

要为 `john` 生成 JWT，可使用 [JWT.io 的 JWT 编码器](https://jwt.io) 或其他工具。若使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下操作：

* 将算法填写为 `HS256`。
* 将 **Valid secret** 部分的密钥更新为 `john-hs256-secret-that-is-very-long`。
* 在 payload 中填入角色 `user`、权限 `read`、Consumer key `john-key`，以及 UNIX 时间戳格式的 `exp` 或 `nbf`。

您的 payload 应类似如下：

```json
{
  "role": "user",
  "permission": "read",
  "key": "john-key",
  "nbf": 1729132271
}
```

复制生成的 JWT 并存入变量：

```text
export john_jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidXNlciIsInBlcm1pc3Npb24iOiJyZWFkIiwia2V5Ijoiam9obi1rZXkiLCJuYmYiOjE3MjkxMzIyNzF9.rAHMTQfnnGFnKYc3am_lpE9pZ9E8EaOT_NBQ5Ss8pk4
```

使用 `john` 的 JWT 向 Route 发送 GET 请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${john_jwt_token}"
```

您应该收到 `HTTP/1.1 200 OK` 响应。

使用相同 JWT 向 Route 发送 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST -H "Authorization: ${john_jwt_token}"
```

您应该收到 `HTTP/1.1 403 Forbidden` 响应。

#### 以 `jane` 身份验证

同样地，为 `jane` 生成 JWT，可使用 [JWT.io 的 JWT 编码器](https://jwt.io) 或其他工具。若使用 [JWT.io 的 JWT 编码器](https://jwt.io)，请执行以下操作：

* 将算法填写为 `HS256`。
* 将 **Valid secret** 部分的密钥更新为 `jane-hs256-secret-that-is-very-long`。
* 在 payload 中填入角色 `admin`、权限 `["read","write"]`、Consumer key `jane-key`，以及 UNIX 时间戳格式的 `exp` 或 `nbf`。

您的 payload 应类似如下：

```json
{
  "role": "admin",
  "permission": ["read","write"],
  "key": "jane-key",
  "nbf": 1729132271
}
```

复制生成的 JWT 并存入变量：

```text
export jane_jwt_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYWRtaW4iLCJwZXJtaXNzaW9uIjpbInJlYWQiLCJ3cml0ZSJdLCJrZXkiOiJqYW5lLWtleSIsIm5iZiI6MTcyOTEzMjI3MX0.meZ-AaGHUPwN_GvVOE3IkKuAJ1wqlCguaXf3gm3Ww8s
```

使用 `jane` 的 JWT 向 Route 发送 GET 请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "Authorization: ${jane_jwt_token}"
```

您应该收到 `HTTP/1.1 200 OK` 响应。

使用相同 JWT 向 Route 发送 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST -H "Authorization: ${jane_jwt_token}"
```

您也应该收到 `HTTP/1.1 200 OK` 响应。
