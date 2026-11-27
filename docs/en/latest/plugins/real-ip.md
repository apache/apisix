---
title: real-ip
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Real IP
description: The real-ip plugin allows Apache APISIX to set the client's real IP by the IP address passed in the HTTP header or HTTP query string.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/real-ip" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `real-ip` Plugin replaces the client address with an IP address from a request header or query parameter. Use it when a trusted proxy passes a verified client address and APISIX would otherwise identify the proxy as the client.

The Plugin is functionally similar to NGINX's [ngx_http_realip_module](https://nginx.org/en/docs/http/ngx_http_realip_module.html) but offers more flexibility.

## Attributes

| Name      | Type    | Required | Default | Valid values   | Description   |
|-----------|---------|----------|---------|----------------|---------------|
| source    | string  | True      |     |    |A built-in [APISIX variable](https://apisix.apache.org/docs/apisix/apisix-variable/) or [NGINX variable](https://nginx.org/en/docs/varindex.html), such as `http_x_forwarded_for` or `arg_realip`. The variable value should be a valid IP address that represents the client's real IP address, with an optional port.|
| trusted_addresses | array[string] | False |     | array of IPv4 or IPv6 addresses (CIDR notation acceptable)  | Addresses of trusted proxies that can supply a replacement address through `source`. When configured, the Plugin changes the client address only if the current `remote_addr` matches this list. When omitted, the Plugin accepts the value from `source` for connections from any peer. Configure trusted addresses when untrusted clients can control the source value. |
| recursive  | boolean | False |  False   |    | Controls how the Plugin selects an address when `source` is `http_x_forwarded_for` and `trusted_addresses` is configured. If false, the Plugin selects the last address in the header. If true, the Plugin scans the header from right to left, skips trusted intermediary addresses, and selects the last non-trusted address. If every address is trusted, it selects the leftmost address. This option has no effect for other sources or when `trusted_addresses` is omitted. |

:::note
If the address specified in `source` is missing or invalid, the Plugin does not change the client address.
:::

## Trust Forwarded Client Information

APISIX can obtain a client address at several stages. Each trust setting checks a different address and has a different effect.

| Stage | Address checked | Effect |
| --- | --- | --- |
| NGINX static real IP settings | The connection address against `nginx_config.http.real_ip_from`. By default, APISIX trusts `127.0.0.1` and `unix:`. | For a trusted source, `real_ip_header` reads the configured header (`X-Real-IP` by default), replaces `remote_addr`, and preserves the connection address in `realip_remote_addr`. |
| Global `apisix.trusted_addresses` | `realip_remote_addr` | Retains incoming `Forwarded` and `X-Forwarded-*` information from configured trusted addresses. If a configured list does not trust the connection address, APISIX sanitizes these headers before Plugins and the upstream receive them. |
| Plugin `trusted_addresses` | The current `remote_addr`, which may already reflect the NGINX rewrite | If the address is trusted, the Plugin replaces it with the address from `source`. |

When the global trust list is omitted, APISIX preserves the inbound `X-Forwarded-For` chain and appends the connection address for compatibility. It still replaces forwarded protocol, host, and port values with information observed by APISIX and clears `Forwarded`. When a configured trust list does not include the connection address, APISIX also discards the inbound `X-Forwarded-For` chain.

Trust only proxies you operate, and configure them to overwrite the source header with a verified client address. When the Plugin skips a request, it leaves `remote_addr` at the value received from NGINX.

## Examples

The examples set the client address from a query parameter, a trusted proxy header, or a multi-proxy chain.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Obtain Real Client Address From URI Parameter

The following example demonstrates how to update client IP address with a URI parameter.

Create a Route as follows:

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
    "id": "real-ip-route",
    "uri": "/get",
    "plugins": {
      "real-ip": {
        "source": "arg_realip",
        "trusted_addresses": ["127.0.0.0/24"]
      },
      "response-rewrite": {
        "headers": {
          "remote_addr": "$remote_addr",
          "remote_port": "$remote_port"
        }
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
  - name: httpbin
    routes:
      - name: real-ip-route
        uris:
          - /get
        plugins:
          real-ip:
            source: arg_realip
            trusted_addresses:
              - 127.0.0.0/24
          response-rewrite:
            headers:
              remote_addr: $remote_addr
              remote_port: $remote_port
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

```yaml title="real-ip-ic.yaml"
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
  name: real-ip-plugin-config
spec:
  plugins:
    - name: real-ip
      config:
        source: arg_realip
        trusted_addresses:
          - 127.0.0.0/24
    - name: response-rewrite
      config:
        headers:
          remote_addr: $remote_addr
          remote_port: $remote_port
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: real-ip-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: real-ip-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="real-ip-ic.yaml"
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
  name: real-ip-route
spec:
  ingressClassName: apisix
  http:
    - name: real-ip-route
      match:
        paths:
          - /get
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: real-ip
          config:
            source: arg_realip
            trusted_addresses:
              - 127.0.0.0/24
        - name: response-rewrite
          config:
            headers:
              remote_addr: $remote_addr
              remote_port: $remote_port
```

</TabItem>

</Tabs>

Apply the configuration:

```shell
kubectl apply -f real-ip-ic.yaml
```

</TabItem>

</Tabs>

Send a request to the Route with real IP and port in the URL parameter:

```shell
curl -i "http://127.0.0.1:9080/get?realip=1.2.3.4:9080"
```

You should see the response includes the following headers:

```text
remote_addr: 1.2.3.4
remote_port: 9080
```

### Obtain Real Client Address From Header

This example reads a verified client address from `X-Verified-Client-IP`. It also shows what happens when the header is missing or the direct peer is not trusted.

Create a Route as follows:

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
    "id": "real-ip-route",
    "uri": "/get",
    "plugins": {
      "real-ip": {
        "source": "http_x_verified_client_ip",
        "trusted_addresses": ["127.0.0.0/24"]
      },
      "response-rewrite": {
        "headers": {
          "remote_addr": "$remote_addr"
        }
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
  - name: httpbin
    routes:
      - name: real-ip-route
        uris:
          - /get
        plugins:
          real-ip:
            source: http_x_verified_client_ip
            trusted_addresses:
              - 127.0.0.0/24
          response-rewrite:
            headers:
              remote_addr: $remote_addr
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

```yaml title="real-ip-ic.yaml"
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
  name: real-ip-plugin-config
spec:
  plugins:
    - name: real-ip
      config:
        source: http_x_verified_client_ip
        trusted_addresses:
          - 127.0.0.0/24
    - name: response-rewrite
      config:
        headers:
          remote_addr: $remote_addr
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: real-ip-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: real-ip-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="real-ip-ic.yaml"
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
  name: real-ip-route
spec:
  ingressClassName: apisix
  http:
    - name: real-ip-route
      match:
        paths:
          - /get
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: real-ip
          config:
            source: http_x_verified_client_ip
            trusted_addresses:
              - 127.0.0.0/24
        - name: response-rewrite
          config:
            headers:
              remote_addr: $remote_addr
```

</TabItem>

</Tabs>

Apply the configuration:

```shell
kubectl apply -f real-ip-ic.yaml
```

</TabItem>

</Tabs>

Send a request that represents a trusted local proxy supplying the verified client address:

```shell
curl -i "http://127.0.0.1:9080/get" \
  -H "X-Verified-Client-IP: 198.51.100.20"
```

You should see a response including the following header:

```text
remote_addr: 198.51.100.20
```

Repeat the request without `X-Verified-Client-IP`:

```shell
curl -i "http://127.0.0.1:9080/get"
```

APISIX logs `missing real address` and leaves the client address unchanged. With a direct local request, the response contains `remote_addr: 127.0.0.1`.

To verify the trust boundary, change `trusted_addresses` to `["192.0.2.10/32"]`, reapply the configuration with the same interface, and send the first request again. The direct peer no longer matches the trusted list, so APISIX ignores the supplied header and the response contains the gateway-visible peer address. Restore the trusted address after the test.

### Obtain Real Client Address Behind Multiple Proxies

This example resolves the original client address from an [`X-Forwarded-For`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For) chain added by multiple trusted proxies.

Create a Route as follows:

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
  "id": "real-ip-route",
  "uri": "/get",
  "plugins": {
    "real-ip": {
      "source": "http_x_forwarded_for",
      "recursive": true,
      "trusted_addresses": ["192.128.0.0/16", "127.0.0.1/32"]
    },
    "response-rewrite": {
      "headers": {
        "remote_addr": "$remote_addr"
      }
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
  - name: httpbin
    routes:
      - name: real-ip-route
        uris:
          - /get
        plugins:
          real-ip:
            source: http_x_forwarded_for
            recursive: true
            trusted_addresses:
              - 192.128.0.0/16
              - 127.0.0.1/32
          response-rewrite:
            headers:
              remote_addr: $remote_addr
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

```yaml title="real-ip-ic.yaml"
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
  name: real-ip-plugin-config
spec:
  plugins:
    - name: real-ip
      config:
        source: http_x_forwarded_for
        recursive: true
        trusted_addresses:
          - 192.128.0.0/16
          - 127.0.0.1/32
    - name: response-rewrite
      config:
        headers:
          remote_addr: $remote_addr
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: real-ip-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /get
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: real-ip-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="real-ip-ic.yaml"
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
  name: real-ip-route
spec:
  ingressClassName: apisix
  http:
    - name: real-ip-route
      match:
        paths:
          - /get
      upstreams:
        - name: httpbin-external-domain
      plugins:
        - name: real-ip
          config:
            source: http_x_forwarded_for
            recursive: true
            trusted_addresses:
              - 192.128.0.0/16
              - 127.0.0.1/32
        - name: response-rewrite
          config:
            headers:
              remote_addr: $remote_addr
```

</TabItem>

</Tabs>

Apply the configuration:

```shell
kubectl apply -f real-ip-ic.yaml
```

</TabItem>

</Tabs>

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/get" \
  -H "X-Forwarded-For: 127.0.0.2, 192.128.1.1, 127.0.0.1"
```

You should see a response including the following header:

```text
remote_addr: 127.0.0.2
```
