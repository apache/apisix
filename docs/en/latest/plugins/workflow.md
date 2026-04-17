---
title: workflow
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - workflow
  - traffic control
description: The workflow Plugin supports the conditional execution of user-defined actions to client traffic based on a given set of rules. This provides a granular approach to traffic management.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/workflow" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `workflow` Plugin supports the conditional execution of user-defined actions to client traffic based on a given set of rules, defined using [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). This provides a granular approach to traffic management.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| rules | array[object] | True | | | An array of one or more pairs of matching conditions and actions to be executed. |
| rules.case | array[array] | False | | | An array of one or more matching conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list). For example, `{"arg_name", "==", "json"}`. |
| rules.actions | array[array] | True | | | An array of actions to be executed when a condition is successfully matched. Currently, the array only supports one action, and it should be either `return`, `limit-count`, or `limit-conn`. When the action is set to `return`, you can configure an HTTP status code to return to the client when the condition is matched. When the action is set to `limit-count`, you can configure all options of the [`limit-count`](./limit-count.md) plugin, except for `group`. When the action is configured to be `limit-conn`, you can configure all options of the [`limit-conn`](./limit-conn.md) plugin. |

## Examples

The examples below demonstrate how you can use the `workflow` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Return Response HTTP Status Code Conditionally

The following example demonstrates a simple rule with one matching condition and one associated action to return HTTP status code conditionally.

Create a Route with the `workflow` Plugin as such:

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
    "id": "workflow-route",
    "uri": "/anything/*",
    "plugins": {
      "workflow":{
        "rules":[
          {
            "case":[
              ["uri", "==", "/anything/rejected"]
            ],
            "actions":[
              [
                "return",
                {"code": 403}
              ]
            ]
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

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - uris:
          - /anything/*
        name: workflow-route
        plugins:
          workflow:
            rules:
              - case:
                  - ["uri", "==", "/anything/rejected"]
                actions:
                  - - return
                    - code: 403
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

```yaml title="workflow-ic.yaml"
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
  name: workflow-plugin-config
spec:
  plugins:
    - name: workflow
      config:
        rules:
          - case:
              - ["uri", "==", "/anything/rejected"]
            actions:
              - - return
                - code: 403
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: workflow-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything/
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: workflow-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="workflow-ic.yaml"
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
  name: workflow-route
spec:
  ingressClassName: apisix
  http:
    - name: workflow-route
      match:
        paths:
          - /anything/*
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: workflow
        enable: true
        config:
          rules:
            - case:
                - ["uri", "==", "/anything/rejected"]
              actions:
                - - return
                  - code: 403
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f workflow-ic.yaml
```

</TabItem>

</Tabs>

Send a request that matches none of the rules:

```shell
curl -i "http://127.0.0.1:9080/anything/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Send a request that matches the configured rule:

```shell
curl -i "http://127.0.0.1:9080/anything/rejected"
```

You should receive an `HTTP/1.1 403 Forbidden` response of following:

```text
{"error_msg":"rejected by workflow"}
```

### Apply Rate Limiting Conditionally by URI and Query Parameter

The following example demonstrates a rule with two matching conditions and one associated action to rate limit requests conditionally.

Create a Route with the `workflow` Plugin as such:

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
    "id": "workflow-route",
    "uri": "/anything/*",
    "plugins":{
      "workflow":{
        "rules":[
          {
            "case":[
              ["uri", "==", "/anything/rate-limit"],
              ["arg_env", "==", "v1"]
            ],
            "actions":[
              [
                "limit-count",
                {
                  "count":1,
                  "time_window":60,
                  "rejected_code":429
                }
              ]
            ]
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

```yaml title="adc.yaml"
services:
  - name: httpbin
    routes:
      - uris:
          - /anything/*
        name: workflow-route
        plugins:
          workflow:
            rules:
              - case:
                  - ["uri", "==", "/anything/rate-limit"]
                  - ["arg_env", "==", "v1"]
                actions:
                  - - limit-count
                    - count: 1
                      time_window: 60
                      rejected_code: 429
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

```yaml title="workflow-ic.yaml"
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
  name: workflow-plugin-config
spec:
  plugins:
    - name: workflow
      config:
        rules:
          - case:
              - ["uri", "==", "/anything/rate-limit"]
              - ["arg_env", "==", "v1"]
            actions:
              - - limit-count
                - count: 1
                  time_window: 60
                  rejected_code: 429
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: workflow-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /anything/
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: workflow-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="workflow-ic.yaml"
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
  name: workflow-route
spec:
  ingressClassName: apisix
  http:
    - name: workflow-route
      match:
        paths:
          - /anything/*
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: workflow
        enable: true
        config:
          rules:
            - case:
                - ["uri", "==", "/anything/rate-limit"]
                - ["arg_env", "==", "v1"]
              actions:
                - - limit-count
                  - count: 1
                    time_window: 60
                    rejected_code: 429
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f workflow-ic.yaml
```

</TabItem>

</Tabs>

Generate two consecutive requests that match the rule:

```shell
curl -i "http://127.0.0.1:9080/anything/rate-limit?env=v1"
```

You should receive an `HTTP/1.1 200 OK` response and an `HTTP 429 Too Many Requests` response.

Generate requests that do not match the condition:

```shell
curl -i "http://127.0.0.1:9080/anything/anything?env=v1"
```

You should receive `HTTP/1.1 200 OK` responses for all requests, as they are not rate limited.

### Apply Rate Limiting Conditionally by Consumers

The following example demonstrates how to configure the Plugin to perform rate limiting based on the following specifications:

* Consumer `john` should have a quota of 5 requests within a 30-second window
* Consumer `jane` should have a quota of 3 requests within a 30-second window
* All other Consumers should have a quota of 2 requests within a 30-second window

While this example will be using [`key-auth`](./key-auth.md), you can easily replace it with other authentication Plugins.

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

Create a third Consumer `jimmy`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jimmy"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jimmy/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jimmy-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jimmy-key"
      }
    }
  }'
```

Create a Route with the `workflow` and `key-auth` Plugins, with the desired rate limiting rules:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "workflow-route",
    "uri": "/anything",
    "plugins":{
      "key-auth": {},
      "workflow":{
        "rules":[
          {
            "actions": [
              [
                "limit-count",
                {
                  "count": 5,
                  "key": "consumer_john",
                  "key_type": "constant",
                  "rejected_code": 429,
                  "time_window": 30,
                  "policy": "local"
                }
              ]
            ],
            "case": [
              [
                "consumer_name",
                "==",
                "john"
              ]
            ]
          },
          {
            "actions": [
              [
                "limit-count",
                {
                  "count": 3,
                  "key": "consumer_jane",
                  "key_type": "constant",
                  "rejected_code": 429,
                  "time_window": 30,
                  "policy": "local"
                }
              ]
            ],
            "case": [
              [
                "consumer_name",
                "==",
                "jane"
              ]
            ]
          },
          {
            "actions": [
              [
                "limit-count",
                {
                  "count": 2,
                  "key": "$consumer_name",
                  "key_type": "var",
                  "rejected_code": 429,
                  "time_window": 30,
                  "policy": "local"
                }
              ]
            ]
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

Create three Consumers and a Route that enables per-Consumer rate limiting:

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
  - username: jimmy
    credentials:
      - name: key-auth
        type: key-auth
        config:
          key: jimmy-key
services:
  - name: httpbin
    routes:
      - uris:
          - /anything
        name: workflow-route
        plugins:
          key-auth: {}
          workflow:
            rules:
              - case:
                  - ["consumer_name", "==", "john"]
                actions:
                  - - limit-count
                    - count: 5
                      key: consumer_john
                      key_type: constant
                      rejected_code: 429
                      time_window: 30
                      policy: local
              - case:
                  - ["consumer_name", "==", "jane"]
                actions:
                  - - limit-count
                    - count: 3
                      key: consumer_jane
                      key_type: constant
                      rejected_code: 429
                      time_window: 30
                      policy: local
              - actions:
                  - - limit-count
                    - count: 2
                      key: "$consumer_name"
                      key_type: var
                      rejected_code: 429
                      time_window: 30
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

Create three Consumers and a Route that enables per-Consumer rate limiting. When Consumers are configured using the Ingress Controller, the Consumer name is generated in the format `namespace_consumername`. As a result, the `consumer_name` logic in the `workflow` Plugin should match the Consumer name in this format.

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="workflow-ic.yaml"
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
apiVersion: apisix.apache.org/v1alpha1
kind: Consumer
metadata:
  namespace: aic
  name: jimmy
spec:
  gatewayRef:
    name: apisix
  credentials:
    - type: key-auth
      name: primary-key
      config:
        key: jimmy-key
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
  name: workflow-plugin-config
spec:
  plugins:
    - name: key-auth
      config:
        _meta:
          disable: false
    - name: workflow
      config:
        rules:
          - case:
              - ["consumer_name", "==", "aic_john"]
            actions:
              - - limit-count
                - count: 5
                  key: consumer_john
                  key_type: constant
                  rejected_code: 429
                  time_window: 30
                  policy: local
          - case:
              - ["consumer_name", "==", "aic_jane"]
            actions:
              - - limit-count
                - count: 3
                  key: consumer_jane
                  key_type: constant
                  rejected_code: 429
                  time_window: 30
                  policy: local
          - actions:
              - - limit-count
                - count: 2
                  key: "$consumer_name"
                  key_type: var
                  rejected_code: 429
                  time_window: 30
                  policy: local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: workflow-route
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
            name: workflow-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="workflow-ic.yaml"
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
kind: ApisixConsumer
metadata:
  namespace: aic
  name: jimmy
spec:
  ingressClassName: apisix
  authParameter:
    keyAuth:
      value:
        key: jimmy-key
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
  name: workflow-route
spec:
  ingressClassName: apisix
  http:
    - name: workflow-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: key-auth
        enable: true
      - name: workflow
        enable: true
        config:
          rules:
            - case:
                - ["consumer_name", "==", "aic_john"]
              actions:
                - - limit-count
                  - count: 5
                    key: consumer_john
                    key_type: constant
                    rejected_code: 429
                    time_window: 30
                    policy: local
            - case:
                - ["consumer_name", "==", "aic_jane"]
              actions:
                - - limit-count
                  - count: 3
                    key: consumer_jane
                    key_type: constant
                    rejected_code: 429
                    time_window: 30
                    policy: local
            - actions:
                - - limit-count
                  - count: 2
                    key: "$consumer_name"
                    key_type: var
                    rejected_code: 429
                    time_window: 30
                    policy: local
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f workflow-ic.yaml
```

</TabItem>

</Tabs>

To verify, send 6 consecutive requests with `john`'s key:

```shell
resp=$(seq 6 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: john-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 6 requests, 5 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    5, 429:    1
```

Send 6 consecutive requests with `jane`'s key:

```shell
resp=$(seq 6 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jane-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 6 requests, 3 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    3, 429:    3
```

Send 3 consecutive requests with `jimmy`'s key:

```shell
resp=$(seq 3 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: jimmy-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 3 requests, 2 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    2, 429:    1
```
