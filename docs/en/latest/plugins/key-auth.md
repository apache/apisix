---
title: key-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Key Auth
  - key-auth
description: The key-auth Plugin supports the use of an authentication key as a mechanism for clients to authenticate themselves before accessing Upstream resources.
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
    <link rel="canonical" href="https://docs.api7.ai/hub/key-auth" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `key-auth` Plugin supports the use of an authentication key as a mechanism for clients to authenticate themselves before accessing Upstream resources.

To use the Plugin, you would configure authentication keys on [Consumers](../terminology/consumer.md) and enable the Plugin on Routes or Services. The key can be included in the request URL query string or request header. APISIX will then verify the key to determine if a request should be allowed or denied to access Upstream resources.

When a Consumer is successfully authenticated, APISIX adds additional headers, such as `X-Consumer-Username`, `X-Credential-Identifier`, and other Consumer custom headers if configured, to the request, before proxying it to the Upstream service. The Upstream service will be able to differentiate between consumers and implement additional logic as needed. If any of these values is not available, the corresponding header will not be added.

## Attributes

For Consumer/Credential:

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| key | string | True | | | A unique key that identifies the Credential for a Consumer. When `apisix.data_encryption.enable_encrypt_fields` is enabled and the configuration is stored in etcd, the key is encrypted with AES before storage. You can also store it in an environment variable and reference it using the `$env://` prefix, or in a secret manager such as HashiCorp Vault's KV secrets engine, and reference it using the `$secret://` prefix. |

For Route:

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| header | string | False | apikey | | The header to get the key from. |
| query | string | False | apikey | | The query string to get the key from. Lower priority than `header`. |
| hide_credentials | boolean | False | false | | If true, do not pass the header or query string with key to Upstream services. |
| anonymous_consumer | string | False | | | Anonymous Consumer name. If configured, allow anonymous users to bypass the authentication. |
| realm | string | False | key | | Realm in the [`WWW-Authenticate`](https://datatracker.ietf.org/doc/html/rfc7235#section-4.1) response header returned with a `401 Unauthorized` response due to authentication failure. Available in Apache APISIX version 3.15.0 and later. |

## Examples

The examples below demonstrate how you can work with the `key-auth` Plugin for different scenarios.

:::note

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Implement Key Authentication on Route

The following example demonstrates how to implement key authentication on a Route and include the key in the request header.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

Create a Route with `key-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {}
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

Create a Consumer with `key-auth` Credential and a Route with `key-auth` Plugin configured:

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jack-key
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth: {}
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

Create a Consumer with `key-auth` Credential and a Route with `key-auth` Plugin configured:

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-cred
      config:
        key: jack-key
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
        _meta:
          disable: false
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
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: jack
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jack-key
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
```

Apply the configuration to your cluster:

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

#### Verify with a Valid Key

Send a request to the Route with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: jack-key'
```

You should receive an `HTTP/1.1 200 OK` response.

#### Verify with an Invalid Key

Send a request with an invalid key:

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: wrong-key'
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Invalid API key in request"}
```

#### Verify without a Key

Send a request to the Route without a key:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Missing API key found in request"}
```

### Hide Authentication Information From Upstream

The following example first demonstrates the default behavior, where the authentication key is forwarded to the Upstream services, and then shows how to prevent the key from being sent by configuring `hide_credentials`. Forwarding the authentication key to Upstream services might lead to security risks in some circumstances.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

#### Without Hiding Credentials

Create a Route with `key-auth` and configure `hide_credentials` to `false`, which is the default configuration:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "key-auth-route",
  "uri": "/anything",
  "plugins": {
    "key-auth": {
      "hide_credentials": false
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

Create a Consumer with `key-auth` Credential and a Route with `key-auth` Plugin configured:

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jack-key
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth:
            hide_credentials: false
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

Create a Consumer with `key-auth` Credential and a Route with `key-auth` Plugin configured:

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-cred
      config:
        key: jack-key
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
        _meta:
          disable: false
        hide_credentials: false
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
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: jack
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jack-key
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
          hide_credentials: false
```

Apply the configuration to your cluster:

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
```

You should see an `HTTP/1.1 200 OK` response with the following:

```json
{
  "args": {
    "apikey": "jack-key"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Amzn-Trace-Id": "Root=1-6502d8a5-2194962a67aa21dd33f94bb2",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 103.248.35.179",
  "url": "http://127.0.0.1/anything?apikey=jack-key"
}
```

Note that the Credential `jack-key` is visible to the Upstream service.

#### Hide Credentials

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Update the Plugin's `hide_credentials` to `true`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/key-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "key-auth": {
      "hide_credentials": true
    }
  }
}'
```

</TabItem>

<TabItem value="adc">

Update the Route configuration:

```yaml title="adc.yaml"
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth:
            hide_credentials: true
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

Update the PluginConfig to set `hide_credentials` to `true`:

```yaml title="key-auth-ic.yaml"
# other configs
# ---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: key-auth-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
        hide_credentials: true
```

Apply the configuration to your cluster:

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

Update the ApisixRoute to set `hide_credentials` to `true`:

```yaml title="key-auth-ic.yaml"
# other configs
# ---
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
          hide_credentials: true
```

Apply the configuration to your cluster:

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
```

You should see an `HTTP/1.1 200 OK` response with the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Amzn-Trace-Id": "Root=1-6502d85c-16f34dbb5629a5960183e803",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "127.0.0.1, 103.248.35.179",
  "url": "http://127.0.0.1/anything"
}
```

Note that the Credential `jack-key` is no longer visible to the Upstream service.

### Demonstrate Priority of Keys in Header and Query

The following example demonstrates how to implement key authentication by consumers on a Route and customize the URL parameter that should include the key. The example also shows that when the API key is configured in both the header and the query string, the request header has a higher priority.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

Create a Route with `key-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "key-auth-route",
  "uri": "/anything",
  "plugins": {
    "key-auth": {
      "query": "auth"
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

Create a Consumer with `key-auth` Credential and a Route with `key-auth` Plugin configured:

```yaml title="adc.yaml"
consumers:
  - username: jack
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jack-key
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth:
            query: auth
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

Create a Consumer with `key-auth` Credential and a Route with `key-auth` Plugin configured:

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-cred
      config:
        key: jack-key
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
        _meta:
          disable: false
        query: auth
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
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: jack
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jack-key
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
          query: auth
```

Apply the configuration to your cluster:

```shell
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

#### Verify with a Valid Key

Send a request to the Route with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything?auth=jack-key"
```

You should receive an `HTTP/1.1 200 OK` response.

#### Verify with an Invalid Key

Send a request with an invalid key:

```shell
curl -i "http://127.0.0.1:9080/anything?auth=wrong-key"
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Invalid API key in request"}
```

#### Verify with a Valid Key in Query String

However, if you include the valid key in header with the invalid key still in the URL query string:

```shell
curl -i "http://127.0.0.1:9080/anything?auth=wrong-key" -H 'apikey: jack-key'
```

You should see an `HTTP/1.1 200 OK` response. This shows that the key included in the header always has a higher priority.

### Add Consumer Custom ID to Header

The following example demonstrates how you can attach a Consumer custom ID to authenticated request in the `X-Consumer-Custom-Id` header, which can be used to implement additional logic as needed.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `jack` with a custom ID label:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

Create a Route with `key-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {}
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

Create a Consumer with `key-auth` Credential and a Route with `key-auth` Plugin enabled:

```yaml title="adc.yaml"
consumers:
  - username: jack
    labels:
      custom_id: "495aec6a"
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jack-key
services:
  - name: key-auth-service
    routes:
      - name: key-auth-route
        uris:
          - /anything
        plugins:
          key-auth: {}
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

Consumer custom labels are currently not supported when configuring resources through the Ingress Controller, and the `X-Consumer-Custom-Id` header is not included in requests. At the moment, this example cannot be completed with the Ingress Controller.

</TabItem>

</Tabs>

To verify, send a request to the Route with the valid key:

```shell
curl -i "http://127.0.0.1:9080/anything?apikey=jack-key"
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {
    "apikey": "jack-key"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea8d64-33df89052ae198a706e18c2a",
    "X-Consumer-Username": "jack",
    "X-Credential-Identifier": "cred-jack-key-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything?apikey=jack-key"
}
```

### Rate Limit with Anonymous Consumer

The following example demonstrates how you can configure different rate limiting policies by regular and anonymous consumers, where the anonymous Consumer does not need to authenticate and has less quota.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a regular Consumer `jack` and configure the `limit-count` Plugin to allow for a quota of 3 within a 30-second window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429,
        "policy": "local"
      }
    }
  }'
```

Create the `key-auth` Credential for the Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
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
        "rejected_code": 429,
        "policy": "local"
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

Configure Consumers with different rate limits and a Route that accepts anonymous users:

```yaml title="adc.yaml"
consumers:
  - username: jack
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
          key: jack-key
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
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

Configure Consumers with different rate limits and a Route that accepts anonymous users:

```yaml title="key-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jack
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-key
      config:
        key: jack-key
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
kubectl apply -f key-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

The ApisixConsumer CRD currently does not support configuring plugins on consumers, except for the authentication plugins allowed in `authParameter`. This example cannot be completed with APISIX CRDs.

</TabItem>

</Tabs>

</TabItem>

</Tabs>

To verify, send five consecutive requests with `jack`'s key:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jack-key' -o /dev/null -s -w "%{http_code}\n") && \
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
