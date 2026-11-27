---
title: ip-restriction
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - IP restriction
  - ip-restriction
description: The ip-restriction Plugin supports restricting access to Upstream resources by IP addresses, through either configuring a whitelist or blacklist of IP addresses.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ip-restriction" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `ip-restriction` Plugin supports restricting access to Upstream resources by IP addresses, through either configuring a whitelist or blacklist of IP addresses. Restricting IP to resources helps prevent unauthorized access and harden API security.

## Attributes

| Name          | Type          | Required | Default                          | Valid values | Description                                                                                    |
|---------------|---------------|----------|----------------------------------|--------------|------------------------------------------------------------------------------------------------|
| whitelist     | array[string] | False    |                                  |              | List of IPs or CIDR ranges to allow. Exactly one of `whitelist` or `blacklist` must be configured. |
| blacklist     | array[string] | False    |                                  |              | List of IPs or CIDR ranges to deny. Exactly one of `whitelist` or `blacklist` must be configured.  |
| message       | string        | False    | "Your IP address is not allowed" | [1, 1024]    | Message returned to the client when the IP is blocked.                                         |
| response_code | integer       | False    | 403                              | [403, 404]   | HTTP response code returned when the request is rejected due to IP address restriction.        |
| phase         | string        | False    | "access"                         | ["rewrite", "access"] | Phase in which the check runs. Set to `rewrite` to reject requests before rewrite-phase authentication Plugins, such as `openid-connect`, `key-auth` or `jwt-auth`, act on them. For example, a blocked client is then not redirected to the identity provider's login page. An `ip-restriction` configured on a Consumer still applies after authentication, but cannot loosen a Route's `rewrite` check. Ignored by the stream Plugin. |

## Examples

The examples below demonstrate how you can configure the `ip-restriction` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Restrict Access by Whitelisting

The following example demonstrates how you can whitelist a list of IP addresses that should have access to the Upstream resource and customize the error message for access denial.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route with the `ip-restriction` Plugin to whitelist a range of IPs and customize the error message when the access is denied:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ip-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ip-restriction": {
        "whitelist": [
          "192.168.0.1/24"
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
  - name: ip-restriction-service
    routes:
      - name: ip-restriction-route
        uris:
          - /anything
        plugins:
          ip-restriction:
            whitelist:
              - "192.168.0.1/24"
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
{label: 'APISIX Ingress Controller', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-plugin-config
spec:
  plugins:
    - name: ip-restriction
      config:
        whitelist:
          - "192.168.0.1/24"
        message: "Access denied"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ip-restriction-route
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
            name: ip-restriction-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: ip-restriction-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: ip-restriction
        enable: true
        config:
          whitelist:
            - "192.168.0.1/24"
          message: "Access denied"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

If your IP is allowed, you should receive an `HTTP/1.1 200 OK` response. If not, you should receive an `HTTP/1.1 403 Forbidden` response with the following error message:

```text
{"message":"Access denied"}
```

### Restrict Access Using Modified IP

The following example demonstrates how you can modify the IP used for IP restriction, using the `real-ip` Plugin. This is particularly useful if APISIX is behind a reverse proxy and the real client IP is not available to APISIX.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route with the `ip-restriction` Plugin to whitelist a specific IP address and obtain client IP address from the URL parameter `realip`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ip-restriction-route",
    "uri": "/anything",
    "plugins": {
      "ip-restriction": {
        "whitelist": [
          "192.168.1.241"
        ]
      },
      "real-ip": {
        "source": "arg_realip"
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
  - name: ip-restriction-service
    routes:
      - name: ip-restriction-route
        uris:
          - /anything
        plugins:
          ip-restriction:
            whitelist:
              - "192.168.1.241"
          real-ip:
            source: arg_realip
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
{label: 'APISIX Ingress Controller', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-realip-plugin-config
spec:
  plugins:
    - name: ip-restriction
      config:
        whitelist:
          - "192.168.1.241"
    - name: real-ip
      config:
        source: arg_realip
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ip-restriction-route
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
            name: ip-restriction-realip-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: ip-restriction-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: ip-restriction
        enable: true
        config:
          whitelist:
            - "192.168.1.241"
      - name: real-ip
        enable: true
        config:
          source: arg_realip
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything?realip=192.168.1.241"
```

You should receive an `HTTP/1.1 200 OK` response.

Send another request with a different IP address:

```shell
curl -i "http://127.0.0.1:9080/anything?realip=192.168.10.24"
```

You should receive an `HTTP/1.1 403 Forbidden` response.

### Reject Requests Before Authentication

By default, `ip-restriction` runs in the `access` phase, after rewrite-phase authentication Plugins such as `key-auth`, `jwt-auth` or `openid-connect`. The following example demonstrates how you can set `phase` to `rewrite`, so that requests from IPs outside the whitelist are rejected before authentication. With `openid-connect`, this means a blocked client is not redirected to the identity provider's login page.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route with the `key-auth` and `ip-restriction` Plugins, and run the IP check in the `rewrite` phase:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ip-restriction-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {},
      "ip-restriction": {
        "whitelist": [
          "192.168.0.1/24"
        ],
        "phase": "rewrite"
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
  - name: ip-restriction-service
    routes:
      - name: ip-restriction-route
        uris:
          - /anything
        plugins:
          key-auth: {}
          ip-restriction:
            whitelist:
              - "192.168.0.1/24"
            phase: rewrite
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
{label: 'APISIX Ingress Controller', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: ip-restriction
      config:
        whitelist:
          - "192.168.0.1/24"
        phase: rewrite
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ip-restriction-route
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
            name: ip-restriction-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="ip-restriction-ic.yaml"
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
  name: ip-restriction-route
spec:
  ingressClassName: apisix
  http:
    - name: ip-restriction-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
        config:
          _meta:
            disable: false
      - name: ip-restriction
        enable: true
        config:
          whitelist:
            - "192.168.0.1/24"
          phase: rewrite
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ip-restriction-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route without an API key:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

If your IP is not allowed, you should receive an `HTTP/1.1 403 Forbidden` response before `key-auth` runs:

```text
{"message":"Your IP address is not allowed"}
```

Without `"phase": "rewrite"`, the same request would receive an `HTTP/1.1 401 Unauthorized` response from `key-auth` instead.

:::caution

In a Global Rule, the `rewrite` phase runs before the Plugins of the Route and Service. If the client IP is set by the `real-ip` Plugin on a Route or Service, a Global Rule `ip-restriction` with `"phase": "rewrite"` checks the address before that change, such as the load balancer's IP. Set the client IP with the NGINX `real_ip_*` directives or a Global Rule `real-ip` Plugin instead.

:::
