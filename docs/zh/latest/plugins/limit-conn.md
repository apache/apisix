---
title: limit-conn
keywords:
  - APISIX
  - API 网关
  - Limit Connection
description: limit-conn 插件通过管理并发连接来限制请求速率。超过阈值的请求可能会被延迟或拒绝，以确保 API 使用受控并防止过载。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/limit-conn" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`limit-conn` 插件通过并发连接数来限制请求速率。超过阈值的请求将根据配置被延迟或拒绝，从而确保可控的资源使用并防止过载。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| conn | integer 或 string | 否 | | 整数时 > 0；或变量表达式 | 允许的最大并发请求数。超过配置的限制且低于 `conn + burst` 的请求将被延迟。如果未配置 `rules`，则为必填项。支持直接填写整数，或填写变量表达式（例如 `$arg_conn`），变量会在运行时解析。|
| burst | integer 或 string | 否 | | 整数时 >= 0；或变量表达式 | 允许延迟的过多并发请求数。超过 `conn + burst` 的请求将被立即拒绝。如果未配置 `rules`，则为必填项。支持直接填写整数，或填写变量表达式（例如 `$arg_burst`），变量会在运行时解析。|
| default_conn_delay | number | 是 | | > 0 | 允许超过 `conn` 且不超过 `conn + burst` 的并发请求的处理延迟（秒），可根据 `only_use_default_delay` 设置动态调整。|
| only_use_default_delay | boolean | 否 | false | | 如果为 false，则根据请求超出 `conn` 限制的程度按比例延迟请求。拥塞越严重，延迟就越大。例如，当 `conn` 为 `5`、`burst` 为 `3` 且 `default_conn_delay` 为 `1` 时，6 个并发请求将导致 1 秒的延迟，7 个请求将导致 2 秒的延迟，8 个请求将导致 3 秒的延迟，依此类推，直到达到 `conn + burst` 的总限制，超过此限制的请求将被拒绝。如果为 true，则使用 `default_conn_delay` 延迟 `burst` 范围内的所有超额请求。超出 `conn + burst` 的请求将被立即拒绝。例如，当 `conn` 为 `5`、`burst` 为 `3` 且 `default_conn_delay` 为 `1` 时，6、7 或 8 个并发请求都将延迟 1 秒。|
| key_type | string | 否 | var | [`var`, `var_combination`] | key 的类型。如果 `key_type` 为 `var`，则 `key` 将被解释为变量。如果 `key_type` 为 `var_combination`，则 `key` 将被解释为变量的组合。|
| key | string | 否 | remote_addr | | 用于计数请求的 key。如果 `key_type` 为 `var`，则 `key` 将被解释为变量。变量不需要以美元符号（`$`）为前缀。如果 `key_type` 为 `var_combination`，则 `key` 会被解释为变量的组合。所有变量都应该以美元符号（`$`）为前缀。例如，要配置 `key` 使用两个请求头 `custom-a` 和 `custom-b` 的组合，则 `key` 应该配置为 `$http_custom_a $http_custom_b`。如果未配置 `rules`，则为必填项。|
| rejected_code | integer | 否 | 503 | [200, ..., 599] | 请求因超出阈值而被拒绝时返回的 HTTP 状态码。|
| rejected_msg | string | 否 | | 非空 | 请求因超出阈值而被拒绝时返回的响应主体。|
| allow_degradation | boolean | 否 | false | | 如果为 true，则允许 APISIX 在插件或其依赖项不可用时继续处理没有插件的请求。|
| policy | string | 否 | local | [`local`, `redis`, `redis-cluster`] | 速率限制计数器的策略。如果是 `local`，则计数器存储在本地内存中。如果是 `redis`，则计数器存储在 Redis 实例上。如果是 `redis-cluster`，则计数器存储在 Redis 集群中。|
| redis_host | string | 否 | | | Redis 节点的地址。当 `policy` 为 `redis` 时必填。|
| redis_port | integer | 否 | 6379 | >= 1 | 当 `policy` 为 `redis` 时，Redis 节点的端口。|
| redis_username | string | 否 | | | 如果使用 Redis ACL，则为 Redis 的用户名。如果使用旧式身份验证方法 `requirepass`，则仅配置 `redis_password`。当 `policy` 为 `redis` 时使用。|
| redis_password | string | 否 | | | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 节点的密码。|
| redis_ssl | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis` 时使用 SSL 连接到 Redis。|
| redis_ssl_verify | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis` 时验证服务器 SSL 证书。|
| redis_database | integer | 否 | 0 | >= 0 | 当 `policy` 为 `redis` 时，Redis 中的数据库编号。|
| redis_timeout | integer | 否 | 1000 | >= 1 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 超时值（以毫秒为单位）。|
| redis_keepalive_timeout | integer | 否 | 10000 | >= 1000 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 的空闲连接超时时间（以毫秒为单位）。|
| redis_keepalive_pool | integer | 否 | 100 | >= 1 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 的连接池最大连接数。|
| key_ttl | integer | 否 | 3600 | | Redis 键的 TTL（以秒为单位）。当 `policy` 为 `redis` 或 `redis-cluster` 时使用。|
| redis_cluster_nodes | array[string] | 否 | | | 至少包含一个地址的 Redis 集群节点列表。当 `policy` 为 `redis-cluster` 时必填。|
| redis_cluster_name | string | 否 | | | Redis 集群的名称。当 `policy` 为 `redis-cluster` 时必填。|
| redis_cluster_ssl | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis-cluster` 时使用 SSL 连接到 Redis 集群。|
| redis_cluster_ssl_verify | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis-cluster` 时验证服务器 SSL 证书。|
| rules | array[object] | 否 | | | 按顺序应用的速率限制规则数组。从 APISIX 3.16.0 起可用。你应配置以下参数集之一，但不能同时配置两者：`conn`、`burst`、`default_conn_delay`、`key` 或 `rules`、`default_conn_delay`。|
| rules.conn | integer 或 string | 是 | | > 0 或变量表达式 | 允许的最大并发请求数。超过配置的限制且低于 `conn + burst` 的请求将被延迟。该参数也支持 string 数据类型，并允许使用以美元符号（`$`）为前缀的内置变量。|
| rules.burst | integer 或 string | 是 | | >= 0 或变量表达式 | 允许延迟的过多并发请求数。超过 `conn + burst` 的请求将被立即拒绝。该参数也支持 string 数据类型，并允许使用以美元符号（`$`）为前缀的内置变量。|
| rules.key | string | 是 | | | 用于计数请求的键。如果配置的键不存在，则不会执行该规则。`key` 被解释为变量的组合。所有变量都应以美元符号（`$`）为前缀。|

## 示例

以下示例演示了如何在不同场景中配置 `limit-conn`。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 通过远程地址应用速率限制

以下示例演示如何使用 `limit-conn` 通过 `remote_addr` 限制请求速率，并附带示例连接和突发阈值。

创建一个带有 `limit-conn` 插件的路由：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "conn": 2,
        "burst": 1,
        "default_conn_delay": 0.1,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "local",
        "rejected_code": 429
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
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - uris:
          - /get
        name: limit-conn-route
        plugins:
          limit-conn:
            conn: 2
            burst: 1
            default_conn_delay: 0.1
            key_type: var
            key: remote_addr
            policy: local
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-plugin-config
spec:
  plugins:
    - name: limit-conn
      config:
        conn: 2
        burst: 1
        default_conn_delay: 0.1
        key_type: var
        key: remote_addr
        policy: local
        rejected_code: 429
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-conn-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: limit-conn-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-conn-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: limit-conn
          config:
            conn: 2
            burst: 1
            default_conn_delay: 0.1
            key_type: var
            key: remote_addr
            policy: local
            rejected_code: 429
```

</TabItem>
</Tabs>

应用配置：

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ `conn`：允许 2 个并发请求。

❷ `burst`：允许 1 个过多的并发请求。

❸ `default_conn_delay`：允许超过 `conn` 和 `conn + burst` 之间的并发请求有 0.1 秒的处理延迟。

❹ `key_type`：设置为 `var`，将 `key` 解释为变量。

❺ `key`：根据请求的 `remote_addr` 计算速率限制计数。

❻ `policy`：使用内存中的本地计数器。

❼ `rejected_code`：将拒绝状态码设置为 `429`。

向路由发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

你应该会看到类似以下内容的响应，其中超过阈值的请求被拒绝：

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

### 通过远程地址和消费者名称应用速率限制

以下示例演示如何使用 `limit-conn` 通过变量组合 `remote_addr` 和 `consumer_name` 对请求进行速率限制。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

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

创建一个带有 `key-auth` 和 `limit-conn` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "limit-conn": {
        "conn": 2,
        "burst": 1,
        "default_conn_delay": 0.1,
        "rejected_code": 429,
        "policy": "local",
        "key_type": "var_combination",
        "key": "$remote_addr $consumer_name"
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
<TabItem value="adc" label="ADC">

创建两个消费者和一个按消费者进行速率限制的路由：

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
services:
  - name: limit-conn-service
    routes:
      - name: limit-conn-route
        uris:
          - /get
        plugins:
          key-auth: {}
          limit-conn:
            conn: 2
            burst: 1
            default_conn_delay: 0.1
            rejected_code: 429
            policy: local
            key_type: var_combination
            key: "$remote_addr $consumer_name"
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
<TabItem value="ingress" label="Ingress Controller">

创建两个消费者和一个按消费者进行速率限制的路由：

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: limit-conn
      config:
        conn: 2
        burst: 1
        default_conn_delay: 0.1
        rejected_code: 429
        policy: local
        key_type: var_combination
        key: "$remote_addr $consumer_name"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-conn-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: limit-conn-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-conn-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: key-auth
          config:
            _meta:
              disable: false
        - name: limit-conn
          config:
            conn: 2
            burst: 1
            default_conn_delay: 0.1
            rejected_code: 429
            policy: local
            key_type: var_combination
            key: "$remote_addr $consumer_name"
```

</TabItem>
</Tabs>

应用配置：

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ `key-auth`：在路由上启用 key 认证。

❷ `key_type`：设置为 `var_combination`，将 `key` 解释为变量的组合。

❸ `key`：设置为 `$remote_addr $consumer_name`，按远程地址和消费者应用速率限制配额。

以消费者 `john` 的身份发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "apikey: john-key"'
```

你应该会看到类似以下内容的响应，其中超过阈值的请求被拒绝：

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

接下来立刻以消费者 `jane` 的身份发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "apikey: jane-key"'
```

你还应该看到类似以下内容的响应，其中过多的请求被拒绝：

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

在此示例中，该插件按变量组合 `remote_addr` 和 `consumer_name` 进行速率限制，这意味着每个消费者的配额是独立的。

### 限制 WebSocket 连接速率

以下示例演示了如何使用 `limit-conn` 插件来限制并发 WebSocket 连接的数量。

启动一个[示例上游 WebSocket 服务器](https://hub.docker.com/r/jmalloc/echo-server)：

```shell
docker run -d \
  -p 8080:8080 \
  --name websocket-server \
  --network=apisix-quickstart-net \
  jmalloc/echo-server
```

该服务器在 `/.ws` 路径上有一个 WebSocket 端点，会回显收到的任何消息。

创建到服务器 WebSocket 端点的路由，并为路由启用 WebSocket：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ws-route",
    "uri": "/.ws",
    "plugins": {
      "limit-conn": {
        "conn": 2,
        "burst": 1,
        "default_conn_delay": 0.1,
        "key_type": "var",
        "key": "remote_addr",
        "rejected_code": 429,
        "policy": "local"
      }
    },
    "enable_websocket": true,
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "websocket-server:8080": 1
      }
    }
  }'
```

❶ 为路由启用 WebSocket。

❷ 替换为你的 WebSocket 服务器地址。

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: websocket-service
    routes:
      - name: ws-route
        uris:
          - /.ws
        enable_websocket: true
        plugins:
          limit-conn:
            conn: 2
            burst: 1
            default_conn_delay: 0.1
            key_type: var
            key: remote_addr
            rejected_code: 429
            policy: local
    upstream:
      type: roundrobin
      nodes:
        - host: websocket-server
          port: 8080
          weight: 1
```

❶ 为路由启用 WebSocket。

❷ 替换为你的 WebSocket 服务器地址。

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="limit-conn-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: limit-conn-plugin-config
spec:
  plugins:
    - name: limit-conn
      config:
        conn: 2
        burst: 1
        default_conn_delay: 0.1
        key_type: var
        key: remote_addr
        rejected_code: 429
        policy: local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ws-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /.ws
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: limit-conn-plugin-config
      backendRefs:
        - name: websocket-server
          port: 8080
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="limit-conn-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ws-route
spec:
  ingressClassName: apisix
  http:
    - name: ws-route
      match:
        paths:
          - /.ws
        methods:
          - GET
      websocket: true
      backends:
        - serviceName: websocket-server
          servicePort: 8080
      plugins:
        - name: limit-conn
          config:
            conn: 2
            burst: 1
            default_conn_delay: 0.1
            key_type: var
            key: remote_addr
            rejected_code: 429
            policy: local
```

</TabItem>
</Tabs>

应用配置：

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

安装 WebSocket 客户端，例如 [websocat](https://github.com/vi/websocat)（如果尚未安装）。通过路由与 WebSocket 服务器建立连接：

```shell
websocat "ws://127.0.0.1:9080/.ws"
```

在终端中发送 "hello" 消息，你应该会看到 WebSocket 服务器回显相同的消息：

```text
Request served by 1cd244052136
hello
hello
```

再打开三个终端会话并运行：

```shell
websocat "ws://127.0.0.1:9080/.ws"
```

由于速率限制的影响，当你尝试与服务器建立 WebSocket 连接时，你应该会看到最后一个终端会话打印 `429 Too Many Requests`。

### 使用 Redis 服务器在 APISIX 节点之间共享配额

以下示例演示了使用 Redis 服务器对多个 APISIX 节点之间的请求进行速率限制，以便不同的 APISIX 节点共享相同的速率限制配额。

在每个 APISIX 实例上，使用以下配置创建路由。请相应地调整配置详情。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "conn": 1,
        "burst": 1,
        "default_conn_delay": 0.1,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "redis",
        "redis_host": "192.168.xxx.xxx",
        "redis_port": 6379,
        "redis_password": "p@ssw0rd",
        "redis_database": 1
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
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - uris:
          - /get
        name: limit-conn-route
        plugins:
          limit-conn:
            conn: 1
            burst: 1
            default_conn_delay: 0.1
            rejected_code: 429
            key_type: var
            key: remote_addr
            policy: redis
            redis_host: "192.168.xxx.xxx"
            redis_port: 6379
            redis_password: "p@ssw0rd"
            redis_database: 1
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-plugin-config
spec:
  plugins:
    - name: limit-conn
      config:
        conn: 1
        burst: 1
        default_conn_delay: 0.1
        rejected_code: 429
        key_type: var
        key: remote_addr
        policy: redis
        redis_host: "redis-service.aic.svc"
        redis_port: 6379
        redis_password: "p@ssw0rd"
        redis_database: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-conn-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: limit-conn-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-conn-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: limit-conn
          config:
            conn: 1
            burst: 1
            default_conn_delay: 0.1
            rejected_code: 429
            key_type: var
            key: remote_addr
            policy: redis
            redis_host: "redis-service.aic.svc"
            redis_port: 6379
            redis_password: "p@ssw0rd"
            redis_database: 1
```

</TabItem>
</Tabs>

应用配置：

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ `policy`：设置为 `redis`，使用 Redis 实例进行速率限制。

❷ `redis_host`：设置为 Redis 实例的 IP 地址。

❸ `redis_port`：设置为 Redis 实例的监听端口。

❹ `redis_password`：设置为 Redis 实例的密码（如有）。

❺ `redis_database`：设置为 Redis 实例中的数据库编号。

向路由发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

你应该会看到类似以下内容的响应，其中超过阈值的请求被拒绝：

```text
Response: 200
Response: 200
Response: 429
Response: 429
Response: 429
```

这表明在不同 APISIX 实例中配置的两个路由共享相同的配额。

### 使用 Redis 集群在 APISIX 节点之间共享配额

你还可以使用 Redis 集群在多个 APISIX 节点之间应用相同的配额，以便不同的 APISIX 节点共享相同的速率限制配额。

确保你的 Redis 实例在[集群模式](https://redis.io/docs/management/scaling/#create-and-use-a-redis-cluster)下运行。为 `limit-conn` 插件配置 `redis_cluster_name` 和 `redis_cluster_nodes` 中的一个或多个节点地址。

在每个 APISIX 实例上，使用以下配置创建路由。请相应地调整配置详情。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "conn": 1,
        "burst": 1,
        "default_conn_delay": 0.1,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "redis-cluster",
        "redis_cluster_nodes": [
          "192.168.xxx.xxx:6379",
          "192.168.xxx.xxx:16379"
        ],
        "redis_password": "p@ssw0rd",
        "redis_cluster_name": "redis-cluster",
        "redis_cluster_ssl": true
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
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - uris:
          - /get
        name: limit-conn-route
        plugins:
          limit-conn:
            conn: 1
            burst: 1
            default_conn_delay: 0.1
            rejected_code: 429
            key_type: var
            key: remote_addr
            policy: redis-cluster
            redis_cluster_nodes:
              - "192.168.xxx.xxx:6379"
              - "192.168.xxx.xxx:16379"
            redis_password: "p@ssw0rd"
            redis_cluster_name: "redis-cluster"
            redis_cluster_ssl: true
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-plugin-config
spec:
  plugins:
    - name: limit-conn
      config:
        conn: 1
        burst: 1
        default_conn_delay: 0.1
        rejected_code: 429
        key_type: var
        key: remote_addr
        policy: redis-cluster
        redis_cluster_nodes:
          - "redis-cluster-0.redis-cluster.aic.svc:6379"
          - "redis-cluster-1.redis-cluster.aic.svc:6379"
        redis_password: "p@ssw0rd"
        redis_cluster_name: "redis-cluster"
        redis_cluster_ssl: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-conn-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: limit-conn-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-conn-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: limit-conn
          config:
            conn: 1
            burst: 1
            default_conn_delay: 0.1
            rejected_code: 429
            key_type: var
            key: remote_addr
            policy: redis-cluster
            redis_cluster_nodes:
              - "redis-cluster-0.redis-cluster.aic.svc:6379"
              - "redis-cluster-1.redis-cluster.aic.svc:6379"
            redis_password: "p@ssw0rd"
            redis_cluster_name: "redis-cluster"
            redis_cluster_ssl: true
```

</TabItem>
</Tabs>

应用配置：

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ `policy`：设置为 `redis-cluster`，使用 Redis 集群进行速率限制。

❷ `redis_cluster_nodes`：设置为 Redis 集群中的 Redis 节点地址。

❸ `redis_password`：设置为 Redis 集群的密码（如有）。

❹ `redis_cluster_name`：设置为 Redis 集群名称。

❺ `redis_cluster_ssl`：启用与 Redis 集群的 SSL/TLS 通信。

向路由发送五个并发请求：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

你应该会看到类似以下内容的响应，其中超过阈值的请求被拒绝：

```text
Response: 200
Response: 200
Response: 429
Response: 429
Response: 429
```

这表明在不同 APISIX 实例中配置的两个路由共享相同的配额。

### 按规则进行速率限制

以下示例演示了如何配置 `limit-conn`，根据请求属性应用不同的速率限制规则。此功能从 APISIX 3.16.0 起可用。在此示例中，根据代表调用者访问层级的 HTTP 标头值应用速率限制。

请注意，所有规则按顺序应用。如果配置的键不存在，则对应的规则将被跳过。

除了 HTTP 标头外，你还可以基于其他内置变量或 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)来实现更灵活和细粒度的速率限制策略。

创建一个带有 `limit-conn` 插件的路由，根据请求标头应用不同的速率限制，允许按订阅（`X-Subscription-ID`）进行速率限制，并对试用用户（`X-Trial-ID`）实施更严格的限制：

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-rules-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "rejected_code": 429,
        "default_conn_delay": 0.1,
        "policy": "local",
        "rules": [
          {
            "key": "${http_x_subscription_id}",
            "conn": "${http_x_custom_conn ?? 5}",
            "burst": 1
          },
          {
            "key": "${http_x_trial_id}",
            "conn": 1,
            "burst": 1
          }
        ]
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
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - uris:
          - /get
        name: limit-conn-rules-route
        plugins:
          limit-conn:
            rejected_code: 429
            default_conn_delay: 0.1
            policy: local
            rules:
              - key: "${http_x_subscription_id}"
                conn: "${http_x_custom_conn ?? 5}"
                burst: 1
              - key: "${http_x_trial_id}"
                conn: 1
                burst: 1
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-plugin-config
spec:
  plugins:
    - name: limit-conn
      config:
        rejected_code: 429
        default_conn_delay: 0.1
        policy: local
        rules:
          - key: "${http_x_subscription_id}"
            conn: "${http_x_custom_conn ?? 5}"
            burst: 1
          - key: "${http_x_trial_id}"
            conn: 1
            burst: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-conn-rules-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: limit-conn-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="limit-conn-ic.yaml"
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
  name: limit-conn-rules-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-conn-rules-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: limit-conn
          config:
            rejected_code: 429
            default_conn_delay: 0.1
            policy: local
            rules:
              - key: "${http_x_subscription_id}"
                conn: "${http_x_custom_conn ?? 5}"
                burst: 1
              - key: "${http_x_trial_id}"
                conn: 1
                burst: 1
```

</TabItem>
</Tabs>

应用配置：

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ 使用 `X-Subscription-ID` 请求标头的值作为速率限制键。

❷ 根据 `X-Custom-Conn` 标头动态设置请求连接数。如果未提供该标头，则应用默认的并发连接数 5。

❸ 使用 `X-Trial-ID` 请求标头的值作为速率限制键。

要验证速率限制，向路由发送 7 个并发请求，使用相同的订阅 ID：

```shell
seq 1 7 | xargs -n1 -P7 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "X-Subscription-ID: sub-123456789"'
```

你应该会看到以下响应，表明在未提供 `X-Custom-Conn` 标头时，应用了默认的并发连接限制 5 和突发值 1：

```text
Response: 429
Response: 200
Response: 200
Response: 200
Response: 200
Response: 200
Response: 200
```

向路由发送 5 个并发请求，使用相同的订阅 ID 并将 `X-Custom-Conn` 标头设置为 1：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "X-Subscription-ID: sub-123456789" -H "X-Custom-Conn: 1"'
```

你应该会看到以下响应，表明应用了并发连接限制 1 和突发值 1：

```text
Response: 429
Response: 429
Response: 429
Response: 200
Response: 200
```

最后，向路由发送 5 个请求，附带试用 ID 标头：

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "X-Trial-ID: trial-123456789"'
```

你应该会看到以下响应，表明应用了并发连接限制 1 和突发值 1：

```text
Response: 429
Response: 429
Response: 429
Response: 200
Response: 200
```
