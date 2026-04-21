---
title: consumer-restriction
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - consumer-restriction
description: The consumer-restriction Plugin implements access controls based on Consumer name, Route ID, Service ID, or Consumer Group ID, enhancing API security.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/consumer-restriction" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `consumer-restriction` Plugin enables access controls based on Consumer name, Route ID, Service ID, or Consumer Group ID.

The Plugin needs to work with authentication plugins, such as [`key-auth`](./key-auth.md) and [`jwt-auth`](./jwt-auth.md), which means you should always create at least one [Consumer](../terminology/consumer.md) in your use case. See examples below for more details.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| type | string | False | consumer_name | consumer_name, service_id, route_id, consumer_group_id | Basis for restriction. Determines what value is checked against the allowlist or denylist. |
| whitelist | array[string] | False | | | List of allowed values. At least one of `whitelist`, `blacklist`, or `allowed_by_methods` must be configured. |
| blacklist | array[string] | False | | | List of denied values. At least one of `whitelist`, `blacklist`, or `allowed_by_methods` must be configured. |
| allowed_by_methods | array[object] | False | | | List of objects specifying allowed HTTP methods per Consumer. At least one of `whitelist`, `blacklist`, or `allowed_by_methods` must be configured. |
| allowed_by_methods[].user | string | False | | | Consumer name. |
| allowed_by_methods[].methods | array[string] | False | | GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE, PURGE | List of HTTP methods allowed for the Consumer. |
| rejected_code | integer | False | 403 | >= 200 | HTTP status code returned when the request is rejected. |
| rejected_msg | string | False | | | Message returned to the client when the request is rejected. |

## Examples

The examples below demonstrate how you can configure the `consumer-restriction` Plugin for different scenarios.

While the examples use [`key-auth`](./key-auth.md) as the authentication method, you can easily adjust to other authentication plugins based on your needs.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
```

:::

### Restrict Access by Consumers

The example below demonstrates how you can use the `consumer-restriction` Plugin on a Route to restrict Consumer access by Consumer names, where Consumers are authenticated with [`key-auth`](./key-auth.md).

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `JohnDoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JohnDoe"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JohnDoe/credentials" -X PUT \
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

Create a second Consumer `JaneDoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JaneDoe"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JaneDoe/credentials" -X PUT \
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

Next, create a Route with key authentication enabled, and configure `consumer-restriction` to allow only Consumer `JaneDoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "consumer-restricted-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "consumer-restriction": {
        "whitelist": ["JaneDoe"]
      }
    },
    "upstream" : {
      "nodes": {
        "httpbin.org":1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
consumers:
  - username: JohnDoe
    credentials:
      - name: cred-john-key-auth
        type: key-auth
        config:
          key: john-key
  - username: JaneDoe
    credentials:
      - name: cred-jane-key-auth
        type: key-auth
        config:
          key: jane-key
services:
  - name: consumer-restriction-service
    routes:
      - name: consumer-restricted-route
        uris:
          - /get
        plugins:
          key-auth: {}
          consumer-restriction:
            whitelist:
              - "JaneDoe"
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

When Consumers are configured using the Ingress Controller, the Consumer name is generated in the format `namespace_consumername`. For example, a Consumer named `janedoe` in the `aic` namespace becomes `aic_janedoe`. Use this format in the `whitelist` or `blacklist` of `consumer-restriction`.

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="consumer-restriction-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: john-key-auth
      config:
        key: john-key
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: janedoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: jane-key-auth
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
  name: consumer-restriction-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: consumer-restriction
      config:
        whitelist:
          - "aic_janedoe"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: consumer-restriction-route
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
            name: consumer-restriction-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="consumer-restriction-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: johndoe
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
  name: janedoe
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
  name: consumer-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: consumer-restriction-route
      match:
        paths:
          - /get
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
      - name: consumer-restriction
        enable: true
        config:
          whitelist:
            - "aic_janedoe"
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f consumer-restriction-ic.yaml
```

</TabItem>

</Tabs>

Send a request to the Route as Consumer `JohnDoe`:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

You should receive an `HTTP/1.1 403 Forbidden` response with the following message:

```text
{"message":"The consumer_name is forbidden."}
```

Send another request to the Route as Consumer `JaneDoe`:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jane-key'
```

You should receive an `HTTP/1.1 200 OK` response, showing the Consumer access is permitted.

### Restrict Access by Consumers and HTTP Methods

The example below demonstrates how you can use the `consumer-restriction` Plugin on a Route to restrict Consumer access by Consumer name and HTTP methods, where Consumers are authenticated with [`key-auth`](./key-auth.md).

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `JohnDoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JohnDoe"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JohnDoe/credentials" -X PUT \
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

Create a second Consumer `JaneDoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JaneDoe"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JaneDoe/credentials" -X PUT \
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

Next, create a Route with key authentication enabled, and use `consumer-restriction` to allow only the configured HTTP methods by Consumers:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "consumer-restricted-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {},
      "consumer-restriction": {
        "allowed_by_methods":[
          {
            "user": "JohnDoe",
            "methods": ["GET"]
          },
          {
            "user": "JaneDoe",
            "methods": ["POST"]
          }
        ]
      }
    },
    "upstream" : {
      "nodes": {
        "httpbin.org":1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
consumers:
  - username: JohnDoe
    credentials:
      - name: cred-john-key-auth
        type: key-auth
        config:
          key: john-key
  - username: JaneDoe
    credentials:
      - name: cred-jane-key-auth
        type: key-auth
        config:
          key: jane-key
services:
  - name: consumer-restriction-service
    routes:
      - name: consumer-restricted-route
        uris:
          - /anything
        plugins:
          key-auth: {}
          consumer-restriction:
            allowed_by_methods:
              - user: "JohnDoe"
                methods:
                  - "GET"
              - user: "JaneDoe"
                methods:
                  - "POST"
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
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="consumer-restriction-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: john-key-auth
      config:
        key: john-key
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: janedoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: jane-key-auth
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
  name: consumer-restriction-methods-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: consumer-restriction
      config:
        allowed_by_methods:
          - user: "aic_johndoe"
            methods:
              - "GET"
          - user: "aic_janedoe"
            methods:
              - "POST"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: consumer-restriction-route
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
            name: consumer-restriction-methods-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f consumer-restriction-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="consumer-restriction-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: johndoe
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
  name: janedoe
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
  name: consumer-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: consumer-restriction-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
      - name: consumer-restriction
        enable: true
        config:
          allowed_by_methods:
            - user: "aic_johndoe"
              methods:
                - "GET"
            - user: "aic_janedoe"
              methods:
                - "POST"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f consumer-restriction-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a POST request to the Route as Consumer `JohnDoe`:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST -H 'apikey: john-key'
```

You should receive an `HTTP/1.1 403 Forbidden` response with the following message:

```text
{"message":"The consumer_name is forbidden."}
```

Now, send a GET request to the Route as Consumer `JohnDoe`:

```shell
curl -i "http://127.0.0.1:9080/anything" -X GET -H 'apikey: john-key'
```

You should receive an `HTTP/1.1 200 OK` response, showing the Consumer access is permitted.

You can also verify the configurations by sending requests as Consumer `JaneDoe` and observe the behaviours match up to what was configured in the `consumer-restriction` Plugin on the Route.

### Restricting by Service ID

The example below demonstrates how you can use the `consumer-restriction` Plugin to restrict Consumer access by Service ID, where the Consumer is authenticated with [`key-auth`](./key-auth.md).

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create two sample Services:

```shell
curl "http://127.0.0.1:9180/apisix/admin/services" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "srv-1",
    "plugins": {
      "key-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org":1
      }
    }
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/services" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "srv-2",
    "plugins": {
      "key-auth": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "mock.api7.ai":1
      }
    }
  }'
```

Next, create a Consumer and configure `consumer-restriction` to allow only `srv-1` Service:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "JohnDoe",
    "plugins": {
      "consumer-restriction": {
        "type": "service_id",
        "whitelist": ["srv-1"]
      }
    }
  }'
```

Create a `key-auth` credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/JohnDoe/credentials" -X PUT \
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

Finally, create two Routes, with each belonging to one of the Services created earlier:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "srv-1-route",
    "uri": "/anything",
    "service_id": "srv-1"
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "srv-2-route",
    "uri": "/srv-2",
    "service_id": "srv-2"
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
consumers:
  - username: JohnDoe
    credentials:
      - name: cred-john-key-auth
        plugins:
          key-auth:
            key: john-key
    plugins:
      consumer-restriction:
        type: service_id
        whitelist:
          - "srv-1"
services:
  - name: srv-1
    plugins:
      key-auth: {}
    routes:
      - name: srv-1-route
        uris:
          - /anything
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
  - name: srv-2
    plugins:
      key-auth: {}
    routes:
      - name: srv-2-route
        uris:
          - /srv-2
    upstream:
      type: roundrobin
      nodes:
        - host: mock.api7.ai
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

When Routes are configured using the Ingress Controller, APISIX Service IDs are auto-generated as the hash of `{namespace}_{routeName}_{ruleIndex}`. These IDs cannot be easily predetermined. Consider using Consumer name-based restriction instead.

</TabItem>

</Tabs>

Send a request to the Route in the `srv-1` Service:

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: john-key'
```

You should receive an `HTTP/1.1 200 OK` response, showing the Consumer access is permitted.

Send a request to the Route in the `srv-2` Service:

```shell
curl -i "http://127.0.0.1:9080/srv-2" -H 'apikey: john-key'
```

You should receive an `HTTP/1.1 403 Forbidden` response with the following message:

```text
{"message":"The service_id is forbidden."}
```
