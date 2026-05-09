---
title: traffic-label
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - traffic-label
  - traffic tagging
  - canary release
description: The traffic-label Plugin sets request headers based on configurable matching rules with weighted distribution, enabling traffic tagging and canary deployments.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/traffic-label" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `traffic-label` Plugin sets request headers based on configurable matching rules. Similar to the [workflow](./workflow.md) Plugin, it evaluates rules in order and executes an action on the first match. The key difference is that `traffic-label` supports **weighted distribution** within each rule's action list, enabling proportional traffic labeling for canary deployments and A/B testing.

Each rule consists of:

- **`match`** — An optional list of conditions evaluated using [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). If omitted, the rule matches all requests.
- **`actions`** — An array of actions to execute when the rule matches. Each action can set request headers and has an optional weight. Traffic is distributed proportionally across actions using weighted round-robin.

Rules are evaluated in array order. Evaluation stops at the first matching rule.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| rules | array[object] | True | | | List of matching rules. Rules are evaluated in order; the first match wins. |
| rules[].match | array | False | `[]` | | Match conditions using [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) syntax. Each element is either an expression array `[var, operator, value]` or the string `"OR"` / `"AND"` to control logical grouping. When omitted, the rule matches all requests. |
| rules[].actions | array[object] | True | | | Actions to execute when the rule matches. Traffic is distributed across actions based on their `weight`. |
| rules[].actions[].set_headers | object | False | | | Request headers to set. Overwrites an existing header or adds a new one. Values support NGINX variables such as `$remote_addr`. Format: `{"header-name": "value"}`. |
| rules[].actions[].weight | integer | False | 1 | ≥ 1 | Relative weight for this action. Traffic proportion = `this weight / sum of all weights in the rule`. An action with only `weight` set passes traffic through without modification. |

:::note

- Rules are evaluated in order. Only the first matching rule executes; subsequent rules are skipped.
- Currently, `set_headers` is the only supported action type.

:::

## Examples

The examples below demonstrate how you can configure `traffic-label` in different scenarios.

:::note

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Label Traffic Based on Request Conditions

The following example demonstrates how to set a request header `X-Server-Id` to different values based on the `?version` query parameter.

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
    "id": "traffic-label-route",
    "uri": "/anything",
    "plugins": {
      "traffic-label": {
        "rules": [
          {
            "match": [["arg_version", "==", "v1"]],
            "actions": [{"set_headers": {"X-Server-Id": "100"}}]
          },
          {
            "match": [["arg_version", "==", "v2"]],
            "actions": [{"set_headers": {"X-Server-Id": "200"}}]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {"httpbin.org:80": 1}
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: traffic-label-route
        uris:
          - /anything
        plugins:
          traffic-label:
            rules:
              - match:
                  - ["arg_version", "==", "v1"]
                actions:
                  - set_headers:
                      X-Server-Id: "100"
              - match:
                  - ["arg_version", "==", "v2"]
                actions:
                  - set_headers:
                      X-Server-Id: "200"
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

```yaml title="traffic-label-ic.yaml"
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
  name: traffic-label-plugin-config
spec:
  plugins:
    - name: traffic-label
      config:
        rules:
          - match:
              - ["arg_version", "==", "v1"]
            actions:
              - set_headers:
                  X-Server-Id: "100"
          - match:
              - ["arg_version", "==", "v2"]
            actions:
              - set_headers:
                  X-Server-Id: "200"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: traffic-label-route
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
            name: traffic-label-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="traffic-label-ic.yaml"
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
  name: traffic-label-route
spec:
  ingressClassName: apisix
  http:
    - name: traffic-label-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: traffic-label
        enable: true
        config:
          rules:
            - match:
                - ["arg_version", "==", "v1"]
              actions:
                - set_headers:
                    X-Server-Id: "100"
            - match:
                - ["arg_version", "==", "v2"]
              actions:
                - set_headers:
                    X-Server-Id: "200"
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f traffic-label-ic.yaml
```

</TabItem>

</Tabs>

Send a request with `?version=v1`:

```shell
curl "http://127.0.0.1:9080/anything?version=v1"
```

The upstream will receive `X-Server-Id: 100`. Send a request with `?version=v2` and the upstream receives `X-Server-Id: 200`. Requests without a `version` parameter match no rule and pass through without modification.

### Distribute Traffic Across Actions by Weight

The following example demonstrates weighted distribution using `traffic-label`. When a request matches the rule, traffic is proportionally distributed across actions based on their `weight`:

- 30% of requests: `X-Server-Id: 100`
- 20% of requests: `X-API-Version: v2`
- 50% of requests: pass through without modification

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
    "id": "traffic-label-route",
    "uri": "/anything",
    "plugins": {
      "traffic-label": {
        "rules": [
          {
            "match": [["uri", "==", "/anything"]],
            "actions": [
              {
                "set_headers": {"X-Server-Id": "100"},
                "weight": 3
              },
              {
                "set_headers": {"X-API-Version": "v2"},
                "weight": 2
              },
              {
                "weight": 5
              }
            ]
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {"httpbin.org:80": 1}
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - name: traffic-label-route
        uris:
          - /anything
        plugins:
          traffic-label:
            rules:
              - match:
                  - ["uri", "==", "/anything"]
                actions:
                  - set_headers:
                      X-Server-Id: "100"
                    weight: 3
                  - set_headers:
                      X-API-Version: v2
                    weight: 2
                  - weight: 5
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

```yaml title="traffic-label-ic.yaml"
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
  name: traffic-label-plugin-config
spec:
  plugins:
    - name: traffic-label
      config:
        rules:
          - match:
              - ["uri", "==", "/anything"]
            actions:
              - set_headers:
                  X-Server-Id: "100"
                weight: 3
              - set_headers:
                  X-API-Version: v2
                weight: 2
              - weight: 5
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: traffic-label-route
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
            name: traffic-label-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="traffic-label-ic.yaml"
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
  name: traffic-label-route
spec:
  ingressClassName: apisix
  http:
    - name: traffic-label-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: traffic-label
        enable: true
        config:
          rules:
            - match:
                - ["uri", "==", "/anything"]
              actions:
                - set_headers:
                    X-Server-Id: "100"
                  weight: 3
                - set_headers:
                    X-API-Version: v2
                  weight: 2
                - weight: 5
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f traffic-label-ic.yaml
```

</TabItem>

</Tabs>

The total weight is `3 + 2 + 5 = 10`. Across 10 requests, approximately 3 will have `X-Server-Id: 100`, 2 will have `X-API-Version: v2`, and 5 will pass through without any added header.
