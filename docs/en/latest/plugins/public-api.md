---
title: public-api
keywords:
  - Apache APISIX
  - API Gateway
  - Public API
description: The public-api plugin exposes an internal API endpoint, making it publicly accessible. One of the primary use cases of this plugin is to expose internal endpoints created by other plugins.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/public-api" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `public-api` Plugin exposes an internal API endpoint, making it publicly accessible. One of the primary use cases of this Plugin is to expose internal endpoints created by other Plugins.

## Attributes

| Name    | Type      | Required | Default | Valid Values | Description |
|---------|-----------|----------|---------|--------------|-------------|
| uri     | string    | False    |         |              | Internal endpoint to expose. If not configured, expose the Route URI. |

## Examples

The examples below demonstrate how you can configure `public-api` in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Expose Prometheus Metrics at Custom Endpoint

The following example demonstrates how you can disable the Prometheus export server that, by default, exposes an endpoint on port `9091`, and expose APISIX Prometheus metrics on a new public API endpoint on port `9080`, which APISIX uses to listen to other client requests.

You will also configure the Route such that the internal endpoint `/apisix/prometheus/metrics` is exposed at a custom endpoint.

:::caution

If a large quantity of metrics is being collected, the Plugin could take up a significant amount of CPU resources for metric computations and negatively impact the processing of regular requests.

To address this issue, APISIX uses [privileged agent](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/process.md#enable_privileged_agent) and offloads the metric computations to a separate process. This optimization applies automatically if you use the metric endpoint configured under `plugin_attr.prometheus.export_addr` in the configuration file. If you expose the metric endpoint with the `public-api` Plugin, you will not benefit from this optimization.

:::

Disable the Prometheus export server in the configuration file and reload APISIX for changes to take effect:

```yaml title="conf/config.yaml"
plugin_attr:
  prometheus:
    enable_export_server: false
```

Next, create a Route with `public-api` Plugin and expose a public API endpoint for APISIX metrics:

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
    "id": "prometheus-metrics",
    "uri": "/prometheus_metrics",
    "plugins": {
      "public-api": {
        "uri": "/apisix/prometheus/metrics"
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: public-api-metrics-service
    routes:
      - name: prometheus-metrics
        uris:
          - /prometheus_metrics
        plugins:
          public-api:
            uri: /apisix/prometheus/metrics
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

```yaml title="public-api-ic.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: prometheus-metrics
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /prometheus_metrics
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: public-api-metrics-plugin-config
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: public-api-metrics-plugin-config
spec:
  plugins:
    - name: public-api
      config:
        uri: /apisix/prometheus/metrics
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="public-api-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: prometheus-metrics
spec:
  ingressClassName: apisix
  http:
    - name: prometheus-metrics
      match:
        paths:
          - /prometheus_metrics
      plugins:
        - name: public-api
          enable: true
          config:
            uri: /apisix/prometheus/metrics
```

</TabItem>

</Tabs>

Apply the configuration:

```shell
kubectl apply -f public-api-ic.yaml
```

</TabItem>

</Tabs>

Send a request to the custom metrics endpoint:

```shell
curl "http://127.0.0.1:9080/prometheus_metrics"
```

You should see an output similar to the following:

```text
# HELP apisix_http_requests_total The total number of client requests since APISIX started
# TYPE apisix_http_requests_total gauge
apisix_http_requests_total 1
# HELP apisix_nginx_http_current_connections Number of HTTP connections
# TYPE apisix_nginx_http_current_connections gauge
apisix_nginx_http_current_connections{state="accepted"} 1
apisix_nginx_http_current_connections{state="active"} 1
apisix_nginx_http_current_connections{state="handled"} 1
apisix_nginx_http_current_connections{state="reading"} 0
apisix_nginx_http_current_connections{state="waiting"} 0
apisix_nginx_http_current_connections{state="writing"} 1
...
```

### Expose Batch Requests Endpoint

The following example demonstrates how you can use the `public-api` Plugin to expose an endpoint for the `batch-requests` Plugin, which is used for assembling multiple requests into one single request before sending them to the gateway.

[//]:<TODO: update link to batch-requests plugin doc when it is available>

Create a sample Route to httpbin's `/anything` endpoint for verification purpose:

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
    "id": "httpbin-anything",
    "uri": "/anything",
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
      - name: httpbin-anything
        uris:
          - /anything
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

```yaml title="public-api-httpbin-ic.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: httpbin-anything
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="public-api-httpbin-ic.yaml"
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
  name: httpbin-anything
spec:
  ingressClassName: apisix
  http:
    - name: httpbin-anything
      match:
        paths:
          - /anything
      upstreams:
        - name: httpbin-external-domain
```

</TabItem>

</Tabs>

Apply the configuration:

```shell
kubectl apply -f public-api-httpbin-ic.yaml
```

</TabItem>

</Tabs>

Create a Route with `public-api` Plugin. Set the Plugin's `uri` to the internal endpoint to be exposed, and set the Route's `uri` to the public endpoint:

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
    "id": "batch-requests",
    "uri": "/apisix/batch-requests",
    "plugins": {
      "public-api": {}
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: public-api-batch-service
    routes:
      - name: batch-requests
        uris:
          - /apisix/batch-requests
        plugins:
          public-api: {}
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

```yaml title="public-api-batch-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: public-api-batch-plugin-config
spec:
  plugins:
    - name: public-api
      config: {}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: batch-requests
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /apisix/batch-requests
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: public-api-batch-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="public-api-batch-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: batch-requests
spec:
  ingressClassName: apisix
  http:
    - name: batch-requests
      match:
        paths:
          - /apisix/batch-requests
      plugins:
        - name: public-api
          enable: true
```

</TabItem>

</Tabs>

Apply the configuration:

```shell
kubectl apply -f public-api-batch-ic.yaml
```

</TabItem>

</Tabs>

Send a pipelined request consisting of a GET and a POST request to the exposed batch requests endpoint:

```shell
curl "http://127.0.0.1:9080/apisix/batch-requests" -X POST -d '
{
  "pipeline": [
    {
      "method": "GET",
      "path": "/anything"
    },
    {
      "method": "POST",
      "path": "/anything",
      "body": "a post request"
    }
  ]
}'
```

You should receive responses from both requests, similar to the following:

```json
[
  {
    "reason": "OK",
    "body": "{\n  \"args\": {}, \n  \"data\": \"\", \n  \"files\": {}, \n  \"form\": {}, \n  \"headers\": {\n    \"Accept\": \"*/*\", \n    \"Host\": \"127.0.0.1\", \n    \"User-Agent\": \"curl/8.6.0\", \n    \"X-Amzn-Trace-Id\": \"Root=1-67b6e33b-5a30174f5534287928c54ca9\", \n    \"X-Forwarded-Host\": \"127.0.0.1\"\n  }, \n  \"json\": null, \n  \"method\": \"GET\", \n  \"origin\": \"192.168.107.1, 43.252.208.84\", \n  \"url\": \"http://127.0.0.1/anything\"\n}\n",
    "headers": {
      ...
    },
    "status": 200
  },
  {
    "reason": "OK",
    "body": "{\n  \"args\": {}, \n  \"data\": \"a post request\", \n  \"files\": {}, \n  \"form\": {}, \n  \"headers\": {\n    \"Accept\": \"*/*\", \n    \"Content-Length\": \"14\", \n    \"Host\": \"127.0.0.1\", \n    \"User-Agent\": \"curl/8.6.0\", \n    \"X-Amzn-Trace-Id\": \"Root=1-67b6e33b-0eddcec07f154dac0d77876f\", \n    \"X-Forwarded-Host\": \"127.0.0.1\"\n  }, \n  \"json\": null, \n  \"method\": \"POST\", \n  \"origin\": \"192.168.107.1, 43.252.208.84\", \n  \"url\": \"http://127.0.0.1/anything\"\n}\n",
    "headers": {
      ...
    },
    "status": 200
  }
]
```

If you would like to expose the batch requests endpoint at a custom endpoint, create a Route with `public-api` Plugin as such:

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
    "id": "batch-requests",
    "uri": "/batch-requests",
    "plugins": {
      "public-api": {
        "uri": "/apisix/batch-requests"
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: public-api-batch-service
    routes:
      - name: batch-requests
        uris:
          - /batch-requests
        plugins:
          public-api:
            uri: /apisix/batch-requests
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

```yaml title="public-api-batch-ic.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: batch-requests
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /batch-requests
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: public-api-batch-plugin-config
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: public-api-batch-plugin-config
spec:
  plugins:
    - name: public-api
      config:
        uri: /apisix/batch-requests
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="public-api-batch-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: batch-requests
spec:
  ingressClassName: apisix
  http:
    - name: batch-requests
      match:
        paths:
          - /batch-requests
      plugins:
        - name: public-api
          enable: true
          config:
            uri: /apisix/batch-requests
```

</TabItem>

</Tabs>

Apply the configuration:

```shell
kubectl apply -f public-api-batch-ic.yaml
```

</TabItem>

</Tabs>

The batch requests endpoint should now be exposed as `/batch-requests`, instead of `/apisix/batch-requests`.

Send a pipelined request consisting of a GET and a POST request to the exposed batch requests endpoint:

```shell
curl "http://127.0.0.1:9080/batch-requests" -X POST -d '
{
  "pipeline": [
    {
      "method": "GET",
      "path": "/anything"
    },
    {
      "method": "POST",
      "path": "/anything",
      "body": "a post request"
    }
  ]
}'
```

You should receive responses from both requests, similar to the following:

```json
[
  {
    "reason": "OK",
    "body": "{\n  \"args\": {}, \n  \"data\": \"\", \n  \"files\": {}, \n  \"form\": {}, \n  \"headers\": {\n    \"Accept\": \"*/*\", \n    \"Host\": \"127.0.0.1\", \n    \"User-Agent\": \"curl/8.6.0\", \n    \"X-Amzn-Trace-Id\": \"Root=1-67b6e33b-5a30174f5534287928c54ca9\", \n    \"X-Forwarded-Host\": \"127.0.0.1\"\n  }, \n  \"json\": null, \n  \"method\": \"GET\", \n  \"origin\": \"192.168.107.1, 43.252.208.84\", \n  \"url\": \"http://127.0.0.1/anything\"\n}\n",
    "headers": {
      ...
    },
    "status": 200
  },
  {
    "reason": "OK",
    "body": "{\n  \"args\": {}, \n  \"data\": \"a post request\", \n  \"files\": {}, \n  \"form\": {}, \n  \"headers\": {\n    \"Accept\": \"*/*\", \n    \"Content-Length\": \"14\", \n    \"Host\": \"127.0.0.1\", \n    \"User-Agent\": \"curl/8.6.0\", \n    \"X-Amzn-Trace-Id\": \"Root=1-67b6e33b-0eddcec07f154dac0d77876f\", \n    \"X-Forwarded-Host\": \"127.0.0.1\"\n  }, \n  \"json\": null, \n  \"method\": \"POST\", \n  \"origin\": \"192.168.107.1, 43.252.208.84\", \n  \"url\": \"http://127.0.0.1/anything\"\n}\n",
    "headers": {
      ...
    },
    "status": 200
  }
]
```
