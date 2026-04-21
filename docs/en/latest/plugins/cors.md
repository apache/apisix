---
title: cors
keywords:
  - Apache APISIX
  - API Gateway
  - CORS
description: This document contains information about the Apache APISIX cors Plugin.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/cors" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `cors` plugin allows you to enable [Cross-Origin Resource Sharing (CORS)](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS). CORS is an HTTP-header based mechanism which allows a server to specify any origins (domain, scheme, or port) other than its own, and instructs browsers to allow the loading of resources from those origins.

## Attributes

| Name | Type | Required | Default | Valid values | Description |
|---|---|---|---|---|---|
| allow_origins | string | False | `"*"` | | Comma-separated string of origins to allow CORS, in the format `scheme://host:port`, for example `https://somedomain.com:8081`. If you have multiple origins, use `,` to list them. If `allow_credential` is set to `false`, you can use `*` to allow all origins. If `allow_credential` is set to `true`, you can use `**` to forcefully allow all origins, but this poses security risks. |
| allow_methods | string | False | `"*"` | | Comma-separated string of HTTP request methods to allow CORS, for example `GET`, `POST`. If `allow_credential` is set to `false`, you can use `*` to allow all methods. If `allow_credential` is set to `true`, you can use `**` to forcefully allow all methods, but this poses security risks. |
| allow_headers | string | False | `"*"` | | Comma-separated string of HTTP headers allowed in requests when accessing a cross-origin resource. If `allow_credential` is set to `false`, you can use `*` to allow all request headers. If `allow_credential` is set to `true`, you can use `**` to forcefully allow all request headers, but this poses security risks. |
| expose_headers | string | False | | | Comma-separated string of HTTP headers that should be made available in response to a cross-origin request. If `allow_credential` is set to `false`, you can use `*` to allow all response headers. If not specified, the Plugin will not modify the `Access-Control-Expose-Headers` header. See [Access-Control-Expose-Headers - MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Expose-Headers) for more details. |
| max_age | integer | False | 5 | | Maximum time in seconds for which the results of a preflight request can be cached. If the time is within this limit, the browser will check the cached result. Set to `-1` to disable caching. Note that the maximum value is browser-dependent. See [Access-Control-Max-Age](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age#Directives) for more details. |
| allow_credential | boolean | False | false | | When set to `true`, allows requests to include credentials such as cookies. According to CORS specification, if you set this to `true`, you cannot use `*` for other CORS attributes. |
| allow_origins_by_regex | array | False | | | Regex to match origins that allow CORS. For example, `[".*\.test.com$"]` can match all subdomains of `test.com`. When configured, only domains matching the RegEx will be allowed and `allow_origins` will be ignored. |
| allow_origins_by_metadata | array | False | | | Origins to enable CORS referenced from `allow_origins` set in the Plugin metadata. For example, if `"allow_origins": {"EXAMPLE": "https://example.com"}` is set in the Plugin metadata, then `["EXAMPLE"]` can be used to allow CORS on the origin `https://example.com`. |
| timing_allow_origins | string | False | | | Comma-separated string of origins to allow access to the resource timing information. See [Timing-Allow-Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Timing-Allow-Origin) for more details. |
| timing_allow_origins_by_regex | array | False | | | Regex to match origins for enabling access to the resource timing information. For example, `[".*\.test.com"]` can match all subdomains of `test.com`. When configured, only domains matching the RegEx will be allowed and `timing_allow_origins` will be ignored. |

:::info IMPORTANT

1. The `allow_credential` attribute is sensitive and must be used carefully. If set to `true`, the default value `*` of the other attributes will be invalid and they should be specified explicitly.
2. When using `**` you are vulnerable to security risks like CSRF. Make sure that this meets your security levels before using it.

:::

## Metadata

| Name | Type | Required | Default | Valid values | Description |
|---|---|---|---|---|---|
| allow_origins | object | False | | | A map of keys and allowed origins. The keys are used in the `allow_origins_by_metadata` attribute and the values are equivalent to the `allow_origins` attribute of the Plugin. |

## Examples

The examples below demonstrate how you can configure the `cors` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' /usr/local/apisix/conf/config.yaml | sed 's/"//g')
```

:::

### Enable CORS for a Route

The following example demonstrates how to enable CORS on a Route to allow resource loading from a list of origins.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route with the `cors` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cors-route",
    "uri": "/anything",
    "plugins": {
      "cors": {
        "allow_origins": "http://sub.domain.com,http://sub2.domain.com",
        "allow_methods": "GET,POST",
        "allow_headers": "headr1,headr2",
        "expose_headers": "ex-headr1,ex-headr2",
        "max_age": 50,
        "allow_credential": true
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: cors-service
    routes:
      - name: cors-route
        uris:
          - /anything
        plugins:
          cors:
            allow_origins: "http://sub.domain.com,http://sub2.domain.com"
            allow_methods: "GET,POST"
            allow_headers: "headr1,headr2"
            expose_headers: "ex-headr1,ex-headr2"
            max_age: 50
            allow_credential: true
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to APISIX:

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

```yaml title="cors-ic.yaml"
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
  name: cors-plugin-config
spec:
  plugins:
    - name: cors
      config:
        allow_origins: "http://sub.domain.com,http://sub2.domain.com"
        allow_methods: "GET,POST"
        allow_headers: "headr1,headr2"
        expose_headers: "ex-headr1,ex-headr2"
        max_age: 50
        allow_credential: true
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: cors-route
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
            name: cors-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f cors-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="cors-ic.yaml"
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
  name: cors-route
spec:
  ingressClassName: apisix
  http:
    - name: cors-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: cors
        enable: true
        config:
          allow_origins: "http://sub.domain.com,http://sub2.domain.com"
          allow_methods: "GET,POST"
          allow_headers: "headr1,headr2"
          expose_headers: "ex-headr1,ex-headr2"
          max_age: 50
          allow_credential: true
```

Apply the configuration to your cluster:

```shell
kubectl apply -f cors-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route with an allowed origin:

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://sub2.domain.com" -I
```

You should receive an `HTTP/1.1 200 OK` response and observe CORS headers:

```text
...
Access-Control-Allow-Origin: http://sub2.domain.com
Access-Control-Allow-Credentials: true
Server: APISIX/3.8.0
Vary: Origin
Access-Control-Allow-Methods: GET,POST
Access-Control-Max-Age: 50
Access-Control-Expose-Headers: ex-headr1,ex-headr2
Access-Control-Allow-Headers: headr1,headr2
```

Send a request to the Route with an origin that is not allowed:

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://sub3.domain.com" -I
```

You should receive an `HTTP/1.1 200 OK` response without any CORS headers:

```text
...
Server: APISIX/3.8.0
Vary: Origin
```

### Use RegEx to Match Origin

The following example demonstrates how to use a regular expression to match allowed origins using the `allow_origins_by_regex` attribute.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route with the `cors` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cors-route",
    "uri": "/anything",
    "plugins": {
      "cors": {
        "allow_methods": "GET,POST",
        "allow_headers": "headr1,headr2",
        "expose_headers": "ex-headr1,ex-headr2",
        "max_age": 50,
        "allow_origins_by_regex": [ ".*\\.test.com$" ]
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: cors-service
    routes:
      - name: cors-route
        uris:
          - /anything
        plugins:
          cors:
            allow_methods: "GET,POST"
            allow_headers: "headr1,headr2"
            expose_headers: "ex-headr1,ex-headr2"
            max_age: 50
            allow_origins_by_regex:
              - ".*\\.test.com$"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to APISIX:

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

```yaml title="cors-ic.yaml"
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
  name: cors-regex-plugin-config
spec:
  plugins:
    - name: cors
      config:
        allow_methods: "GET,POST"
        allow_headers: "headr1,headr2"
        expose_headers: "ex-headr1,ex-headr2"
        max_age: 50
        allow_origins_by_regex:
          - ".*\\.test.com$"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: cors-route
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
            name: cors-regex-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f cors-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

```yaml title="cors-ic.yaml"
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
  name: cors-route
spec:
  ingressClassName: apisix
  http:
    - name: cors-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: cors
        enable: true
        config:
          allow_methods: "GET,POST"
          allow_headers: "headr1,headr2"
          expose_headers: "ex-headr1,ex-headr2"
          max_age: 50
          allow_origins_by_regex:
            - ".*\\.test.com$"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f cors-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route with an allowed origin:

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://a.test.com" -I
```

You should receive an `HTTP/1.1 200 OK` response and observe CORS headers:

```text
...
Access-Control-Allow-Origin: http://a.test.com
Server: APISIX/3.8.0
Vary: Origin
Access-Control-Allow-Methods: GET,POST
Access-Control-Max-Age: 50
Access-Control-Expose-Headers: ex-headr1,ex-headr2
Access-Control-Allow-Headers: headr1,headr2
```

Send a request with an origin that does not match the pattern:

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://a.test2.com" -I
```

You should receive an `HTTP/1.1 200 OK` response without any CORS headers:

```text
...
Server: APISIX/3.8.0
Vary: Origin
```

### Configure Origins in Plugin Metadata

The following example demonstrates how to configure allowed origins in [Plugin metadata](https://apisix.apache.org/docs/apisix/terminology/plugin/) and reference them in the `cors` Plugin using `allow_origins_by_metadata`.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Configure Plugin metadata for the `cors` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/cors" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "allow_origins": {
      "key_1": "https://domain.com",
      "key_2": "https://sub.domain.com,https://sub2.domain.com",
      "key_3": "*"
    }
  }'
```

Create a Route with the `cors` Plugin using `allow_origins_by_metadata`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cors-route",
    "uri": "/anything",
    "plugins": {
      "cors": {
        "allow_methods": "GET,POST",
        "allow_headers": "headr1,headr2",
        "expose_headers": "ex-headr1,ex-headr2",
        "max_age": 50,
        "allow_origins_by_metadata": ["key_1"]
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
plugin_metadata:
  cors:
    allow_origins:
      key_1: "https://domain.com"
      key_2: "https://sub.domain.com,https://sub2.domain.com"
      key_3: "*"
services:
  - name: cors-service
    routes:
      - name: cors-route
        uris:
          - /anything
        plugins:
          cors:
            allow_methods: "GET,POST"
            allow_headers: "headr1,headr2"
            expose_headers: "ex-headr1,ex-headr2"
            max_age: 50
            allow_origins_by_metadata:
              - "key_1"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to APISIX:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

Update your GatewayProxy manifest to configure the Plugin metadata:

```yaml title="gatewayproxy.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: GatewayProxy
metadata:
  namespace: aic
  name: apisix-config
spec:
  provider:
    type: ControlPlane
    controlPlane:
      # your control plane connection configuration
  pluginMetadata:
    cors:
      allow_origins:
        key_1: "https://domain.com"
        key_2: "https://sub.domain.com,https://sub2.domain.com"
        key_3: "*"
```

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX Ingress Controller', value: 'apisix-ingress-controller'}
]}>

<TabItem value="gateway-api">

Create the Route with `allow_origins_by_metadata`:

```yaml title="cors-ic.yaml"
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
  name: cors-metadata-plugin-config
spec:
  plugins:
    - name: cors
      config:
        allow_methods: "GET,POST"
        allow_headers: "headr1,headr2"
        expose_headers: "ex-headr1,ex-headr2"
        max_age: 50
        allow_origins_by_metadata:
          - "key_1"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: cors-route
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
            name: cors-metadata-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

Apply the configuration to your cluster:

```shell
kubectl apply -f gatewayproxy.yaml -f cors-ic.yaml
```

</TabItem>

<TabItem value="apisix-ingress-controller">

Create the Route with `allow_origins_by_metadata`:

```yaml title="cors-ic.yaml"
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
  name: cors-route
spec:
  ingressClassName: apisix
  http:
    - name: cors-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
      - name: cors
        enable: true
        config:
          allow_methods: "GET,POST"
          allow_headers: "headr1,headr2"
          expose_headers: "ex-headr1,ex-headr2"
          max_age: 50
          allow_origins_by_metadata:
            - "key_1"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f gatewayproxy.yaml -f cors-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route with an allowed origin:

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: https://domain.com" -I
```

You should receive an `HTTP/1.1 200 OK` response and observe CORS headers:

```text
...
Access-Control-Allow-Origin: https://domain.com
Server: APISIX/3.8.0
Vary: Origin
Access-Control-Allow-Methods: GET,POST
Access-Control-Max-Age: 50
Access-Control-Expose-Headers: ex-headr1,ex-headr2
Access-Control-Allow-Headers: headr1,headr2
```

Send a request with an origin not in the metadata:

```shell
curl "http://127.0.0.1:9080/anything" -H "Origin: http://a.test2.com" -I
```

You should receive an `HTTP/1.1 200 OK` response without any CORS headers:

```text
...
Server: APISIX/3.8.0
Vary: Origin
```
