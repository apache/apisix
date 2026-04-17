---
title: basic-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Basic Auth
  - basic-auth
description: The basic-auth Plugin adds basic access authentication for Consumers to authenticate themselves before being able to access Upstream resources.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/basic-auth" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `basic-auth` Plugin adds [basic access authentication](https://en.wikipedia.org/wiki/Basic_access_authentication) for [Consumers](../terminology/consumer.md) to authenticate themselves before being able to access Upstream resources.

When a Consumer is successfully authenticated, APISIX adds additional headers, such as `X-Consumer-Username`, `X-Credential-Identifier`, and other Consumer custom headers if configured, to the request, before proxying it to the Upstream service. The Upstream service will be able to differentiate between consumers and implement additional logics as needed. If any of these values is not available, the corresponding header will not be added.

## Attributes

For Consumer/Credentials:

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| username | string | True | | | Unique basic auth username for a Consumer. |
| password | string | True | | | Basic auth password for the Consumer. The password is encrypted with AES before being stored in etcd. You can also store it in an environment variable and reference it using the `env://` prefix, or in a secret manager such as HashiCorp Vault's KV secrets engine, and reference it using the `secret://` prefix. |

For Route:

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| hide_credentials | boolean | False | false | | If true, do not pass the authorization request header to Upstream services. |
| anonymous_consumer | string | False | | | Anonymous Consumer name. If configured, allow anonymous users to bypass the authentication. |
| realm | string | False | basic | | Realm in the [`WWW-Authenticate`](https://datatracker.ietf.org/doc/html/rfc7235#section-4.1) response header returned with a `401 Unauthorized` response due to authentication failure. Available in Apache APISIX version 3.15.0 and later. |

## Examples

The examples below demonstrate how you can work with the `basic-auth` Plugin for different scenarios.

:::note

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
```

:::

### Implement Basic Authentication on Route

The following example demonstrates how to implement basic authentication on a Route.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `johndoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe"
  }'
```

Create `basic-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

Create a Route with `basic-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {}
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

Create a Consumer with `basic-auth` Credential and a Route with `basic-auth` Plugin configured:

```yaml title="adc.yaml"
consumers:
  - username: johndoe
    credentials:
      - name: basic-auth
        type: basic-auth
        config:
          username: johndoe
          password: john-key
services:
  - name: basic-auth-service
    routes:
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth: {}
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

Create a Consumer with `basic-auth` Credential and a Route with `basic-auth` Plugin configured:

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: basic-auth
      name: primary-cred
      config:
        username: johndoe
        password: john-key
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
  name: basic-auth-plugin-config
spec:
  plugins:
    - name: basic-auth
      config:
        _meta:
          disable: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: basic-auth-route
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
            name: basic-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: johndoe
spec:
  ingressClassName: apisix
  authParameter:
    basicAuth:
      value:
        username: johndoe
        password: john-key
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
  name: basic-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: basic-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: basic-auth
        enable: true
```

Apply the configuration to your cluster:

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

#### Verify with Valid Credentials

Send a request to the Route with valid credentials:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66e5107c-5bb3e24f2de5baf733aec1cc",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything"
}
```

#### Verify with Invalid Credentials

Send a request with invalid credentials:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:invalid-password
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Invalid user authorization"}
```

#### Verify without Credentials

Send a request without credentials:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should see an `HTTP/1.1 401 Unauthorized` response with the following:

```text
{"message":"Missing authorization in request"}
```

### Hide Authentication Information From Upstream

The following example demonstrates how to prevent the client's credentials (the `Authorization` header) from being sent to the Upstream services by configuring `hide_credentials`. If you are using APISIX, the `Authorization` header containing the client's credentials is forwarded to the Upstream services by default, which might lead to security risks in some circumstances and you should consider updating `hide_credentials` as shown in this example.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `johndoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe"
  }'
```

Create `basic-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

#### Without Hiding Credentials

Create a Route with `basic-auth` and configure `hide_credentials` to `false`, which is the default configuration:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "id": "basic-auth-route",
  "uri": "/anything",
  "plugins": {
    "basic-auth": {
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

Create a Consumer with `basic-auth` Credential and a Route with `basic-auth` Plugin configured:

```yaml title="adc.yaml"
consumers:
  - username: johndoe
    credentials:
      - name: basic-auth
        type: basic-auth
        config:
          username: johndoe
          password: john-key
services:
  - name: basic-auth-service
    routes:
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth:
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

Create a Consumer with `basic-auth` Credential and a Route with `basic-auth` Plugin configured:

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: basic-auth
      name: primary-cred
      config:
        username: johndoe
        password: john-key
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
  name: basic-auth-plugin-config
spec:
  plugins:
    - name: basic-auth
      config:
        _meta:
          disable: false
        hide_credentials: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: basic-auth-route
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
            name: basic-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: johndoe
spec:
  ingressClassName: apisix
  authParameter:
    basicAuth:
      value:
        username: johndoe
        password: john-key
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
  name: basic-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: basic-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: basic-auth
        enable: true
        config:
          hide_credentials: false
```

Apply the configuration to your cluster:

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request with the valid credentials:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
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
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66cc2195-22bd5f401b13480e63c498c6",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 43.228.226.23",
  "url": "http://127.0.0.1/anything"
}
```

Note that the credentials are visible to the Upstream service in base64-encoded format. You can also pass the base64-encoded credentials in the request using the `Authorization` header:

```shell
curl -i "http://127.0.0.1:9080/anything" -H "Authorization: Basic am9obmRvZTpqb2huLWtleQ=="
```

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
curl "http://127.0.0.1:9180/apisix/admin/routes/basic-auth-route" -X PATCH \
-H "X-API-KEY: ${admin_key}" \
-d '{
  "plugins": {
    "basic-auth": {
      "hide_credentials": true
    }
  }
}'
```

</TabItem>

<TabItem value="adc">

Update the Route configuration:

```yaml title="adc.yaml"
# other configs
# ...
services:
  - name: basic-auth-service
    routes:
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth:
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

```yaml title="basic-auth-ic.yaml"
# other configs
# ---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: basic-auth-plugin-config
spec:
  plugins:
    - name: basic-auth
      config:
        _meta:
          disable: false
        hide_credentials: true
```

Apply the configuration to your cluster:

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

Update the ApisixRoute to set `hide_credentials` to `true`:

```yaml title="basic-auth-ic.yaml"
# other configs
# ---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: basic-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: basic-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: basic-auth
        enable: true
        config:
          hide_credentials: true
```

Apply the configuration to your cluster:

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request with the valid credentials:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
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
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66cc21a7-4f6ac87946e25f325167d53a",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 43.228.226.23",
  "url": "http://127.0.0.1/anything"
}
```

Note that the credentials are no longer visible to the Upstream service.

### Add Consumer Custom ID to Header

The following example demonstrates how you can attach a Consumer custom ID to authenticated request in the `Consumer-Custom-Id` header, which can be used to implement additional logics as needed.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Consumer `johndoe` with a custom ID label:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
    "labels": {
      "custom_id": "495aec6a"
    }
  }'
```

Create `basic-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
      }
    }
  }'
```

Create a Route with `basic-auth`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {}
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

Create a Consumer with `basic-auth` Credential and a Route with `basic-auth` Plugin enabled:

```yaml title="adc.yaml"
consumers:
  - username: johndoe
    labels:
      custom_id: "495aec6a"
    credentials:
      - name: basic-auth
        type: basic-auth
        config:
          username: johndoe
          password: john-key
services:
  - name: basic-auth-service
    routes:
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth: {}
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

To verify, send a request to the Route with the valid credentials:

```shell
curl -i "http://127.0.0.1:9080/anything" -u johndoe:john-key
```

You should see an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Authorization": "Basic am9obmRvZTpqb2huLWtleQ==",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.6.0",
    "X-Amzn-Trace-Id": "Root=1-66ea8d64-33df89052ae198a706e18c2a",
    "X-Consumer-Username": "johndoe",
    "X-Credential-Identifier": "cred-john-basic-auth",
    "X-Consumer-Custom-Id": "495aec6a",
    "X-Forwarded-Host": "127.0.0.1"
  },
  "json": null,
  "method": "GET",
  "origin": "192.168.65.1, 205.198.122.37",
  "url": "http://127.0.0.1/anything"
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

Create a regular Consumer `johndoe` and configure the `limit-count` Plugin to allow for a quota of 3 within a 30-second window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
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

Create the `basic-auth` Credential for the Consumer `johndoe`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-basic-auth",
    "plugins": {
      "basic-auth": {
        "username": "johndoe",
        "password": "john-key"
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

Create a Route and configure the `basic-auth` Plugin to accept anonymous Consumer `anonymous` from bypassing the authentication:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "basic-auth-route",
    "uri": "/anything",
    "plugins": {
      "basic-auth": {
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
  - username: johndoe
    plugins:
      limit-count:
        count: 3
        time_window: 30
        rejected_code: 429
        policy: local
    credentials:
      - name: basic-auth
        type: basic-auth
        config:
          username: johndoe
          password: john-key
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
      - name: basic-auth-route
        uris:
          - /anything
        plugins:
          basic-auth:
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

```yaml title="basic-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: johndoe
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: basic-auth
      name: primary-key
      config:
        username: johndoe
        password: john-key
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
  name: basic-auth-plugin-config
spec:
  plugins:
    - name: basic-auth
      config:
        anonymous_consumer: aic_anonymous  # namespace_consumername
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: basic-auth-route
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
            name: basic-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f basic-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

The ApisixConsumer CRD currently does not support configuring plugins on consumers, except for the authentication plugins allowed in `authParameter`. This example cannot be completed with APISIX CRDs.

</TabItem>

</Tabs>

</TabItem>

</Tabs>

To verify, send five consecutive requests with `johndoe`'s credentials:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -u johndoe:john-key -o /dev/null -s -w "%{http_code}\n") && \
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
