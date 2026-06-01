---
title: limit-count
keywords:
  - APISIX
  - API 网关
  - Limit Count
  - 速率限制
description: limit-count 插件使用固定窗口算法，通过给定时间间隔内的请求数量来限制请求速率。超过配置配额的请求将被拒绝。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/limit-count" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`limit-count` 插件使用固定窗口算法，通过给定时间间隔内的请求数量来限制请求速率。超过配置配额的请求将被拒绝。

你可能会在响应中看到以下速率限制标头：

* `X-RateLimit-Limit`：总配额
* `X-RateLimit-Remaining`：剩余配额
* `X-RateLimit-Reset`：计数器重置的剩余秒数

## 属性

| 名称                | 类型    | 必选项      | 默认值        | 有效值                                   | 描述                                                                                                                                                                                                                                 |
| ------------------- | ------- | ---------- | ------------- | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| count | integer 或 string | 否 | | > 0 | 给定时间间隔内允许的最大请求数。如果未配置 `rules`，则此项必填。支持从 APISIX 3.16.0 起使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |
| time_window | integer 或 string | 否 | | > 0 | 速率限制 `count` 对应的时间间隔（以秒为单位）。如果未配置 `rules`，则此项必填。支持从 APISIX 3.16.0 起使用 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |
| rules | array[object] | 否 | | | 速率限制规则列表。每个规则是一个包含 `count`、`time_window` 和 `key` 的对象。如果配置了 `rules`，则顶层的 `count` 和 `time_window` 将被忽略。 |
| rules.count | integer 或 string | 是 | | > 0 | 给定时间间隔内允许的最大请求数。支持 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |
| rules.time_window | integer 或 string | 是 | | > 0 | 速率限制 `count` 对应的时间间隔（以秒为单位）。支持 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |
| rules.key | string | 是 | | | 用于统计请求的键。如果配置的键不存在，则不会执行该规则。`key` 被解释为变量的组合，例如：`$http_custom_a $http_custom_b`。|
| rules.header_prefix | string | 否 | | | 速率限制标头的前缀。如果已配置，响应将包含 `X-{header_prefix}-RateLimit-Limit`、`X-{header_prefix}-RateLimit-Remaining` 和 `X-{header_prefix}-RateLimit-Reset` 标头。如果未配置，则使用规则数组中规则的索引作为前缀。例如，第一个规则的标头将是 `X-1-RateLimit-Limit`、`X-1-RateLimit-Remaining` 和 `X-1-RateLimit-Reset`。|
| key_type | string | 否 | var | ["var","var_combination","constant"] | key 的类型。如果`key_type` 为 `var`，则 `key` 将被解释为变量。如果 `key_type` 为 `var_combination`，则 `key` 将被解释为变量的组合。如果 `key_type` 为 `constant`，则 `key` 将被解释为常量。 |
| key | string | 否 | remote_addr | | 用于计数请求的 key。如果 `key_type` 为 `var`，则 `key` 将被解释为变量。变量不需要以美元符号（`$`）为前缀。如果 `key_type` 为 `var_combination`，则 `key` 会被解释为变量的组合。所有变量都应该以美元符号 (`$`) 为前缀。例如，要配置 `key` 使用两个请求头 `custom-a` 和 `custom-b` 的组合，则 `key` 应该配置为 `$http_custom_a $http_custom_b`。如果 `key_type` 为 `constant`，则 `key` 会被解释为常量值。|
| rejected_code | integer | 否 | 503 | [200,...,599] | 请求因超出阈值而被拒绝时返回的 HTTP 状态代码。|
| rejection_msg | string | 否 | | 非空 | 请求因超出阈值而被拒绝时返回的响应主体。|
| policy | string | 否 | local | ["local","re​​dis","re​​dis-cluster"] | 速率限制计数器的策略。如果是 `local`，则计数器存储在本地内存中。如果是 `redis`，则计数器存储在 Redis 实例上。如果是 `redis-cluster`，则计数器存储在 Redis 集群中。|
| allow_degradation | boolean | 否 | false | | 如果为 true，则允许 APISIX 在插件或其依赖项不可用时继续处理没有插件的请求。|
| show_limit_quota_header | boolean | 否 | true | | 如果为 true，则在响应标头中包含 `X-RateLimit-Limit` 以显示总配额和 `X-RateLimit-Remaining` 以显示剩余配额。|
| group | string | 否 | | 非空 | 插件的 `group` ID，以便同一 `group` 的路由可以共享相同的速率限制计数器。 |
| redis_host | string | 否 | | | Redis 节点的地址。当 `policy` 为 `redis` 时必填。 |
| redis_port | integer | 否 | 6379 | [1,...] | 当 `policy` 为 `redis` 时，Redis 节点的端口。 |
| redis_username | string | 否 | | | 如果使用 Redis ACL，则为 Redis 的用户名。如果使用旧式身份验证方法 `requirepass`，则仅配置 `redis_password`。当 `policy` 为 `redis` 时使用。 |
| redis_password | string | 否 | | | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 节点的密码。 |
| redis_ssl | boolean | 否 | false |如果为 true，则在 `policy` 为 `redis` 时使用 SSL 连接到 Redis 集群。|
| redis_ssl_verify | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis` 时验证服务器 SSL 证书。|
| redis_database | integer | 否 | 0 | >= 0 | 当 `policy` 为 `redis` 时，Redis 中的数据库编号。|
| redis_timeout | integer | 否 | 1000 | [1,...] | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 超时值（以毫秒为单位）。 |
| redis_keepalive_timeout | integer | 否 | 10000 | ≥ 1000 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，与 `redis` 或 `redis-cluster` 的空闲连接超时时间，单位为毫秒。|
| redis_keepalive_pool | integer | 否 | 100 | ≥ 1 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，与 `redis` 或 `redis-cluster` 的连接池最大连接数。|
| redis_cluster_nodes | array[string] | 否 | | | 具有至少一个地址的 Redis 群集节点列表。当 policy 为 redis-cluster 时必填。 |
| redis_cluster_name | string | 否 | | | Redis 集群的名称。当 `policy` 为 `redis-cluster` 时必须使用。|
| redis_cluster_ssl | boolean | 否 | false | | 如果为 `true`，当 `policy` 为 `redis-cluster`时，使用 SSL 连接 Redis 集群。|
| redis_cluster_ssl_verify | boolean | 否 | false | | 如果为 `true`，当 `policy` 为 `redis-cluster` 时，验证服务器 SSL 证书。  |

## 示例

下面的示例演示了如何在不同情况下配置 `limit-count` 。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 按远程地址应用速率限制

下面的示例演示了通过单一变量 `remote_addr` 对请求进行速率限制。

创建一个带有 `limit-count` 插件的路由，允许在 30 秒窗口内为每个远程地址设置 1 个配额：

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
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr",
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
        name: limit-count-route
        plugins:
          limit-count:
            count: 1
            time_window: 30
            rejected_code: 429
            key_type: var
            key: remote_addr
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

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-plugin-config
spec:
  plugins:
    - name: limit-count
      config:
        count: 1
        time_window: 30
        rejected_code: 429
        key_type: var
        key: remote_addr
        policy: local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-count-route
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
            name: limit-count-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-count-route
      match:
        paths:
          - /get
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: limit-count
        enable: true
        config:
          count: 1
          time_window: 30
          rejected_code: 429
          key_type: var
          key: remote_addr
          policy: local
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

发送验证请求：

```shell
curl -i "http://127.0.0.1:9080/get"
```

你应该会看到 `HTTP/1.1 200 OK` 响应。

该请求已消耗了时间窗口允许的所有配额。如果你在相同的 30 秒时间间隔内再次发送该请求，你应该会收到 `HTTP/1.1 429 Too Many Requests` 响应，表示该请求超出了配额阈值。

### 通过远程地址和消费者名称应用速率限制

以下示例演示了通过变量 `remote_addr` 和 `consumer_name` 的组合对请求进行速率限制。它允许每个远程地址和每个消费者在 30 秒窗口内有 1 个配额。

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

创建一个带有 `key-auth` 和 `limit-count` 插件的路由，并在 `limit-count` 插件中指定使用变量组合作为速率限制键。`key-auth` 插件在路由上启用密钥认证。`key_type` 设置为 `var_combination` 以将 `key` 解释为变量的组合，`key` 设置为 `$remote_addr $consumer_name` 以按远程地址和每个消费者应用速率限制配额：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
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

<TabItem value="adc">

创建两个消费者和一个按消费者启用速率限制的路由。`key-auth` 插件在路由上启用密钥认证。`key_type` 设置为 `var_combination` 以将 `key` 解释为变量的组合，`key` 设置为 `$remote_addr $consumer_name` 以按远程地址和每个消费者应用速率限制配额：

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
  - name: limit-count-service
    routes:
      - name: limit-count-route
        uris:
          - /get
        plugins:
          key-auth: {}
          limit-count:
            count: 1
            time_window: 30
            rejected_code: 429
            key_type: var_combination
            key: "$remote_addr $consumer_name"
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

创建两个消费者和一个按消费者启用速率限制的路由。`key-auth` 插件在路由上启用密钥认证。`key_type` 设置为 `var_combination` 以将 `key` 解释为变量的组合，`key` 设置为 `$remote_addr $consumer_name` 以按远程地址和每个消费者应用速率限制配额：

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: limit-count
      config:
        count: 1
        time_window: 30
        rejected_code: 429
        key_type: var_combination
        key: "$remote_addr $consumer_name"
        policy: local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-count-route
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
            name: limit-count-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-count-route
      match:
        paths:
          - /get
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
      - name: limit-count
        enable: true
        config:
          count: 1
          time_window: 30
          rejected_code: 429
          key_type: var_combination
          key: "$remote_addr $consumer_name"
          policy: local
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

以消费者 `jane` 的身份发送请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jane-key'
```

你应该会看到一个 `HTTP/1.1 200 OK` 响应以及相应的响应主体。

此请求已消耗了为时间窗口设置的所有配额。如果你在相同的 30 秒时间间隔内向消费者 `jane` 发送相同的请求，你应该会收到一个 `HTTP/1.1 429 Too Many Requests` 响应，表示请求超出了配额阈值。

在相同的 30 秒时间间隔内向消费者 `john` 发送相同的请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

你应该看到一个 `HTTP/1.1 200 OK` 响应和相应的响应主体，表明请求不受速率限制。

在相同的 30 秒时间间隔内再次以消费者 `john` 的身份发送相同的请求，你应该收到一个 `HTTP/1.1 429 Too Many Requests` 响应。

这通过变量 `remote_addr` 和 `consumer_name` 的组合验证了插件速率限制。

### 在路由之间共享配额

以下示例通过配置 `limit-count` 插件的 `group` 演示了在多个路由之间共享速率限制配额。

请注意，同一 `group` 的 `limit-count` 插件的配置应该相同。为了避免更新异常和重复配置，你可以创建一个带有 `limit-count` 插件和上游的服务，以供路由连接。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建服务：

```shell
curl "http://127.0.0.1:9180/apisix/admin/services" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-service",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "policy": "local",
        "group": "srv1"
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

创建两个路由，并将其 `service_id` 配置为 `limit-count-service`，以便它们对插件和上游共享相同的配置：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route-1",
    "service_id": "limit-count-service",
    "uri": "/get1",
    "plugins": {
      "proxy-rewrite": {
        "uri": "/get"
      }
    }
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route-2",
    "service_id": "limit-count-service",
    "uri": "/get2",
    "plugins": {
      "proxy-rewrite": {
        "uri": "/get"
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建一个带有两个路由的服务，共享相同的速率限制配额：

```yaml title="adc.yaml"
services:
  - name: limit-count-service
    plugins:
      limit-count:
        count: 1
        time_window: 30
        rejected_code: 429
        policy: local
        group: srv1
    routes:
      - name: limit-count-route-1
        uris:
          - /get1
        plugins:
          proxy-rewrite:
            uri: /get
      - name: limit-count-route-2
        uris:
          - /get2
        plugins:
          proxy-rewrite:
            uri: /get
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

创建两个引用相同 PluginConfig 的 HTTPRoute 以共享配额：

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-plugin-config
spec:
  plugins:
    - name: limit-count
      config:
        count: 1
        time_window: 30
        rejected_code: 429
        policy: local
        group: srv1
    - name: proxy-rewrite
      config:
        uri: /get
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-count-route-1
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get1
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: limit-count-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-count-route-2
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get2
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: limit-count-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

创建一个包含多个路径的 ApisixRoute，共享相同的插件配置：

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-shared-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-count-shared
      match:
        paths:
          - /get1
          - /get2
      upstreams:
      - name: httpbin-external-domain
      plugins:
        - name: proxy-rewrite
          enable: true
          config:
            uri: /get
        - name: limit-count
          enable: true
          config:
            count: 1
            time_window: 30
            rejected_code: 429
            policy: local
            group: srv1
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

:::note

[`proxy-rewrite`](./proxy-rewrite.md) 插件用于将 URI 重写为 `/get`，以便将请求转发到正确的端点。

:::

向路由 `/get1` 发送请求：

```shell
curl -i "http://127.0.0.1:9080/get1"
```

你应该会看到一个 `HTTP/1.1 200 OK` 响应以及相应的响应主体。

在相同的 30 秒时间间隔内向路由 `/get2` 发送相同的请求：

```shell
curl -i "http://127.0.0.1:9080/get2"
```

你应该收到 `HTTP/1.1 429 Too Many Requests` 响应，这验证两个路由共享相同的速率限制配额。

### 使用 Redis 服务器在 APISIX 节点之间共享配额

以下示例演示了使用 Redis 服务器对多个 APISIX 节点之间的请求进行速率限制，以便不同的 APISIX 节点共享相同的速率限制配额。

在每个 APISIX 实例上，使用以下配置创建一个路由。相应地调整管理 API 的地址、Redis 主机、端口、密码和数据库。

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
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
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

<TabItem value="adc">

创建一个使用 Redis 进行速率限制的路由。将 `policy` 设置为 `redis` 以使用 Redis 实例进行速率限制。配置 `redis_host`、`redis_port`、`redis_password` 和 `redis_database` 以匹配你的 Redis 实例：

```yaml title="adc.yaml"
services:
  - name: redis-limit-service
    routes:
      - name: redis-limit-route
        uris:
          - /get
        plugins:
          limit-count:
            count: 1
            time_window: 30
            rejected_code: 429
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

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-redis-plugin-config
spec:
  plugins:
    - name: limit-count
      config:
        count: 1
        time_window: 30
        rejected_code: 429
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
  name: redis-limit-route
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
            name: limit-count-redis-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="limit-count-ic.yaml"
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
  name: redis-limit-route
spec:
  ingressClassName: apisix
  http:
    - name: redis-limit-route
      match:
        paths:
          - /get
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: limit-count
        enable: true
        config:
          count: 1
          time_window: 30
          rejected_code: 429
          key: remote_addr
          policy: redis
          redis_host: "redis-service.aic.svc"
          redis_port: 6379
          redis_password: "p@ssw0rd"
          redis_database: 1
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

向 APISIX 实例发送请求：

```shell
curl -i "http://127.0.0.1:9080/get"
```

你应该会看到一个 `HTTP/1.1 200 OK` 响应以及相应的响应主体。

在相同的 30 秒时间间隔内向不同的 APISIX 实例发送相同的请求，你应该会收到一个 `HTTP/1.1 429 Too Many Requests` 响应，验证在不同 APISIX 节点中配置的路由是否共享相同的配额。

### 使用 Redis 集群在 APISIX 节点之间共享配额

你还可以使用 Redis 集群在多个 APISIX 节点之间应用相同的配额，以便不同的 APISIX 节点共享相同的速率限制配额。

确保你的 Redis 实例在 [集群模式](https://redis.io/docs/management/scaling/#create-and-use-a-redis-cluster) 下运行。`limit-count` 插件配置至少需要两个节点。

在每个 APISIX 实例上，使用以下配置创建路由。相应地调整管理 API 的地址、Redis 集群节点、密码、集群名称和 SSL 验证。

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
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "key": "remote_addr",
        "policy": "redis-cluster",
        "redis_cluster_nodes": [
          "192.168.xxx.xxx:6379",
          "192.168.xxx.xxx:16379"
        ],
        "redis_password": "p@ssw0rd",
        "redis_cluster_name": "redis-cluster-1",
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

<TabItem value="adc">

创建一个使用 Redis 集群进行速率限制的路由。将 `policy` 设置为 `redis-cluster` 以使用 Redis 集群进行速率限制。配置 `redis_cluster_nodes` 为 Redis 节点地址，`redis_password` 为集群密码，`redis_cluster_name` 为集群名称，并启用 `redis_cluster_ssl` 以进行 SSL/TLS 通信：

```yaml title="adc.yaml"
services:
  - name: redis-cluster-limit-service
    routes:
      - name: redis-cluster-limit-route
        uris:
          - /get
        plugins:
          limit-count:
            count: 1
            time_window: 30
            rejected_code: 429
            key: remote_addr
            policy: redis-cluster
            redis_cluster_nodes:
              - "192.168.xxx.xxx:6379"
              - "192.168.xxx.xxx:16379"
            redis_password: "p@ssw0rd"
            redis_cluster_name: redis-cluster-1
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

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-redis-cluster-plugin-config
spec:
  plugins:
    - name: limit-count
      config:
        count: 1
        time_window: 30
        rejected_code: 429
        key: remote_addr
        policy: redis-cluster
        redis_cluster_nodes:
          - "redis-cluster-0.redis-cluster.aic.svc:6379"
          - "redis-cluster-1.redis-cluster.aic.svc:6379"
        redis_password: "p@ssw0rd"
        redis_cluster_name: redis-cluster-1
        redis_cluster_ssl: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: redis-cluster-limit-route
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
            name: limit-count-redis-cluster-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="limit-count-ic.yaml"
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
  name: redis-cluster-limit-route
spec:
  ingressClassName: apisix
  http:
    - name: redis-cluster-limit-route
      match:
        paths:
          - /get
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: limit-count
        enable: true
        config:
          count: 1
          time_window: 30
          rejected_code: 429
          key: remote_addr
          policy: redis-cluster
          redis_cluster_nodes:
            - "redis-cluster-0.redis-cluster.aic.svc:6379"
            - "redis-cluster-1.redis-cluster.aic.svc:6379"
          redis_password: "p@ssw0rd"
          redis_cluster_name: redis-cluster-1
          redis_cluster_ssl: true
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

向 APISIX 实例发送请求：

```shell
curl -i "http://127.0.0.1:9080/get"
```

你应该会看到一个 `HTTP/1.1 200 OK` 响应以及相应的响应主体。

在相同的 30 秒时间间隔内向不同的 APISIX 实例发送相同的请求，你应该会收到一个 `HTTP/1.1 429 Too Many Requests` 响应，验证在不同 APISIX 节点中配置的路由是否共享相同的配额。

### 使用匿名消费者进行速率限制

以下示例演示了如何为常规和匿名消费者配置不同的速率限制策略，其中匿名消费者不需要进行身份验证并且配额较少。虽然此示例使用 [`key-auth`](./key-auth.md) 进行身份验证，但匿名消费者也可以使用 [`basic-auth`](./basic-auth.md)、[`jwt-auth`](./jwt-auth.md) 和 [`hmac-auth`](./hmac-auth.md) 进行配置。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建一个消费者 `john`，并配置 `limit-count` 插件，以允许 30 秒内配额为 3：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

为消费者 `john` 创建 `key-auth` 凭证：

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

创建匿名用户 `anonymous`，并配置 `limit-count` 插件，以允许 30 秒内配额为 1：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "anonymous",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

创建路由并配置 `key-auth` 插件以接受匿名消费者 `anonymous` 绕过身份验证：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {
        "anonymous_consumer": "anonymous"
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

配置具有不同速率限制的消费者和接受匿名用户的路由：

```yaml title="adc.yaml"
consumers:
  - username: john
    plugins:
      limit-count:
        count: 3
        time_window: 30
        rejected_code: 429
        policy: local
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: john-key
  - username: anonymous
    plugins:
      limit-count:
        count: 1
        time_window: 30
        rejected_code: 429
        policy: local
services:
  - name: anonymous-rate-limit-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth:
            anonymous_consumer: anonymous
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

配置具有不同速率限制的消费者和接受匿名用户的路由：

```yaml title="limit-count-ic.yaml"
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
  plugins:
    - name: limit-count
      config:
        count: 3
        time_window: 30
        rejected_code: 429
        policy: local
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: anonymous
spec:
  gatewayRef:
    name: apisix
  plugins:
    - name: limit-count
      config:
        count: 1
        time_window: 30
        rejected_code: 429
        policy: local
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
  name: key-auth-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        anonymous_consumer: aic_anonymous  # namespace_consumername
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: key-auth-route
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
            name: key-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

将配置应用到集群：

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

:::important[note]

ApisixConsumer CRD 目前不支持在消费者上配置插件，除了 `authParameter` 中允许的认证插件。此示例无法使用 APISIX CRD 完成。

:::

</TabItem>

</Tabs>

</TabItem>

</Tabs>

使用 `john` 的密钥发送五个连续的请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: john-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

你应该看到以下响应，显示在 5 个请求中，3 个请求成功（状态代码 200），而其他请求被拒绝（状态代码 429）。

```text
200:    3, 429:    2
```

发送五个匿名请求：

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

你应该看到以下响应，表明只有一个请求成功：

```text
200:    1, 429:    4
```

### 自定义速率限制标头

以下示例演示了如何使用插件元数据自定义速率限制响应标头名称，默认名称为 `X-RateLimit-Limit`、`X-RateLimit-Remaining` 和 `X-RateLimit-Reset`。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

配置插件元数据以自定义速率限制标头：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/limit-count" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "limit_header": "X-Custom-RateLimit-Limit",
    "remaining_header": "X-Custom-RateLimit-Remaining",
    "reset_header": "X-Custom-RateLimit-Reset"
  }'
```

创建带有 `limit-count` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr"
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

配置插件元数据并创建带有速率限制的路由：

```yaml title="adc.yaml"
plugin_metadata:
  limit-count:
    limit_header: X-Custom-RateLimit-Limit
    remaining_header: X-Custom-RateLimit-Remaining
    reset_header: X-Custom-RateLimit-Reset
services:
  - name: limit-count-service
    routes:
      - name: limit-count-route
        uris:
          - /get
        plugins:
          limit-count:
            count: 1
            time_window: 30
            rejected_code: 429
            key_type: var
            key: remote_addr
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

更新你的 GatewayProxy 清单以配置插件元数据：

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
      # ...
      # 你的控制平面连接配置
  pluginMetadata:
    limit-count:
      limit_header: X-Custom-RateLimit-Limit
      remaining_header: X-Custom-RateLimit-Remaining
      reset_header: X-Custom-RateLimit-Reset
```

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

创建启用插件的路由：

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-plugin-config
spec:
  plugins:
    - name: limit-count
      config:
        count: 1
        time_window: 30
        rejected_code: 429
        key_type: var
        key: remote_addr
        policy: local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: limit-count-route
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
            name: limit-count-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

创建启用插件的路由：

```yaml title="limit-count-ic.yaml"
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
  name: limit-count-route
spec:
  ingressClassName: apisix
  http:
    - name: limit-count-route
      match:
        paths:
          - /get
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: limit-count
        enable: true
        config:
          count: 1
          time_window: 30
          rejected_code: 429
          key_type: var
          key: remote_addr
          policy: local
```

</TabItem>

</Tabs>

将配置应用到集群：

```shell
kubectl apply -f gatewayproxy.yaml -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

发送请求进行验证：

```shell
curl -i "http://127.0.0.1:9080/get"
```

你应该收到 `HTTP/1.1 200 OK` 响应，并看到以下标头：

```text
X-Custom-RateLimit-Limit: 1
X-Custom-RateLimit-Remaining: 0
X-Custom-RateLimit-Reset: 28
```
