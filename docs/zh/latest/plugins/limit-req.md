---
title: limit-req
keywords:
  - APISIX
  - API 网关
  - Limit Request
  - 速率限制
description: limit-req 插件使用漏桶算法来限制请求的数量并允许节流。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/limit-req" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`limit-req` 插件使用[漏桶](https://en.wikipedia.org/wiki/Leaky_bucket)算法来限制请求的数量并允许节流。

## 本地 vs Redis 速率限制

`limit-req` 插件支持两种速率限制模式：

* **本地速率限制**：限制在每个网关实例上独立执行。每个实例维护自己的计数器，因此当流量分布在多个实例之间时，有效限制大约为（限制 × 实例数量）。当未设置 `policy` 或 `policy` 为 `local` 时，这是默认模式。
* **基于 Redis 的速率限制**：限制通过 Redis 在所有网关实例之间共享。所有实例共享相同的配额，因此配置的限制适用于所有网关实例。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|----------|---------|--------------|-------------|
| rate | number | 是 | | > 0 | 每秒允许的最大请求数。超过速率且低于突发的请求将被延迟。|
| burst | number | 是 | | >= 0 | 每秒允许延迟的请求数，以进行节流。超过速率和突发的请求将被拒绝。|
| key_type | string | 否 | var | ["var", "var_combination"] | key 的类型。如果 `key_type` 为 `var`，则 `key` 将被解释为变量。如果 `key_type` 为 `var_combination`，则 `key` 将被解释为变量的组合。|
| key | string | 是 | | | 用于计数请求的 key。如果 `key_type` 为 `var`，则 `key` 将被解释为变量。变量不需要以美元符号（`$`）为前缀。如果 `key_type` 为 `var_combination`，则 `key` 会被解释为变量的组合。所有变量都应该以美元符号（`$`）为前缀。例如，要配置 `key` 使用两个请求头 `custom-a` 和 `custom-b` 的组合，则 `key` 应该配置为 `$http_custom_a $http_custom_b`。|
| rejected_code | integer | 否 | 503 | [200,...,599] | 请求因超出阈值而被拒绝时返回的 HTTP 状态代码。|
| rejected_msg | string | 否 | | 非空 | 请求因超出阈值而被拒绝时返回的响应主体。|
| nodelay | boolean | 否 | false | | 如果为 true，则不延迟突发阈值内的请求。|
| allow_degradation | boolean | 否 | false | | 如果为 true，则允许 APISIX 在插件或其依赖项不可用时继续处理没有插件的请求。|
| policy | string | 否 | local | ["local", "redis", "redis-cluster"] | 速率限制计数器的策略。如果是 `local`，则计数器存储在本地内存中。如果是 `redis`，则计数器存储在 Redis 实例上。如果是 `redis-cluster`，则计数器存储在 Redis 集群中。|
| redis_host | string | 否 | | | Redis 节点的地址。当 `policy` 为 `redis` 时必填。|
| redis_port | integer | 否 | 6379 | [1,...] | 当 `policy` 为 `redis` 时，Redis 节点的端口。|
| redis_username | string | 否 | | | 如果使用 Redis ACL，则为 Redis 的用户名。如果使用旧式身份验证方法 `requirepass`，则仅配置 `redis_password`。当 `policy` 为 `redis` 时使用。|
| redis_password | string | 否 | | | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 节点的密码。|
| redis_ssl | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis` 时使用 SSL 连接到 Redis。|
| redis_ssl_verify | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis` 时验证服务器 SSL 证书。|
| redis_database | integer | 否 | 0 | >= 0 | 当 `policy` 为 `redis` 时，Redis 中的数据库编号。|
| redis_timeout | integer | 否 | 1000 | [1,...] | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 超时值（以毫秒为单位）。|
| redis_keepalive_timeout | integer | 否 | 10000 | ≥ 1000 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，与 Redis 的空闲连接超时时间，单位为毫秒。|
| redis_keepalive_pool | integer | 否 | 100 | ≥ 1 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，与 Redis 的连接池最大连接数。|
| redis_cluster_nodes | array[string] | 否 | | | 具有至少一个地址的 Redis 集群节点列表。当 policy 为 redis-cluster 时必填。|
| redis_cluster_name | string | 否 | | | Redis 集群的名称。当 `policy` 为 `redis-cluster` 时必须使用。|
| redis_cluster_ssl | boolean | 否 | false | | 如果为 `true`，当 `policy` 为 `redis-cluster` 时，使用 SSL 连接 Redis 集群。|
| redis_cluster_ssl_verify | boolean | 否 | false | | 如果为 `true`，当 `policy` 为 `redis-cluster` 时，验证服务器 SSL 证书。|

## 示例

以下示例演示了如何在不同场景中配置 `limit-req`。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 按远程地址应用速率限制

以下示例演示了通过单个变量 `remote_addr` 对 HTTP 请求进行速率限制。

使用 `limit-req` 插件创建允许每个远程地址 1 QPS 的路由：

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
  -d '
  {
    "id": "limit-req-route",
    "uri": "/get",
    "plugins": {
      "limit-req": {
        "rate": 1,
        "burst": 0,
        "key": "remote_addr",
        "key_type": "var",
        "rejected_code": 429,
        "policy": "local",
        "nodelay": true
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
  - name: httpbin
    routes:
      - uris:
          - /get
        name: limit-req-route
        plugins:
          limit-req:
            rate: 1
            burst: 0
            key: remote_addr
            key_type: var
            rejected_code: 429
            policy: local
            nodelay: true
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

```yaml title="limit-req-ic.yaml"
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
  name: limit-req-plugin-config
spec:
  plugins:
    - name: limit-req
      config:
        rate: 1
        burst: 0
        key: remote_addr
        key_type: var
        rejected_code: 429
        policy: local
        nodelay: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-req-route
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
            name: limit-req-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="limit-req-ic.yaml"
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
  name: limit-req-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-req-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: limit-req
          config:
            rate: 1
            burst: 0
            key: remote_addr
            key_type: var
            rejected_code: 429
            policy: local
            nodelay: true
```

</TabItem>

</Tabs>

应用配置：

```shell
kubectl apply -f limit-req-ic.yaml
```

</TabItem>

</Tabs>

❶ `rate`：将 QPS 限制为 1。

❷ `key`：设置为 `remote_addr`，以按远程地址应用速率限制配额。

❸ `key_type`：设置为 `var`，以将 `key` 解释为变量。

发送请求以验证：

```shell
curl -i "http://127.0.0.1:9080/get"
```

你应该会看到一个 `HTTP/1.1 200 OK` 响应。

该请求已消耗了时间窗口允许的所有配额。如果你在同一秒内再次发送请求，你应该会收到 `HTTP/1.1 429 Too Many Requests` 响应，表示请求超出了配额阈值。

### 实现 API 节流

以下示例演示了如何配置 `burst` 以允许超出配置值的速率限制阈值并实现请求节流。你还将看到与未实施节流时的比较。

使用 `limit-req` 插件创建一个路由，允许每个远程地址 1 QPS，并将 `burst` 设置为 1，以允许 1 个超过 `rate` 的请求延迟处理：

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
    "id": "limit-req-route",
    "uri": "/get",
    "plugins": {
      "limit-req": {
        "rate": 1,
        "burst": 1,
        "key": "remote_addr",
        "rejected_code": 429,
        "policy": "local"
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
  - name: httpbin
    routes:
      - uris:
          - /get
        name: limit-req-route
        plugins:
          limit-req:
            rate: 1
            burst: 1
            key: remote_addr
            rejected_code: 429
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

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="limit-req-ic.yaml"
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
  name: limit-req-plugin-config
spec:
  plugins:
    - name: limit-req
      config:
        rate: 1
        burst: 1
        key: remote_addr
        rejected_code: 429
        policy: local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-req-route
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
            name: limit-req-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="limit-req-ic.yaml"
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
  name: limit-req-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-req-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: limit-req
          config:
            rate: 1
            burst: 1
            key: remote_addr
            rejected_code: 429
            policy: local
```

</TabItem>

</Tabs>

应用配置：

```shell
kubectl apply -f limit-req-ic.yaml
```

</TabItem>

</Tabs>

❶ `burst`：允许 1 个超过 `rate` 的请求延迟处理。

生成三个对路由的请求：

```shell
resp=$(seq 3 | xargs -I{} curl -i "http://127.0.0.1:9080/get" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200 responses: $count_200 ; 429 responses: $count_429"
```

你可能会看到所有三个请求都成功：

```text
200 responses: 3 ; 429 responses: 0
```

要查看没有 `burst` 的效果，请将 `burst` 更新为 0 或将 `nodelay` 设置为 `true`，如下所示：

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
curl "http://127.0.0.1:9180/apisix/admin/routes/limit-req-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "limit-req": {
        "nodelay": true
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

使用 `nodelay: true` 更新 ADC YAML：

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - uris:
          - /get
        name: limit-req-route
        plugins:
          limit-req:
            rate: 1
            burst: 1  # alternatively, set burst to 0
            key: remote_addr
            rejected_code: 429
            policy: local
            nodelay: true
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

使用更新的插件设置同步配置：

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

更新 manifest 文件如下：

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="limit-req-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: limit-req-plugin-config
spec:
  plugins:
    - name: limit-req
      config:
        rate: 1
        burst: 1  # alternatively, set burst to 0
        key: remote_addr
        rejected_code: 429
        policy: local
        nodelay: true
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="limit-req-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: limit-req-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-req-route
      match:
        paths:
          - /get
        methods:
          - GET
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: limit-req
          config:
            rate: 1
            burst: 1  # alternatively, set burst to 0
            key: remote_addr
            rejected_code: 429
            policy: local
            nodelay: true
```

</TabItem>

</Tabs>

应用更新的配置：

```shell
kubectl apply -f limit-req-ic.yaml
```

</TabItem>

</Tabs>

再次向路由生成三个请求：

```shell
resp=$(seq 3 | xargs -I{} curl -i "http://127.0.0.1:9080/get" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200 responses: $count_200 ; 429 responses: $count_429"
```

你应该会看到类似以下内容的响应，表明超出速率的请求已被拒绝：

```text
200 responses: 1 ; 429 responses: 2
```

### 按远程地址和消费者名称应用速率限制

以下示例演示了通过变量组合 `remote_addr` 和 `consumer_name` 来限制请求的速率。

使用 `limit-req` 插件创建一个路由，允许每个远程地址和每个消费者有 1 QPS。

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

创建一个带有 `key-auth` 和 `limit-req` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-req-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "limit-req": {
        "rate": 1,
        "burst": 0,
        "key": "$remote_addr $consumer_name",
        "key_type": "var_combination",
        "rejected_code": 429,
        "policy": "local"
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

创建两个消费者以及一个按消费者进行速率限制的路由：

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
  - name: limit-req-service
    routes:
      - name: limit-req-route
        uris:
          - /get
        plugins:
          key-auth: {}
          limit-req:
            rate: 1
            burst: 0
            key: "$remote_addr $consumer_name"
            key_type: var_combination
            rejected_code: 429
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

创建两个消费者以及一个按消费者进行速率限制的路由：

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="limit-req-ic.yaml"
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
  name: limit-req-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: limit-req
      config:
        rate: 1
        burst: 0
        key: "$remote_addr $consumer_name"
        key_type: var_combination
        rejected_code: 429
        policy: local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-req-route
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
            name: limit-req-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="limit-req-ic.yaml"
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
  name: limit-req-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-req-route
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
        - name: limit-req
          config:
            rate: 1
            burst: 0
            key: "$remote_addr $consumer_name"
            key_type: var_combination
            rejected_code: 429
            policy: local
```

</TabItem>

</Tabs>

应用配置：

```shell
kubectl apply -f limit-req-ic.yaml
```

</TabItem>

</Tabs>

❶ `key-auth`：在路由上启用 key 认证。

❷ `key`：设置为 `$remote_addr $consumer_name`，以按远程地址和消费者应用速率限制配额。

❸ `key_type`：设置为 `var_combination`，以将 `key` 解释为变量的组合。

同时发送两个请求，每个请求针对一个消费者：

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jane-key' & \
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key' &
```

你应该会收到两个请求的 `HTTP/1.1 200 OK`，表明请求未超过每个消费者的阈值。

如果你在同一秒内以任一消费者身份发送更多请求，应该会收到 `HTTP/1.1 429 Too Many Requests` 响应。

这验证了插件通过变量组合 `remote_addr` 和 `consumer_name` 进行速率限制。
