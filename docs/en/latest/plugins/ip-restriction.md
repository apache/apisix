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
