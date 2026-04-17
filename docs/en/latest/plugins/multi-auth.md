---
title: multi-auth
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Multi Auth
  - multi-auth
description: The multi-auth plugin enables consumers using diverse authentication methods to share the same route or service, streamlining API lifecycle management.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/multi-auth" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `multi-auth` Plugin allows Consumers using different authentication methods to share the same Route or Service. It supports the configuration of multiple authentication Plugins, so that a request would be allowed through if it authenticates successfully against any configured authentication method.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| auth_plugins | array | True | - | | An array of at least two authentication Plugins. |

## Examples

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Allow Different Authentications on the Same Route

The following example demonstrates how to have one Consumer using basic authentication, while another Consumer using key authentication, both sharing the same Route.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create two Consumers:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username":"consumer1"
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username":"consumer2"
  }'
```

Configure basic authentication Credential for `consumer1`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/consumer1/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "basic-auth": {
        "username":"consumer1",
        "password":"consumer1_pwd"
      }
    }
  }'
```

Configure key authentication Credential for `consumer2`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/consumer2/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "key-auth": {
        "key":"consumer2_pwd"
      }
    }
  }'
```

Create a Route with `multi-auth` and configure the two authentication Plugins that Consumers use:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "multi-auth-route",
    "uri": "/anything",
    "plugins": {
      "multi-auth":{
        "auth_plugins":[
          {
            "basic-auth":{}
          },
          {
            "key-auth":{
              "hide_credentials":true,
              "header":"apikey",
              "query":"apikey"
            }
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

Create two Consumers with their respective Credentials and a Route with `multi-auth`:

```yaml title="adc.yaml"
consumers:
  - username: consumer1
    credentials:
      - name: cred-consumer1-basic-auth
        type: basic-auth
        config:
          username: consumer1
          password: consumer1_pwd
  - username: consumer2
    credentials:
      - name: cred-consumer2-key-auth
        type: key-auth
        config:
          key: consumer2_pwd
services:
  - name: multi-auth-service
    routes:
      - name: multi-auth-route
        uris:
          - /anything
        plugins:
          multi-auth:
            auth_plugins:
              - basic-auth: {}
              - key-auth:
                  hide_credentials: true
                  header: apikey
                  query: apikey
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

```yaml title="multi-auth-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: consumer1
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: basic-auth
      name: cred-consumer1-basic-auth
      config:
        username: consumer1
        password: consumer1_pwd
---
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: consumer2
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: cred-consumer2-key-auth
      config:
        key: consumer2_pwd
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
  name: multi-auth-plugin-config
spec:
  plugins:
    - name: multi-auth
      config:
        auth_plugins:
          - basic-auth: {}
          - key-auth:
              hide_credentials: true
              header: apikey
              query: apikey
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: multi-auth-route
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
            name: multi-auth-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f multi-auth-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="multi-auth-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: consumer1
spec:
  ingressClassName: apisix
  authParameter:
    basicAuth:
      value:
        username: consumer1
        password: consumer1_pwd
---
apiVersion: apisix.apache.org/v2
kind: ApisixConsumer
metadata:
  namespace: aic
  name: consumer2
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: consumer2_pwd
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
  name: multi-auth-route
spec:
  ingressClassName: apisix
  http:
    - name: multi-auth-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: multi-auth
        enable: true
        config:
          auth_plugins:
            - basic-auth: {}
            - key-auth:
                hide_credentials: true
                header: apikey
                query: apikey
```

Apply the configuration to your cluster:

```shell
kubectl apply -f multi-auth-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route with `consumer1` basic authentication credentials:

```shell
curl -i "http://127.0.0.1:9080/anything" -u consumer1:consumer1_pwd
```

You should receive an `HTTP/1.1 200 OK` response.

Send another request to the Route with `consumer2` key authentication Credential:

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'apikey: consumer2_pwd'
```

You should again receive an `HTTP/1.1 200 OK` response.

Send a request to the Route without any Credential:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 401 Unauthorized` response.

This shows that Consumers using different authentication methods are able to authenticate and access the resource behind the same Route.
