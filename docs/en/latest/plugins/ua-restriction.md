---
title: User-Agent Restriction (ua-restriction)
keywords:
  - Apache APISIX
  - API Gateway
  - UA restriction
description: The ua-restriction Plugin restricts access to upstream resources using an allowlist or denylist of user agents, preventing overload from web crawlers and enhancing API security.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ua-restriction" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `ua-restriction` Plugin supports restricting access to upstream resources through either configuring an allowlist or denylist of user agents. A common use case is to prevent web crawlers from overloading the upstream resources and causing service degradation.

## Attributes

| Name           | Type          | Required | Default       | Valid values   | Description                                                                                                                          |
|----------------|---------------|----------|---------------|----------------|--------------------------------------------------------------------------------------------------------------------------------------|
| bypass_missing | boolean       | False    | false         |                | If `true`, bypasses the UA restriction check when the `User-Agent` header is missing.                                                |
| allowlist      | array[string] | False    |               |                | List of allowed user agents (supports regex). Exactly one of `allowlist` or `denylist` must be configured.                           |
| denylist       | array[string] | False    |               |                | List of denied user agents (supports regex). Exactly one of `allowlist` or `denylist` must be configured.                            |
| message        | string        | False    | "Not allowed" | [1, 1024] chars | Message returned to the client when the user agent is not allowed.                                                                   |

## Examples

The examples below demonstrate how you can configure `ua-restriction` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Reject Web Crawlers and Customize Error Message

The following example demonstrates how you can configure the Plugin to fend off unwanted web crawlers and customize the rejection message.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route and configure the Plugin to block specific crawlers from accessing resources with a customized message:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ua-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ua-restriction": {
        "bypass_missing": false,
        "denylist": [
          "(Baiduspider)/(\\d+)\\.(\\d+)",
          "bad-bot-1"
        ],
        "message": "Access denied"
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
  - name: ua-restriction-service
    routes:
      - name: ua-restriction-route
        uris:
          - /anything
        plugins:
          ua-restriction:
            bypass_missing: false
            denylist:
              - "(Baiduspider)/(\\d+)\\.(\\d+)"
              - "bad-bot-1"
            message: "Access denied"
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

```yaml title="ua-restriction-ic.yaml"
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
  name: ua-restriction-plugin-config
spec:
  plugins:
    - name: ua-restriction
      config:
        bypass_missing: false
        denylist:
          - "(Baiduspider)/(\\d+)\\.(\\d+)"
          - "bad-bot-1"
        message: "Access denied"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ua-restriction-route
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
            name: ua-restriction-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ua-restriction-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="ua-restriction-ic.yaml"
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
  name: ua-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: ua-restriction-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: ua-restriction
        enable: true
        config:
          bypass_missing: false
          denylist:
            - "(Baiduspider)/(\\d+)\\.(\\d+)"
            - "bad-bot-1"
          message: "Access denied"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ua-restriction-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Send another request to the Route with a disallowed user agent:

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'User-Agent: Baiduspider/5.0'
```

You should receive an `HTTP/1.1 403 Forbidden` response with the following message:

```text
{"message":"Access denied"}
```

### Bypass UA Restriction Checks

The following example demonstrates how to configure the Plugin to allow requests of a specific user agent to bypass the UA restriction.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ua-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ua-restriction": {
        "bypass_missing": true,
        "allowlist": [
          "good-bot-1"
        ],
        "message": "Access denied"
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
  - name: ua-restriction-service
    routes:
      - name: ua-restriction-route
        uris:
          - /anything
        plugins:
          ua-restriction:
            bypass_missing: true
            allowlist:
              - "good-bot-1"
            message: "Access denied"
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

```yaml title="ua-restriction-ic.yaml"
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
  name: ua-restriction-allowlist-plugin-config
spec:
  plugins:
    - name: ua-restriction
      config:
        bypass_missing: true
        allowlist:
          - "good-bot-1"
        message: "Access denied"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ua-restriction-route
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
            name: ua-restriction-allowlist-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ua-restriction-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="ua-restriction-ic.yaml"
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
  name: ua-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: ua-restriction-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: ua-restriction
        enable: true
        config:
          bypass_missing: true
          allowlist:
            - "good-bot-1"
          message: "Access denied"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ua-restriction-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route without modifying the user agent:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 403 Forbidden` response with the following message:

```text
{"message":"Access denied"}
```

Send another request to the Route with an empty user agent:

```shell
curl -i "http://127.0.0.1:9080/anything" -H 'User-Agent: '
```

You should receive an `HTTP/1.1 200 OK` response.
