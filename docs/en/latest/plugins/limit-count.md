---
title: Rate Limiting by Count (limit-count)
keywords:
  - Apache APISIX
  - API Gateway
  - Limit Count
description: The limit-count plugin uses fixed or sliding window algorithms to limit the rate of requests by the number of requests within a given time interval. Requests exceeding the configured quota will be rejected.
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

## Description

The `limit-count` plugin uses fixed or sliding window algorithms to limit the rate of requests by the number of requests within a given time interval. Requests exceeding the configured quota will be rejected.

You may see the following rate limiting headers in the response:

* `X-RateLimit-Limit`: the total quota
* `X-RateLimit-Remaining`: the remaining quota
* `X-RateLimit-Reset`: number of seconds left for the counter to reset

## Attributes

| Name                    | Type    | Required                                  | Default       | Valid values                           | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ----------------------- | ------- | ----------------------------------------- | ------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| count                   | integer or string | False                                     |               | > 0                              | The maximum number of requests allowed within a given time interval. Required if `rules` is not configured. Supports [lua-resty-expr](https://github.com/api7/lua-resty-expr) from APISIX 3.16.0. |
| time_window             | integer or string | False                                     |               | > 0                        | The time interval corresponding to the rate limiting `count` in seconds. Required if `rules` is not configured. Supports [lua-resty-expr](https://github.com/api7/lua-resty-expr) from APISIX 3.16.0. |
| window_type             | string            | False                                     | fixed         | ["fixed","sliding"]              | The window algorithm used by the plugin. |
| rules                   | array[object]     | False                                     |               |                            | A list of rate limiting rules. Each rule is an object containing `count`, `time_window`, and `key`. |
| rules.count             | integer or string | True                                      |               | > 0                        | The maximum number of requests allowed within a given time interval. Supports [lua-resty-expr](https://github.com/api7/lua-resty-expr). |
| rules.time_window       | integer or string | True                                      |               | > 0                        | The time interval corresponding to the rate limiting `count` in seconds. Supports [lua-resty-expr](https://github.com/api7/lua-resty-expr). |
| rules.key               | string            | True                                      |               |                            | The key to count requests by. If the configured key does not exist, the rule will not be executed. The `key` is interpreted as a combination of variables, for example: `$http_custom_a $http_custom_b`. |
| rules.header_prefix     | string            | False                                     |               |                            | Prefix for rate limit headers. If configured, the response will include `X-{header_prefix}-RateLimit-Limit`, `X-{header_prefix}-RateLimit-Remaining`, and `X-{header_prefix}-RateLimit-Reset` headers. If not configured, the index of the rule in the rules array is used as the prefix. |
| key_type                | string            | False                                     | var           | ["var","var_combination","constant"] | The type of key. If the `key_type` is `var`, the `key` is interpreted as a variable. If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. If the `key_type` is `constant`, the `key` is interpreted as a constant. |
| key                     | string            | False                                     | remote_addr   |                            | The key to count requests by. If the `key_type` is `var`, the `key` is interpreted as a variable. The variable does not need to be prefixed by a dollar sign (`$`). If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. All variables should be prefixed by dollar signs (`$`). If the `key_type` is `constant`, the `key` is interpreted as a constant value. |
| rejected_code           | integer           | False                                     | 503           | [200,...,599]              | The HTTP status code returned when a request is rejected for exceeding the threshold. |
| rejected_msg            | string            | False                                     |               | non-empty                  | The response body returned when a request is rejected for exceeding the threshold. |
| policy                  | string            | False                                     | local         | ["local","redis","redis-cluster","redis-sentinel"] | The policy for the rate limiting counter. If it is `local`, the counter is stored in local memory. If it is `redis`, the counter is stored on a Redis instance. If it is `redis-cluster`, the counter is stored in a Redis cluster. If it is `redis-sentinel`, the counter is stored on the Redis master discovered through Sentinel. |
| allow_degradation       | boolean           | False                                     | false         |                            | If true, allow APISIX to continue handling requests without the plugin when the plugin or its dependencies become unavailable. |
| show_limit_quota_header | boolean           | False                                     | true          |                            | If true, include `X-RateLimit-Limit` to show the total quota and `X-RateLimit-Remaining` to show the remaining quota in the response header. |
| sync_interval           | number            | False                                     |               | -1 or >= 0.1               | The delayed synchronization interval in seconds for Redis-based policies. Set to `-1` to disable delayed synchronization explicitly. |
| group                   | string            | False                                     |               | non-empty                  | The `group` ID for the plugin, such that routes of the same `group` can share the same rate limiting counter. |
| redis_host              | string            | False                                     |               |                            | The address of the Redis node. Required when `policy` is `redis`. |
| redis_port              | integer           | False                                     | 6379          | [1,...]                    | The port of the Redis node when `policy` is `redis`. |
| redis_username          | string            | False                                     |               |                            | The username for Redis if Redis ACL is used. If you use the legacy authentication method `requirepass`, configure only the `redis_password`. Used when `policy` is `redis` or `redis-sentinel`. |
| redis_password          | string            | False                                     |               |                            | The password of the Redis node when `policy` is `redis`, `redis-cluster`, or `redis-sentinel`. |
| redis_ssl               | boolean           | False                                     | false         |                            | If true, use SSL to connect to Redis when `policy` is `redis`. |
| redis_ssl_verify        | boolean           | False                                     | false         |                            | If true, verify the server SSL certificate when `policy` is `redis`. |
| redis_database          | integer           | False                                     | 0             | >= 0                       | The database number in Redis when `policy` is `redis` or `redis-sentinel`. |
| redis_timeout           | integer           | False                                     | 1000          | [1,...]                    | The Redis timeout value in milliseconds when `policy` is `redis` or `redis-cluster`. |
| redis_keepalive_timeout | integer           | False                                     | 10000         | ≥ 1000                     | Keepalive timeout in milliseconds for Redis when `policy` is `redis` or `redis-cluster`. |
| redis_keepalive_pool    | integer           | False                                     | 100           | ≥ 1                        | Keepalive pool size for Redis when `policy` is `redis` or `redis-cluster`. |
| redis_cluster_nodes     | array[string]     | False                                     |               |                            | The list of Redis cluster nodes with at least one address. Required when `policy` is `redis-cluster`. |
| redis_cluster_name      | string            | False                                     |               |                            | The name of the Redis cluster. Required when `policy` is `redis-cluster`. |
| redis_cluster_ssl       | boolean           | False                                     | false         |                            | If true, use SSL to connect to Redis when `policy` is `redis-cluster`. |
| redis_cluster_ssl_verify| boolean           | False                                     | false         |                            | If true, verify the server SSL certificate when `policy` is `redis-cluster`. |
| redis_sentinels         | array[object]     | False                                     |               |                            | The list of Sentinel nodes. Required when `policy` is `redis-sentinel`. Each item must contain `host` and `port`. |
| redis_master_name       | string            | False                                     |               |                            | The Redis master name monitored by Sentinel. Required when `policy` is `redis-sentinel`. |
| redis_role              | string            | False                                     | master        | ["master","slave"]      | The Redis role selected through Sentinel. |
| redis_connect_timeout   | integer           | False                                     | 1000          | [1,...]                    | The Redis connection timeout in milliseconds when `policy` is `redis-sentinel`. |
| redis_read_timeout      | integer           | False                                     | 1000          | [1,...]                    | The Redis read timeout in milliseconds when `policy` is `redis-sentinel`. |
| sentinel_username       | string            | False                                     |               |                            | The username for Redis Sentinel if Sentinel ACL is enabled. |
| sentinel_password       | string            | False                                     |               |                            | The password for Redis Sentinel if Sentinel ACL is enabled. |

NOTE: `encrypt_fields = {"redis_password", "sentinel_password"}` is also defined in the schema, which means that the fields will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

## Examples

The examples below demonstrate how you can configure `limit-count` in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Apply Rate Limiting by Remote Address

The following example demonstrates the rate limiting of requests by a single variable, `remote_addr`.

Create a Route with `limit-count` plugin that allows for a quota of 1 within a 30-second window per remote address:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

Send a request to verify:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response.

The request has consumed all the quota allowed for the time window. If you send the request again within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response, indicating the request surpasses the quota threshold.

### Apply Rate Limiting by Remote Address and Consumer Name

The following example demonstrates the rate limiting of requests by a combination of variables, `remote_addr` and `consumer_name`. It allows for a quota of 1 within a 30-second window per remote address and for each consumer.

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

Create `key-auth` Credential for the consumer:

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

Create a Route with `key-auth` and `limit-count` plugins, and specify in the `limit-count` plugin to use a combination of variables as the rate limiting key. The `key-auth` plugin enables key authentication on the route. The `key_type` is set to `var_combination` to interpret the `key` as a combination of variables, and `key` is set to `$remote_addr $consumer_name` to apply rate limiting quota by remote address and for each consumer:

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

Create two consumers and a route that enables rate limiting by consumers. The `key-auth` plugin enables key authentication on the route. The `key_type` is set to `var_combination` to interpret the `key` as a combination of variables, and `key` is set to `$remote_addr $consumer_name` to apply rate limiting quota by remote address and for each consumer:

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

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

Create two consumers and a route that enables rate limiting by consumers. The `key-auth` plugin enables key authentication on the route. The `key_type` is set to `var_combination` to interpret the `key` as a combination of variables, and `key` is set to `$remote_addr $consumer_name` to apply rate limiting quota by remote address and for each consumer:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

Send a request as the Consumer `jane`:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jane-key'
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body.

This request has consumed all the quota set for the time window. If you send the same request as the Consumer `jane` within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response, indicating the request surpasses the quota threshold.

Send the same request as the Consumer `john` within the same 30-second time interval:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body, indicating the request is not rate limited.

Send the same request as the Consumer `john` again within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response.

This verifies the plugin rate limits by the combination of variables, `remote_addr` and `consumer_name`.

### Share Quota among Routes

The following example demonstrates the sharing of rate limiting quota among multiple routes by configuring the `group` of the `limit-count` plugin.

Note that the configurations of the `limit-count` plugin of the same `group` should be identical. To avoid update anomalies and repetitive configurations, you can create a Service with `limit-count` plugin and Upstream for routes to connect to.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a service:

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

Create two Routes and configure their `service_id` to be `limit-count-service`, so that they share the same configurations for the Plugin and Upstream:

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

Create a service with two routes that share the same rate limiting quota:

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

Create two HTTPRoutes that reference the same PluginConfig to share quota:

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

Create an ApisixRoute with multiple paths that share the same plugin configuration:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

:::note

The [`proxy-rewrite`](./proxy-rewrite.md) plugin is used to rewrite the URI to `/get` so that requests are forwarded to the correct endpoint.

:::

Send a request to Route `/get1`:

```shell
curl -i "http://127.0.0.1:9080/get1"
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body.

Send the same request to Route `/get2` within the same 30-second time interval:

```shell
curl -i "http://127.0.0.1:9080/get2"
```

You should receive an `HTTP/1.1 429 Too Many Requests` response, which verifies the two routes share the same rate limiting quota.

### Share Quota Among APISIX Nodes with a Redis Server

The following example demonstrates the rate limiting of requests across multiple APISIX nodes with a Redis server, such that different APISIX nodes share the same rate limiting quota.

On each APISIX instance, create a Route with the following configurations. Adjust the address of the Admin API, Redis host, port, password, and database accordingly.

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

Create a route with Redis-based rate limiting. Set `policy` to `redis` to use a Redis instance for rate limiting. Configure the `redis_host`, `redis_port`, `redis_password`, and `redis_database` to match your Redis instance:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

Send a request to an APISIX instance:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body.

Send the same request to a different APISIX instance within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response, verifying routes configured in different APISIX nodes share the same quota.

### Share Quota Among APISIX Nodes with a Redis Cluster

You can also use a Redis cluster to apply the same quota across multiple APISIX nodes, such that different APISIX nodes share the same rate limiting quota.

Ensure that your Redis instances are running in [cluster mode](https://redis.io/docs/management/scaling/#create-and-use-a-redis-cluster). A minimum of two nodes are required for the `limit-count` plugin configurations.

On each APISIX instance, create a Route with the following configurations. Adjust the address of the Admin API, Redis cluster nodes, password, cluster name, and SSL verification accordingly.

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

Create a route with Redis cluster-based rate limiting. Set `policy` to `redis-cluster` to use a Redis cluster for rate limiting. Configure `redis_cluster_nodes` with the Redis node addresses, `redis_password` with the cluster password, `redis_cluster_name` with the cluster name, and enable `redis_cluster_ssl` for SSL/TLS communication:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

Send a request to an APISIX instance:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body.

Send the same request to a different APISIX instance within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response, verifying routes configured in different APISIX nodes share the same quota.

### Share Quota Among APISIX Nodes with Redis Sentinel

The following example demonstrates rate limiting across multiple APISIX nodes using Redis with [Sentinel](https://redis.io/docs/management/sentinel/) for high availability. Sentinel monitors the Redis master and promotes a replica if the master fails. APISIX discovers the current master through the configured Sentinel nodes, so the shared quota survives a failover without configuration changes.

On each APISIX instance, create a Route with the following configurations. Adjust the Admin API address, Sentinel nodes, master name, and credentials accordingly:

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

If Sentinel ACL is not enabled, omit `sentinel_password`. For ACL-based authentication, use `redis_username`/`redis_password` for the Redis data nodes and `sentinel_username`/`sentinel_password` for the Sentinel nodes.

Send a request to an APISIX instance:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response. Sending the same request again within the 30-second window returns `HTTP/1.1 429 Too Many Requests`. If the Redis master fails over, Sentinel promotes a replica and APISIX continues enforcing the shared quota against the new master.

### Apply Sliding Window Rate Limiting

By default, `limit-count` uses a fixed window, where the counter resets at the start of each `time_window`. Around a window boundary this can allow up to twice the configured rate, since a client may exhaust the quota at the end of one window and again at the start of the next.

Set `window_type` to `sliding` to use a sliding window, which weights the previous window's count to smooth enforcement across boundaries. `window_type` works with all policies (`local`, `redis`, `redis-cluster`, and `redis-sentinel`).

Create a Route with the following configurations:

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

Send requests to the Route:

```shell
curl -i "http://127.0.0.1:9080/get"
```

The first 10 requests within 60 seconds return `HTTP/1.1 200 OK` and the 11th returns `HTTP/1.1 429 Too Many Requests`. Unlike a fixed window, the quota does not fully reset at the 60-second boundary; the window slides continuously, preventing a burst of up to twice the rate around the boundary.

### Reduce Redis Round Trips with Delayed Synchronization

For Redis-based policies (`redis`, `redis-cluster`, and `redis-sentinel`), APISIX synchronizes the counter with Redis on every request by default. On high-traffic routes, this adds a Redis round trip to each request.

Set `sync_interval` (in seconds) to synchronize in batches instead: between intervals the counter is served from local memory and reconciled with Redis once per interval. This reduces Redis round trips and tail latency, at the cost of the global count lagging by up to one interval's local delta. Set `sync_interval` to `-1` (the default behavior) to synchronize on every request.

Create a Route with the following configurations. Adjust the Redis connection settings accordingly:

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

`sync_interval` must be at least `0.1` and smaller than `time_window`. Delayed synchronization uses the `plugin-limit-count-lock` shared dictionary, which is provisioned by default, so no additional configuration is required.

Send requests to the Route:

```shell
curl -i "http://127.0.0.1:9080/get"
```

Requests are counted locally and reconciled with Redis every second. Once the quota of 1000 requests within 60 seconds is reached, further requests return `HTTP/1.1 429 Too Many Requests`.

### Rate Limit with Anonymous Consumer

The following example demonstrates how you can configure different rate limiting policies for regular and anonymous Consumers, where the anonymous Consumer does not need to authenticate and has less quota. While this example uses [`key-auth`](./key-auth.md) for authentication, the anonymous Consumer can also be configured with [`basic-auth`](./basic-auth.md), [`jwt-auth`](./jwt-auth.md), and [`hmac-auth`](./hmac-auth.md).

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a regular Consumer `john` and configure the `limit-count` plugin to allow for a quota of 3 within a 30-second window:

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

Create the `key-auth` Credential for the Consumer `john`:

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

Create an anonymous user `anonymous` and configure the `limit-count` Plugin to allow for a quota of 1 within a 30-second window:

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

Create a Route and configure the `key-auth` Plugin to accept anonymous Consumer `anonymous` from bypassing the authentication:

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

Configure consumers with different rate limits and a route that accepts anonymous users:

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

Configure consumers with different rate limits and a route that accepts anonymous users:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

Configure consumers with different rate limits and a route that accepts anonymous users:

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
            anonymous_consumer: aic_anonymous
```

Apply the configuration to your cluster:

```shell
kubectl apply -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

To verify, send five consecutive requests with `john`'s key:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: john-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 5 requests, 3 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    3, 429:    2
```

Send five anonymous requests:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that only one request was successful:

```text
200:    1, 429:    4
```

### Customize Rate Limiting Headers

The following example demonstrates how you can use Plugin metadata to customize the rate limiting response header names, which are by default `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset`.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Configure Plugin metadata to customize rate limiting headers:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/limit-count" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "limit_header": "X-Custom-RateLimit-Limit",
    "remaining_header": "X-Custom-RateLimit-Remaining",
    "reset_header": "X-Custom-RateLimit-Reset"
  }'
```

Create a Route with `limit-count` Plugin:

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

Configure plugin metadata and create a route with rate limiting:

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

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

Update your GatewayProxy manifest for the plugin metadata:

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
      # your control plane connection configuration
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

Create a route with the plugin enabled:

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

Create a route with the plugin enabled:

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

Apply the configuration to your cluster:

```shell
kubectl apply -f gatewayproxy.yaml -f limit-count-ic.yaml
```

</TabItem>

</Tabs>

Send a request to verify:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should receive an `HTTP/1.1 200 OK` response and see the following headers:

```text
X-Custom-RateLimit-Limit: 1
X-Custom-RateLimit-Remaining: 0
X-Custom-RateLimit-Reset: 28
```
