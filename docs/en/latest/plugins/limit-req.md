---
title: Rate Limiting (limit-req)
keywords:
  - Apache APISIX
  - API Gateway
  - Limit Request
  - limit-req
description: The limit-req Plugin uses the leaky bucket algorithm to rate limit the number of the requests and allow for throttling.
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

## Description

The `limit-req` Plugin uses the [leaky bucket](https://en.wikipedia.org/wiki/Leaky_bucket) algorithm to rate limit the number of the requests and allow for throttling.

## Local vs Redis Rate Limiting

The `limit-req` Plugin supports two modes of rate limiting:

* **Local rate limiting**: Limits are enforced independently on each gateway instance. Each instance maintains its own counters, so the effective limit is roughly (limit × number of instances) when traffic is spread across instances. This is the default when no `policy` is set or when `policy` is `local`.
* **Redis-based rate limiting**: Limits are shared across all gateway instances through Redis. All instances share the same quota, so the configured limit applies to all gateway instances.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| rate | number | True | | > 0 | The rate at which requests are admitted, in requests per second. Excess requests within the `burst` capacity are delayed unless `nodelay` is `true`. |
| burst | number | True | | >= 0 | The maximum number of excess requests allowed above the configured `rate`. This is a burst capacity, not a per-second quota. Requests exceeding this capacity are rejected. |
| key_type | string | False | var | ["var", "var_combination"] | The type of key. If the `key_type` is `var`, the `key` is interpreted as a variable. If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. |
| key | string | True | | | The key to count requests by. If the `key_type` is `var`, the `key` is interpreted as a variable. The variable does not need to be prefixed by a dollar sign (`$`). If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. All variables should be prefixed by dollar signs (`$`). For example, to configure the `key` to use a combination of two request headers `custom-a` and `custom-b`, the `key` should be configured as `$http_custom_a $http_custom_b`. |
| rejected_code | integer | False | 503 | [200,...,599] | The HTTP status code returned when a request is rejected for exceeding the threshold. |
| rejected_msg | string | False | | non-empty | The response body returned when a request is rejected for exceeding the threshold. |
| nodelay | boolean | False | false | | If true, admit requests within the `burst` capacity without delay. Excess requests still consume burst capacity and are rejected when it is exhausted. |
| allow_degradation | boolean | False | false | | If true, allow APISIX to continue handling requests without the Plugin when the Plugin or its dependencies become unavailable. |
| policy | string | False | local | ["local", "redis", "redis-cluster"] | The policy for rate limiting counter. If it is `local`, the counter is stored in memory locally. If it is `redis`, the counter is stored on a Redis instance. If it is `redis-cluster`, the counter is stored in a Redis cluster. |
| redis_host | string | False | | | The address of the Redis node. Required when `policy` is `redis`. |
| redis_port | integer | False | 6379 | [1,...] | The port of the Redis node when `policy` is `redis`. |
| redis_username | string | False | | | The username for Redis if Redis ACL is used. If you use the legacy authentication method `requirepass`, configure only the `redis_password`. Used when `policy` is `redis`. |
| redis_password | string | False | | | The password of the Redis node when `policy` is `redis` or `redis-cluster`. |
| redis_ssl | boolean | False | false | | If true, use SSL to connect to Redis when `policy` is `redis`. |
| redis_ssl_verify | boolean | False | false | | If true, verify the server SSL certificate when `policy` is `redis`. |
| redis_server_name | string | False | | | TLS SNI when `policy` is `redis` and `redis_ssl` is true. Defaults to `redis_host`. When `redis_ssl_verify` is true the certificate must also match this name, so set it when `redis_host` is an alias the certificate does not cover. |
| redis_database | integer | False | 0 | >= 0 | The database number in Redis when `policy` is `redis`. |
| redis_timeout | integer | False | 1000 | [1,...] | The Redis timeout value in milliseconds when `policy` is `redis` or `redis-cluster`. |
| redis_keepalive_timeout | integer | False | 10000 | ≥ 1000 | Keepalive timeout in milliseconds for redis when `policy` is `redis` or `redis-cluster`. |
| redis_keepalive_pool | integer | False | 100 | ≥ 1 | Keepalive pool size for redis when `policy` is `redis` or `redis-cluster`. |
| redis_cluster_nodes | array[string] | False | | | The list of the Redis cluster nodes with at least one address. Required when policy is redis-cluster. |
| redis_cluster_name | string | False | | | The name of the Redis cluster. Required when `policy` is `redis-cluster`. |
| redis_cluster_ssl | boolean | False | false | | If true, use SSL to connect to Redis cluster when `policy` is `redis-cluster`. |
| redis_cluster_ssl_verify | boolean | False | false | | If true, verify the server SSL certificate when `policy` is `redis-cluster`. |

NOTE: `encrypt_fields = {"redis_password"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

## Examples

The examples below demonstrate how you can configure `limit-req` in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Apply Rate Limiting by Remote Address

The following example demonstrates the rate limiting of HTTP requests by a single variable, `remote_addr`.

Create a Route with `limit-req` Plugin that allows for 1 QPS per remote address:

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

Synchronize the configuration to the gateway:

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

Apply the configuration:

```shell
kubectl apply -f limit-req-ic.yaml
```

</TabItem>

</Tabs>

❶ `rate`: limit the QPS to 1.

❷ `key`: set to `remote_addr` to apply rate limiting quota by remote address.

❸ `key_type`: set to `var` to interpret the `key` as a variable.

Send a request to verify:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response.

With `rate` set to 1 and `burst` set to 0, a second request arriving less than one second after the first is rejected with `HTTP/1.1 429 Too Many Requests`. The leaky bucket drains continuously; it does not reset at the start of each second.

### Implement API Throttling

The following example demonstrates how to configure `burst` to allow overrun of the rate limiting threshold by the configured value and achieve request throttling. You will also see a comparison against when throttling is not implemented.

Create a Route with `limit-req` Plugin that allows for 1 QPS per remote address, with a `burst` of 1 to allow for 1 request exceeding the `rate` to be delayed for processing:

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

Synchronize the configuration to the gateway:

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

Apply the configuration:

```shell
kubectl apply -f limit-req-ic.yaml
```

</TabItem>

</Tabs>

❶ `burst`: allow for 1 request exceeding the `rate` to be delayed for processing.

Wait for any previous burst to drain, then send three requests to the Route in parallel:

```shell
sleep 2
resp=$(seq 3 | xargs -P 3 -I{} curl "http://127.0.0.1:9080/get" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200 responses: $count_200 ; 429 responses: $count_429"
```

With an initially empty bucket and all three requests arriving together, one request proceeds immediately, one is delayed by about one second, and one is rejected:

```text
200 responses: 2 ; 429 responses: 1
```

To admit the excess request without delaying it, keep `burst` set to 1 and set `nodelay` to `true`:

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

Update the ADC YAML with `nodelay: true`:

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
            nodelay: true
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration with updated plugin settings:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

Update the manifest file as such:

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
        burst: 1
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
            burst: 1
            key: remote_addr
            rejected_code: 429
            policy: local
            nodelay: true
```

</TabItem>

</Tabs>

Apply the updated configuration:

```shell
kubectl apply -f limit-req-ic.yaml
```

</TabItem>

</Tabs>

Wait for the bucket to drain, then send three requests in parallel again:

```shell
sleep 2
resp=$(seq 3 | xargs -P 3 -I{} curl "http://127.0.0.1:9080/get" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200 responses: $count_200 ; 429 responses: $count_429"
```

The expected counts are the same, but both accepted requests now proceed without a throttling delay:

```text
200 responses: 2 ; 429 responses: 1
```

The counts can vary if requests arrive far enough apart for the bucket to drain. Sending requests serially can hide the effect of `burst`, because each delayed request gives the bucket time to drain before the next request arrives.

To reject excess requests instead of allowing a burst, set `burst` to 0. For three requests arriving together at `rate: 1`, one succeeds and two are rejected, regardless of `nodelay`.

### Apply Rate Limiting by Remote Address and Consumer Name

The following example demonstrates the rate limiting of requests by a combination of variables, `remote_addr` and `consumer_name`.

Create a Route with `limit-req` Plugin that allows for 1 QPS per remote address and for each Consumer.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `john`:

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

Create a Route with `key-auth` and `limit-req` Plugins:

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

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

Create two Consumers and a Route that enables rate limiting by Consumers:

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

Apply the configuration:

```shell
kubectl apply -f limit-req-ic.yaml
```

</TabItem>

</Tabs>

❶ `key-auth`: enable key authentication on the Route.

❷ `key`: set to `$remote_addr $consumer_name` to apply rate limiting quota by remote address and Consumer.

❸ `key_type`: set to `var_combination` to interpret the `key` as a combination of variables.

Send two requests simultaneously, each for one Consumer:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jane-key' & \
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key' &
```

You should receive `HTTP/1.1 200 OK` for both requests, indicating the request has not exceeded the threshold for each Consumer.

If you send more requests as either Consumer within the same second, you should receive an `HTTP/1.1 429 Too Many Requests` response.

This verifies the Plugin rate limits by the combination of variables, `remote_addr` and `consumer_name`.
