---
title: limit-count
keywords:
  - APISIX
  - API 网关
  - Limit Count
  - 速率限制
description: limit-count 插件使用固定窗口或滑动窗口算法，通过给定时间间隔内的请求数量来限制请求速率。超过配置配额的请求将被拒绝。
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

`limit-count` 插件使用固定窗口或滑动窗口算法，通过给定时间间隔内的请求数量来限制请求速率。超过配置配额的请求将被拒绝。

使用默认响应标头名称时，在单限流模式下将 `show_limit_quota_header` 设置为 `true`，响应中会包含以下速率限制标头：

* `X-RateLimit-Limit`：总配额
* `X-RateLimit-Remaining`：剩余配额
* `X-RateLimit-Reset`：计数器重置的剩余秒数

在 `rules` 模式下，每条规则都会使用带前缀的标头，例如 `X-Jack-RateLimit-Reset` 或 `X-1-RateLimit-Reset`。详情请参见 `rules.header_prefix`。

### 本地限流与 Redis 限流

`limit-count` 插件支持两种计数器存储模式：

* **本地限流：** 每个 APISIX 实例分别维护计数器。当流量分发到多个实例时，整体有效配额约等于配置配额乘以实例数量。未配置 `policy` 或将其设置为 `local` 时使用此默认模式。
* **基于 Redis 的限流：** APISIX 实例通过 Redis 共享计数器，因此同一配置配额适用于所有实例。单个 Redis 实例使用 `redis`，Redis 集群使用 `redis-cluster`，由 Redis Sentinel 管理的节点使用 `redis-sentinel`。

APISIX 3.18.0 及后续版本支持 Redis Sentinel、滑动窗口和 Redis 延迟同步。APISIX 3.16.0 及后续版本支持多条规则和通过变量解析限流值。

## 属性

| 名称                | 类型    | 必选项      | 默认值        | 有效值                                   | 描述                                                                                                                                                                                                                                 |
| ------------------- | ------- | ---------- | ------------- | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| count | integer 或 string | 否 | | > 0 | `time_window` 内允许的最大请求数。未配置 `rules` 时，必须与 `time_window` 一起配置；请勿与 `rules` 同时配置。字符串可以是数值，也可以通过 `$` 前缀引用 APISIX 或 NGINX 变量。解析结果必须是小于或等于 `9007199254740991` 的正整数，否则 APISIX 返回 `500 Internal Server Error`；`allow_degradation` 为 `true` 时除外。APISIX 3.16.0 及后续版本支持字符串值，APISIX 3.18.0 及后续版本支持运行时校验。 |
| time_window | integer 或 string | 否 | | > 0 | `count` 对应的时间间隔，单位为秒。未配置 `rules` 时，必须与 `count` 一起配置；请勿与 `rules` 同时配置。字符串可以是数值，也可以通过 `$` 前缀引用 APISIX 或 NGINX 变量。解析结果必须是小于或等于 `9007199254740991` 的正整数，否则 APISIX 返回 `500 Internal Server Error`；`allow_degradation` 为 `true` 时除外。APISIX 3.16.0 及后续版本支持字符串值，APISIX 3.18.0 及后续版本支持运行时校验。 |
| window_type | string | 否 | fixed | ["fixed","sliding"] | 限流窗口算法。`fixed` 对每个时间窗口独立执行配额；`sliding` 在计算当前计数时对上一个窗口加权，从而平滑窗口边界处的突发流量。APISIX 3.18.0 及后续版本支持 `sliding`。 |
| rules | array[object] | 否 | | | 按顺序执行的限流规则。请勿将 `rules` 与顶层的 `count`、`time_window` 或 `group` 同时配置；顶层 `key` 和 `key_type` 在规则模式下不生效。每条规则必须使用唯一的 `key`。如果请求中无法解析规则的键表达式，则跳过该规则。 |
| rules.count | integer 或 string | 是 | | > 0 | 规则的 `time_window` 内允许的最大请求数。字符串可以是数值，也可以通过 `$` 前缀引用 APISIX 或 NGINX 变量。解析结果必须是小于或等于 `9007199254740991` 的正整数，否则 APISIX 返回 `500 Internal Server Error`；`allow_degradation` 为 `true` 时除外。 |
| rules.time_window | integer 或 string | 是 | | > 0 | 规则中 `count` 对应的时间间隔，单位为秒。字符串可以是数值，也可以通过 `$` 前缀引用 APISIX 或 NGINX 变量。解析结果必须是小于或等于 `9007199254740991` 的正整数，否则 APISIX 返回 `500 Internal Server Error`；`allow_degradation` 为 `true` 时除外。 |
| rules.key | string | 是 | | | 用作该规则计数键的变量表达式。每个 APISIX 或 NGINX 变量都必须带 `$` 前缀，例如 `$remote_addr` 或 `$remote_addr $http_x_tenant`。顶层 `key_type` 不适用。如果该键表达式无法从请求中解析出任何变量，则跳过该规则。 |
| rules.header_prefix | string | 否 | | | 插入该规则配额标头中 `RateLimit-` 之前的前缀。例如，`foo` 会生成 `X-foo-RateLimit-Limit`、`X-foo-RateLimit-Remaining` 和 `X-foo-RateLimit-Reset`。如果省略，则使用从 1 开始的规则索引，因此第一条规则会生成 `X-1-RateLimit-*`。仅当 `show_limit_quota_header` 为 `true` 时发送。 |
| key_type | string | 否 | var | ["var","var_combination","constant"] | key 的类型。如果 `key_type` 为 `var`，则 `key` 将被解释为变量。如果 `key_type` 为 `var_combination`，则 `key` 将被解释为变量的组合。如果 `key_type` 为 `constant`，则 `key` 将被解释为常量。 |
| key | string | 否 | remote_addr | | 用于计数请求的 key。如果 `key_type` 为 `var`，则 `key` 将被解释为变量。变量不需要以美元符号（`$`）为前缀。如果 `key_type` 为 `var_combination`，则 `key` 会被解释为变量的组合。所有变量都应该以美元符号 (`$`) 为前缀。如果 `key_type` 为 `constant`，则 `key` 会被解释为常量值。 |
| rejected_code | integer | 否 | 503 | [200,...,599] | 请求因超出阈值而被拒绝时返回的 HTTP 状态代码。 |
| rejected_msg | string | 否 | | 非空 | 请求因超出阈值而被拒绝时返回的响应主体。 |
| policy | string | 否 | local | ["local","redis","redis-cluster","redis-sentinel"] | 速率限制计数器的策略。如果是 `local`，则计数器存储在本地内存中。如果是 `redis`，则计数器存储在 Redis 实例上。如果是 `redis-cluster`，则计数器存储在 Redis 集群中。如果是 `redis-sentinel`，则计数器存储在通过 Sentinel 发现的 Redis 主节点上。 |
| allow_degradation | boolean | 否 | false | | 如果为 `true`，当计数器后端发生故障，或通过变量解析的 `count` 或 `time_window` 无效时，APISIX 会继续处理请求但不执行限流。如果为 `false`，这些故障会返回 `500 Internal Server Error`。 |
| show_limit_quota_header | boolean | 否 | true | | 如果为 `true`，则在响应中包含配额标头。使用默认插件元数据时，单限流模式使用 `X-RateLimit-Limit`、`X-RateLimit-Remaining` 和 `X-RateLimit-Reset`。在 `rules` 模式下，每条规则都会输出 `rules.header_prefix` 中说明的带前缀标头。 |
| sync_interval | number | 否 | -1 | -1 或 >= 0.1；小于顶层数值型 `time_window` | Redis 类策略的延迟同步间隔，单位为秒。设置为 `-1` 时，每个请求都会直接同步。如果顶层动态 `time_window` 或 `rules.time_window` 的解析值小于或等于 `sync_interval`，APISIX 会对该请求回退为直接同步。APISIX 3.18.0 及后续版本支持延迟同步。 |
| group | string | 否 | | 非空 | 插件的 `group` ID，以便同一 `group` 的路由可以共享相同的速率限制计数器。 |
| redis_host | string | 否 | | | Redis 节点的地址。当 `policy` 为 `redis` 时必填。 |
| redis_port | integer | 否 | 6379 | [1,...] | 当 `policy` 为 `redis` 时，Redis 节点的端口。 |
| redis_username | string | 否 | | | 如果使用 Redis ACL，则为 Redis 的用户名。如果使用旧式身份验证方法 `requirepass`，则仅配置 `redis_password`。当 `policy` 为 `redis` 或 `redis-sentinel` 时使用。 |
| redis_password | string | 否 | | | 当 `policy` 为 `redis`、`redis-cluster` 或 `redis-sentinel` 时，Redis 节点的密码。 |
| redis_ssl | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis` 时使用 SSL 连接 Redis。 |
| redis_ssl_verify | boolean | 否 | false | | 如果为 true，则在 `policy` 为 `redis` 时验证服务器 SSL 证书。 |
| redis_server_name | string | 否 | | | 当 `policy` 为 `redis` 且 `redis_ssl` 为 true 时使用的 TLS SNI。默认使用 `redis_host`。当 `redis_ssl_verify` 为 true 时，证书还必须与该名称匹配，因此当 `redis_host` 是证书未覆盖的别名时请设置此项。 |
| redis_database | integer | 否 | 0 | >= 0 | 当 `policy` 为 `redis` 或 `redis-sentinel` 时，Redis 中的数据库编号。 |
| redis_timeout | integer | 否 | 1000 | [1,...] | 当 `policy` 为 `redis` 或 `redis-cluster` 时，Redis 超时值（以毫秒为单位）。 |
| redis_keepalive_timeout | integer | 否 | `redis` 和 `redis-cluster` 为 10000；`redis-sentinel` 为 60000 | `redis` 和 `redis-cluster` >= 1000；`redis-sentinel` >= 1 | Redis 空闲连接超时时间，单位为毫秒。 |
| redis_keepalive_pool | integer | 否 | 100 | ≥ 1 | 当 `policy` 为 `redis` 或 `redis-cluster` 时，与 Redis 的连接池最大连接数。 |
| redis_cluster_nodes | array[string] | 否 | | | 具有至少一个地址的 Redis 集群节点列表。当 `policy` 为 `redis-cluster` 时必填。 |
| redis_cluster_name | string | 否 | | | Redis 集群的名称。当 `policy` 为 `redis-cluster` 时必填。 |
| redis_cluster_ssl | boolean | 否 | false | | 如果为 `true`，当 `policy` 为 `redis-cluster` 时，使用 SSL 连接 Redis 集群。 |
| redis_cluster_ssl_verify | boolean | 否 | false | | 如果为 `true`，当 `policy` 为 `redis-cluster` 时，验证服务器 SSL 证书。 |
| redis_sentinels | array[object] | 否 | | | Sentinel 节点列表。当 `policy` 为 `redis-sentinel` 时必填。每一项都必须包含 `host` 和 `port`。 |
| redis_master_name | string | 否 | | | Sentinel 监控的 Redis 主节点名称。当 `policy` 为 `redis-sentinel` 时必填。 |
| redis_role | string | 否 | master | ["master","slave"] | 通过 Sentinel 选择的 Redis 角色。 |
| redis_connect_timeout | integer | 否 | 1000 | [1,...] | 当 `policy` 为 `redis-sentinel` 时，Redis 连接超时值（毫秒）。 |
| redis_read_timeout | integer | 否 | 1000 | [1,...] | 当 `policy` 为 `redis-sentinel` 时，Redis 读取超时值（毫秒）。 |
| sentinel_username | string | 否 | | | 如果启用了 Sentinel ACL，则为 Sentinel 用户名。 |
| sentinel_password | string | 否 | | | 如果启用了 Sentinel ACL，则为 Sentinel 密码。 |

注意：schema 中还定义了 `encrypt_fields = {"redis_password", "sentinel_password"}`，这意味着这些字段将会被加密存储在 etcd 中。具体参考[加密存储字段](../plugin-develop.md#加密存储字段)。

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

### 使用 Redis Sentinel 在 APISIX 节点之间共享配额

以下示例演示如何使用带 [Sentinel](https://redis.io/docs/management/sentinel/) 的 Redis 在多个 APISIX 节点之间进行限流，以实现高可用。Sentinel 监控 Redis 主节点，并在主节点故障时将一个副本提升为主节点。APISIX 通过配置的 Sentinel 节点发现当前主节点，因此共享配额可以在故障转移后无需修改配置继续生效。APISIX 3.18.0 及后续版本支持 `redis-sentinel` 策略。

在每个 APISIX 实例上，使用以下配置创建一个路由。请相应调整 Admin API 地址、Sentinel 节点、主节点名称和凭据：

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
        "policy": "redis-sentinel",
        "redis_sentinels": [
          { "host": "192.168.xxx.xxx", "port": 26379 },
          { "host": "192.168.xxx.xxx", "port": 26380 },
          { "host": "192.168.xxx.xxx", "port": 26381 }
        ],
        "redis_master_name": "mymaster",
        "redis_password": "p@ssw0rd",
        "sentinel_password": "s3ntinelp@ss",
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

如果未启用 Sentinel ACL，可省略 `sentinel_password`。若使用基于 ACL 的认证，请为 Redis 数据节点配置 `redis_username`/`redis_password`，为 Sentinel 节点配置 `sentinel_username`/`sentinel_password`。

向某个 APISIX 实例发送请求：

```shell
curl -i "http://127.0.0.1:9080/get"
```

你应当收到 `HTTP/1.1 200 OK` 响应。在 30 秒窗口内再次发送相同请求将返回 `HTTP/1.1 429 Too Many Requests`。如果 Redis 主节点发生故障转移，Sentinel 会提升一个副本，APISIX 将继续针对新的主节点强制执行共享配额。

### 应用滑动窗口速率限制

默认情况下，`limit-count` 使用固定窗口，计数器在每个 `time_window` 开始时重置。在窗口边界附近，这可能允许达到配置速率的两倍，因为客户端可能在一个窗口结束时耗尽配额，又在下一个窗口开始时再次耗尽配额。

将 `window_type` 设置为 `sliding` 可使用滑动窗口，它通过对上一个窗口的计数加权来平滑边界处的限流。在 APISIX 3.18.0 及后续版本中，`window_type` 适用于所有策略（`local`、`redis`、`redis-cluster` 和 `redis-sentinel`）。

使用以下配置创建一个路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "limit-count": {
        "count": 10,
        "time_window": 60,
        "rejected_code": 429,
        "key": "remote_addr",
        "window_type": "sliding"
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

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/get"
```

60 秒内的前 10 个请求返回 `HTTP/1.1 200 OK`，第 11 个返回 `HTTP/1.1 429 Too Many Requests`。与固定窗口不同，配额不会在 60 秒边界处完全重置；窗口持续滑动，从而避免边界附近出现两倍速率的突发。

### 通过延迟同步减少 Redis 往返

对于基于 Redis 的策略（`redis`、`redis-cluster` 和 `redis-sentinel`），APISIX 默认在每个请求时与 Redis 同步计数器。在高流量路由上，这会为每个请求增加一次 Redis 往返。APISIX 3.18.0 及后续版本支持延迟同步。

设置 `sync_interval`（单位：秒）可改为批量同步：在两次同步之间，计数由本地内存提供，并每隔一个间隔与 Redis 对账一次。这可以减少 Redis 往返和尾延迟，代价是全局计数最多滞后一个间隔的本地增量。将 `sync_interval` 设置为 `-1`（默认行为）则在每个请求时同步。

使用以下配置创建一个路由，请相应调整 Redis 连接设置：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "limit-count": {
        "count": 1000,
        "time_window": 60,
        "rejected_code": 429,
        "key": "remote_addr",
        "policy": "redis",
        "redis_host": "192.168.xxx.xxx",
        "redis_port": 6379,
        "redis_password": "p@ssw0rd",
        "redis_database": 1,
        "sync_interval": 1
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

`sync_interval` 必须不小于 `0.1`。在单限流模式下，它还必须小于顶层的数值型 `time_window`。如果 `rules.time_window` 的值或顶层的动态 `time_window` 解析后的值小于或等于 `sync_interval`，APISIX 会回退为对该请求直接同步。解析后的时间窗口大于 `sync_interval` 时，仍使用延迟同步。延迟同步使用 `plugin-limit-count-lock` 共享字典，该字典默认已配置，因此无需额外配置。

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/get"
```

请求在本地计数，并每秒与 Redis 对账一次。一旦达到 60 秒内 1000 个请求的配额，后续请求将返回 `HTTP/1.1 429 Too Many Requests`。

在同步发生之前，不同 APISIX 实例中的计数器可能暂时不一致，因此并发请求可能在同步间隔内超过配置配额。如果精确的跨实例限流比减少 Redis 流量更重要，请使用直接同步。

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

配置具有不同速率限制的消费者和接受匿名用户的路由：

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
  plugins:
    - name: limit-count
      enable: true
      config:
        count: 3
        time_window: 30
        rejected_code: 429
        policy: local
---
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: anonymous
spec:
  ingressClassName: apisix
  plugins:
    - name: limit-count
      enable: true
      config:
        count: 1
        time_window: 30
        rejected_code: 429
        policy: local
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
  name: key-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: key-auth-route
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: key-auth
          enable: true
          config:
            anonymous_consumer: aic_anonymous  # namespace_consumername
```

将配置应用到集群：

```shell
kubectl apply -f limit-count-ic.yaml
```

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

### 记录请求被放行或拒绝的原因

插件会把本次判定写入 `$rate_limiting_info` 变量，值为一个 JSON 对象，可以加入访问日志，或加入日志类插件的 `log_format`。例如，在 `config.yaml` 中把它加入访问日志：

```yaml
nginx_config:
  http:
    access_log_format: '$remote_addr - [$time_local] "$request" $status "$rate_limiting_info"'
```

计入固定窗口的请求记录的值类似如下：

```json
{"rate_limiting_key":"\/apisix\/routes\/1:1:127.0.0.1","rate_limiting_limit":10,"rate_limiting_remaining":3,"rate_limiting_reset":42,"window_type":"fixed","window_size_ms":60000,"decision":"allowed","cost":1,"evaluated_at_ms":1759212345678,"current_window":{"start_ms":1759212300123,"end_ms":1759212360123,"count":7,"created":false}}
```

计入滑动窗口的请求记录的值类似如下：

```json
{"rate_limiting_key":"\/apisix\/routes\/1:1:127.0.0.1","rate_limiting_limit":10,"rate_limiting_remaining":3,"rate_limiting_reset":14,"window_type":"sliding","window_size_ms":60000,"decision":"allowed","cost":1,"evaluated_at_ms":1759212345678,"current_window":{"id":29320205,"start_ms":1759212300000,"end_ms":1759212360000,"count":4},"previous_window":{"count":10,"weight":0.2387,"weighted_count":2.387}}
```

字段的顺序不固定，JSON 编码会把键中的 `/` 转义为 `\/`。所有 `*_ms` 字段都是以毫秒为单位的 Unix 时间戳或时长，取自 APISIX 实例的时钟。适用于该窗口类型、但对本次请求未知的字段为 `null`。各字段含义如下：

* `rate_limiting_key`、`rate_limiting_limit`、`rate_limiting_remaining`、`rate_limiting_reset`：计数器的键、配额、剩余配额以及距重置的秒数，与限流响应头一致。滑动窗口拒绝请求时，`rate_limiting_reset` 是距离可以再次放行请求的时间，可能早于窗口结束时间。
* `window_type`：`fixed` 或 `sliding`。
* `window_size_ms`：以毫秒表示的 `time_window`。
* `decision`：`allowed`、`rejected`，或在无法更新计数器（例如 Redis 不可达）时为 `error`。值为 `error` 时只包含以上字段。
* `cost`：本次请求计入计数器的值。固定窗口即使拒绝请求也会计数；滑动窗口和延迟同步只对放行的请求计数，因此被拒绝请求的 `cost` 为 `0`。
* `evaluated_at_ms`：检查本次请求的时间。
* `current_window.count`：计入本次请求（含其 `cost`）之后当前窗口的计数。本地固定窗口拒绝请求时为 `null`。
* `current_window.start_ms` 和 `current_window.end_ms`：当前窗口的起止时间。

固定窗口不与时钟对齐：它从该键下计入的第一个请求开始，持续 `time_window` 秒。`current_window.created` 在开启该窗口的请求上为 `true`。它只在 `local` 策略下可知，在 Redis 策略下为 `null`；Redis 策略下窗口结束时间由 Redis 计数器的 TTL 推算，不同请求之间可能相差几毫秒。

滑动窗口与时钟对齐：`current_window.id` 是自 Unix 纪元以来的窗口序号，当前窗口从 `id * window_size_ms` 开始。当前窗口的计数加上上一个窗口按其仍处于滑动范围内的比例加权后的计数，只要低于配额，请求就会被放行。`previous_window.count` 是上一个窗口的计数（不超过配额），`previous_window.weight` 是该比例（0 到 1），`previous_window.weighted_count` 是两者的乘积。

启用延迟同步（`sync_interval`）时，通过 Redis 共享的计数器每个间隔只读取一次，`delayed_sync` 对象描述了本次请求所依据的数据：

* `delayed_sync.synced_at_ms`：该 APISIX 实例上一次同步计数器的时间。
* `delayed_sync.synced_count`：当时 Redis 中当前窗口的计数。
* `delayed_sync.local_delta`：该 APISIX 实例自那以后计入、尚未同步的值，不含本次请求。

此时 `current_window.count` 是估算值，即 `synced_count + local_delta + cost`，不包含其他实例自各自上次同步以来的计数。对于滑动窗口，`current_window` 和 `previous_window` 描述的是上一次同步时的窗口：上一个窗口的权重在同步时就已确定，因此 `previous_window.weight` 是本次请求实际使用的权重，而不是 `evaluated_at_ms` 时刻的权重。快照只在其窗口结束之后才会刷新，因此在窗口边界之后几毫秒内到达的请求仍按上一次的快照判定，此时它的 `evaluated_at_ms` 会晚于 `current_window.end_ms`。

配置多条 `rules` 时，该变量描述最后一条被检查的规则；如果有规则拒绝了请求，就是该规则。
