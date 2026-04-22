---
title: Concurrency Limiting (limit-conn)
keywords:
  - Apache APISIX
  - API Gateway
  - Limit Connection
description: The limit-conn plugin restricts the rate of requests by managing concurrent connections. Requests exceeding the threshold may be delayed or rejected, ensuring controlled API usage and preventing overload.
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

## Description

The `limit-conn` Plugin limits the rate of requests by the number of concurrent connections. Requests exceeding the threshold will be delayed or rejected based on the configuration, ensuring controlled resource usage and preventing overload.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| conn | integer,string | False | | integer > 0, or [lua-resty-expr](https://github.com/api7/lua-resty-expr) | The maximum number of concurrent requests allowed. Requests exceeding the configured limit and below `conn + burst` will be delayed. Required if `rules` is not configured. |
| burst | integer,string | False | | integer >= 0, or [lua-resty-expr](https://github.com/api7/lua-resty-expr) | The number of excessive concurrent requests allowed to be delayed. Requests exceeding `conn + burst` will be rejected immediately. Required if `rules` is not configured. |
| default_conn_delay | number | True | | > 0 | Processing latency allowed in seconds for concurrent requests exceeding `conn` and up to `conn + burst`, which can be dynamically adjusted based on `only_use_default_delay` setting. |
| only_use_default_delay | boolean | False | false | | If false, delay requests proportionally based on how much they exceed the `conn` limit. The delay grows larger as congestion increases. For instance, with `conn` being `5`, `burst` being `3`, and `default_conn_delay` being `1`, 6 concurrent requests would result in a 1-second delay, 7 requests a 2-second delay, 8 requests a 3-second delay, and so on, until the total limit of `conn + burst` is reached, beyond which requests are rejected. If true, use `default_conn_delay` to delay all excessive requests within the `burst` range. Requests beyond `conn + burst` are rejected immediately. For instance, with `conn` being `5`, `burst` being `3`, and `default_conn_delay` being `1`, 6, 7, or 8 concurrent requests are all delayed by exactly 1 second each. |
| key_type | string | False | var | [`var`, `var_combination`] | The type of key. If the `key_type` is `var`, the `key` is interpreted as a variable. If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. |
| key | string | False | remote_addr | | The key to count requests by. If the `key_type` is `var`, the `key` is interpreted as a variable. The variable does not need to be prefixed by a dollar sign (`$`). If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. All variables should be prefixed by dollar signs (`$`). For example, to configure the `key` to use a combination of two request headers `custom-a` and `custom-b`, the `key` should be configured as `$http_custom_a $http_custom_b`. Required if `rules` is not configured. |
| rejected_code | integer | False | 503 | [200, ..., 599] | The HTTP status code returned when a request is rejected for exceeding the threshold. |
| rejected_msg | string | False | | non-empty | The response body returned when a request is rejected for exceeding the threshold. |
| allow_degradation | boolean | False | false | | If true, allow APISIX to continue handling requests without the Plugin when the Plugin or its dependencies become unavailable. |
| policy | string | False | local | [`local`, `redis`, `redis-cluster`] | The policy for rate limiting counter. If it is `local`, the counter is stored in memory locally. If it is `redis`, the counter is stored on a Redis instance. If it is `redis-cluster`, the counter is stored in a Redis cluster. |
| redis_host | string | False | | | The address of the Redis node. Required when `policy` is `redis`. |
| redis_port | integer | False | 6379 | >= 1 | The port of the Redis node when `policy` is `redis`. |
| redis_username | string | False | | | The username for Redis if Redis ACL is used. If you use the legacy authentication method `requirepass`, configure only the `redis_password`. Used when `policy` is `redis`. |
| redis_password | string | False | | | The password of the Redis node when `policy` is `redis` or `redis-cluster`. |
| redis_ssl | boolean | False | false | | If true, use SSL to connect to Redis when `policy` is `redis`. |
| redis_ssl_verify | boolean | False | false | | If true, verify the server SSL certificate when `policy` is `redis`. |
| redis_database | integer | False | 0 | >= 0 | The database number in Redis when `policy` is `redis`. |
| redis_timeout | integer | False | 1000 | >= 1 | The Redis timeout value in milliseconds when `policy` is `redis` or `redis-cluster`. |
| redis_keepalive_timeout | integer | False | 10000 | >= 1000 | Keepalive timeout in milliseconds for Redis when `policy` is `redis` or `redis-cluster`. |
| redis_keepalive_pool | integer | False | 100 | >= 1 | Keepalive pool size for Redis when `policy` is `redis` or `redis-cluster`. |
| key_ttl | integer | False | 3600 | | The TTL of the Redis key in seconds. Used when `policy` is `redis` or `redis-cluster`. |
| redis_cluster_nodes | array[string] | False | | | The list of Redis cluster nodes with at least one address. Required when `policy` is `redis-cluster`. |
| redis_cluster_name | string | False | | | The name of the Redis cluster. Required when `policy` is `redis-cluster`. |
| redis_cluster_ssl | boolean | False | false | | If true, use SSL to connect to Redis cluster when `policy` is `redis-cluster`. |
| redis_cluster_ssl_verify | boolean | False | false | | If true, verify the server SSL certificate when `policy` is `redis-cluster`. |
| rules | array[object] | False | | | An array of rate-limiting rules that are applied sequentially. Available in APISIX from 3.16.0. You should configure one of the following parameter sets, but not both: `conn`, `burst`, `default_conn_delay`, `key` or `rules`, `default_conn_delay`. |
| rules.conn | integer or string | True | | > 0 or [lua-resty-expr](https://github.com/api7/lua-resty-expr) | The maximum number of concurrent requests allowed. Requests exceeding the configured limit and below `conn + burst` will be delayed. This parameter also supports the string data type and allows the use of built-in variables prefixed with a dollar sign (`$`). |
| rules.burst | integer or string | True | | >= 0 or [lua-resty-expr](https://github.com/api7/lua-resty-expr) | The number of excessive concurrent requests allowed to be delayed. Requests exceeding `conn + burst` will be rejected immediately. This parameter also supports the string data type and allows the use of built-in variables prefixed with a dollar sign (`$`). |
| rules.key | string | True | | | The key to count requests by. If the configured key does not exist, the rule will not be executed. The `key` is interpreted as a combination of variables. All variables should be prefixed by dollar signs (`$`). |

## Examples

The examples below demonstrate how you can configure `limit-conn` in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Apply Rate Limiting by Remote Address

The following example demonstrates how to use `limit-conn` to rate limit requests by `remote_addr`, with example connection and burst thresholds.

Create a Route with `limit-conn` Plugin as such:

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

Synchronize the configuration to the gateway:

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

Apply the configuration:

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ `conn`: allow 2 concurrent requests.

❷ `burst`: allow 1 excessive concurrent request.

❸ `default_conn_delay`: Allow 0.1 second of processing latency for concurrent requests between `conn` and `conn + burst`.

❹ `key_type`: set to `var` to interpret `key` as a variable.

❺ `key`: calculate rate limiting count by request's `remote_addr`.

❻ `policy`: use the local counter in memory.

❼ `rejected_code`: set the rejection status code to `429`.

Send five concurrent requests to the route:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

You should see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

### Apply Rate Limiting by Remote Address and Consumer Name

The following example demonstrates how to use `limit-conn` to rate limit requests by a combination of variables, `remote_addr` and `consumer_name`.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

Create `key-auth` Credential for the Consumer:

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

Create a second Consumer `jane`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jane"
  }'
```

Create `key-auth` Credential for the Consumer:

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

Create a Route with `key-auth` and `limit-conn` Plugins:

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

Create two Consumers and a Route that enables rate limiting by Consumers:

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

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

Create two Consumers and a Route that enables rate limiting by Consumers:

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

Apply the configuration:

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ `key-auth`: enable key authentication on the Route.

❷ `key_type`: set to `var_combination` to interpret the `key` as a combination of variables.

❸ `key`: set to `$remote_addr $consumer_name` to apply rate limiting quota by remote address and Consumer.

Send five concurrent requests as the Consumer `john`:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "apikey: john-key"'
```

You should see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

Immediately send five concurrent requests as the Consumer `jane`:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "apikey: jane-key"'
```

You should also see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

In this case, the Plugin rate limits by the combination of variables `remote_addr` and `consumer_name`, which means each Consumer's quota is independent.

### Rate Limit WebSocket Connections

The following example demonstrates how you can use the `limit-conn` Plugin to limit the number of concurrent WebSocket connections.

Start a [sample upstream WebSocket server](https://hub.docker.com/r/jmalloc/echo-server):

```shell
docker run -d \
  -p 8080:8080 \
  --name websocket-server \
  --network=apisix-quickstart-net \
  jmalloc/echo-server
```

The server has a WebSocket endpoint at `/.ws` that echoes back any message received.

Create a Route to the server WebSocket endpoint and enable WebSocket for the Route:

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

❶ Enable WebSocket for the Route.

❷ Replace with your WebSocket server address.

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

❶ Enable WebSocket for the Route.

❷ Replace with your WebSocket server address.

Synchronize the configuration to the gateway:

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

Apply the configuration:

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

Install a WebSocket client, such as [websocat](https://github.com/vi/websocat), if you have not already. Establish connection with the WebSocket server through the Route:

```shell
websocat "ws://127.0.0.1:9080/.ws"
```

Send a "hello" message in the terminal, you should see the WebSocket server echoes back the same message:

```text
Request served by 1cd244052136
hello
hello
```

Open three more terminal sessions and run:

```shell
websocat "ws://127.0.0.1:9080/.ws"
```

You should see the last terminal session prints `429 Too Many Requests` when you try to establish a WebSocket connection with the server, due to the rate limiting effect.

### Share Quota Among APISIX Nodes with a Redis Server

The following example demonstrates the rate limiting of requests across multiple APISIX nodes with a Redis server, such that different APISIX nodes share the same rate limiting quota.

On each APISIX instance, create a Route with the following configurations. Adjust the configuration details accordingly.

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

Synchronize the configuration to the gateway:

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

Apply the configuration:

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ `policy`: set to `redis` to use a Redis instance for rate limiting.

❷ `redis_host`: set to Redis instance IP address.

❸ `redis_port`: set to Redis instance listening port.

❹ `redis_password`: set to the password of the Redis instance, if any.

❺ `redis_database`: set to the database number in the Redis instance.

Send five concurrent requests to the route:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

You should see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 429
Response: 429
Response: 429
```

This shows the two Routes configured in different APISIX instances share the same quota.

### Share Quota Among APISIX Nodes with a Redis Cluster

You can also use a Redis cluster to apply the same quota across multiple APISIX nodes, such that different APISIX nodes share the same rate limiting quota.

Ensure that your Redis instances are running in [cluster mode](https://redis.io/docs/management/scaling/#create-and-use-a-redis-cluster). Configure `redis_cluster_name` and one or more node addresses in `redis_cluster_nodes` for the `limit-conn` Plugin.

On each APISIX instance, create a Route with the following configurations. Adjust the configuration details accordingly.

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

Synchronize the configuration to the gateway:

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

Apply the configuration:

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ `policy`: set to `redis-cluster` to use a Redis cluster for rate limiting.

❷ `redis_cluster_nodes`: set to Redis node addresses in the Redis cluster.

❸ `redis_password`: set to the password of the Redis cluster, if any.

❹ `redis_cluster_name`: set to the Redis cluster name.

❺ `redis_cluster_ssl`: enable SSL/TLS communication with Redis cluster.

Send five concurrent requests to the route:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

You should see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 429
Response: 429
Response: 429
```

This shows the two Routes configured in different APISIX instances share the same quota.

### Rate Limit by Rules

The following example demonstrates how you can configure `limit-conn` to apply different rate-limiting rules based on request attributes. This feature is available from APISIX 3.16.0. In this example, rate limits are applied based on HTTP header values that represent the caller's access tier.

Note that all rules are applied sequentially. If a configured key does not exist, the corresponding rule will be skipped.

In addition to HTTP headers, you can also base rules on other built-in variables or [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) to implement more flexible and fine-grained rate-limiting strategies.

Create a Route with the `limit-conn` Plugin that applies different rate limits based on request headers, allowing requests to be rate limited per subscription (`X-Subscription-ID`) and enforcing a stricter limit for trial users (`X-Trial-ID`):

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

Synchronize the configuration to the gateway:

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

Apply the configuration:

```shell
kubectl apply -f limit-conn-ic.yaml
```

</TabItem>
</Tabs>

❶ Use the value of the `X-Subscription-ID` request header as the rate-limiting key.

❷ Set the request connection dynamically based on the `X-Custom-Conn` header. If the header is not provided, a default concurrent connection count of 5 is applied.

❸ Use the value of the `X-Trial-ID` request header as the rate-limiting key.

To verify rate limiting, send 7 concurrent requests to the Route with the same subscription ID:

```shell
seq 1 7 | xargs -n1 -P7 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "X-Subscription-ID: sub-123456789"'
```

You should see the following response, which shows that the default concurrent connection limit of 5 with a burst of 1 is applied when the `X-Custom-Conn` header is not provided:

```text
Response: 429
Response: 200
Response: 200
Response: 200
Response: 200
Response: 200
Response: 200
```

Send 5 concurrent requests to the Route with the same subscription ID and set the `X-Custom-Conn` header to 1:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "X-Subscription-ID: sub-123456789" -H "X-Custom-Conn: 1"'
```

You should see the following response, which shows that the concurrent connection limit of 1 with a burst of 1 is applied:

```text
Response: 429
Response: 429
Response: 429
Response: 200
Response: 200
```

Finally, generate 5 requests to the Route with the trial ID header:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "X-Trial-ID: trial-123456789"'
```

You should see the following response, which shows that the concurrent connection limit of 1 with a burst of 1 is applied:

```text
Response: 429
Response: 429
Response: 429
Response: 200
Response: 200
```
