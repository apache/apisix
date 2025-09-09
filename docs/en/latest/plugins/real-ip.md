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

## Description

The `real-ip` Plugin allows APISIX to set the client's real IP by the IP address passed in the HTTP header or HTTP query string. This is particularly useful when APISIX is behind a reverse proxy since the proxy could act as the request-originating client otherwise.

The Plugin is functionally similar to NGINX's [ngx_http_realip_module](https://nginx.org/en/docs/http/ngx_http_realip_module.html) but offers more flexibility.

## Attributes

| Name      | Type    | Required | Default | Valid values   | Description   |
|-----------|---------|----------|---------|----------------|---------------|
| source    | string  | True      |     |    |A built-in [APISIX variable](https://apisix.apache.org/docs/apisix/apisix-variable/) or [NGINX variable](https://nginx.org/en/docs/varindex.html), such as `http_x_forwarded_for` or `arg_realip`. The variable value should be a valid IP address that represents the client's real IP address, with an optional port.|
| trusted_addresses | array[string] | False |     | array of IPv4 or IPv6 addresses (CIDR notation acceptable)  | Trusted addresses that are known to send correct replacement addresses. This configuration sets the [`set_real_ip_from`](https://nginx.org/en/docs/http/ngx_http_realip_module.html#set_real_ip_from) directive. |
| recursive  | boolean | False |  False   |    | If false, replace the original client address that matches one of the trusted addresses by the last address sent in the configured `source`.<br />If true, replace the original client address that matches one of the trusted addresses by the last non-trusted address sent in the configured `source`. |

:::note
Only `X-Forwarded-*` headers sent from addresses in the `apisix.trusted_addresses` configuration (supports IP and CIDR) will be trusted and passed to plugins or upstream. If `apisix.trusted_addresses` is not configured or the IP is not within the configured address range, all `X-Forwarded-*` headers will be overridden with trusted values.
:::

:::note
If the address specified in `source` is missing or invalid, the Plugin would not change the client address.
:::

## Examples

The examples below demonstrate how you can configure `real-ip` in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Obtain Real Client Address From URI Parameter

The following example demonstrates how to update the client IP address with a URI parameter.

Create a Route as follows. You should configure `source` to obtain value from the URL parameter `realip` using [APISIX variable](https://apisix.apache.org/docs/apisix/apisix-variable/) or [NGINX variable](https://nginx.org/en/docs/varindex.html). Use the `response-rewrite` Plugin to set response headers to verify if the client IP and port were actually updated.

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

Send a request to the Route with real IP and port in the URL parameter:

```shell
curl -i "http://127.0.0.1:9080/get?realip=1.2.3.4:9080"
```

You should see the response includes the following header:

```text
remote-addr: 1.2.3.4
remote-port: 9080
```

### Obtain Real Client Address From Header

The following example shows how to set the real client IP when APISIX is behind a reverse proxy, such as a load balancer when the proxy exposes the real client IP in the [`X-Forwarded-For`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For) header.

Create a Route as follows. You should configure `source` to obtain value from the request header `X-Forwarded-For` using [APISIX variable](https://apisix.apache.org/docs/apisix/apisix-variable/) or [NGINX variable](https://nginx.org/en/docs/varindex.html). Use the `response-rewrite` Plugin to set a response header to verify if the client IP was actually updated.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "real-ip-route",
    "uri": "/get",
    "plugins": {
      "real-ip": {
        "source": "http_x_forwarded_for",
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

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see a response including the following header:

```text
remote-addr: 10.26.3.19
```

The IP address should correspond to the IP address of the request-originating client.

### Obtain Real Client Address Behind Multiple Proxies

The following example shows how to get the real client IP when APISIX is behind multiple proxies, which causes [`X-Forwarded-For`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For) header to include a list of proxy IP addresses.

Create a Route as follows. You should configure `source` to obtain value from the request header `X-Forwarded-For` using [APISIX variable](https://apisix.apache.org/docs/apisix/apisix-variable/) or [NGINX variable](https://nginx.org/en/docs/varindex.html). Set `recursive` to `true` so that the original client address that matches one of the trusted addresses is replaced by the last non-trusted address sent in the configured `source`. Then, use the `response-rewrite` Plugin to set a response header to verify if the client IP was actually updated.

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
      "trusted_addresses": ["192.128.0.0/16", "127.0.0.0/24"]
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

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/get" \
  -H "X-Forwarded-For: 127.0.0.2, 192.128.1.1, 127.0.0.1"
```

You should see a response including the following header:

```text
remote-addr: 127.0.0.2
```
