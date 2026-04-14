---
title: chaitin-waf
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - WAF
description: The chaitin-waf Plugin integrates with Chaitin WAF (SafeLine) to detect and block web threats, strengthening API security and protecting user data.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/chaitin-waf" />
</head>

## Description

The `chaitin-waf` Plugin integrates with the Chaitin WAF (SafeLine) service to provide advanced detection and prevention of web-based threats, enhancing application security and protecting sensitive user data.

## Response Headers

The Plugin can add the following response headers, depending on the configuration of `append_waf_resp_header` and `append_waf_debug_header`:

| Header | Description |
|--------|-------------|
| `X-APISIX-CHAITIN-WAF` | Indicates whether APISIX forwarded the request to the WAF server.<br />• `yes`: Request was forwarded to the WAF server.<br />• `no`: Request was not forwarded to the WAF server.<br />• `unhealthy`: Request matches the configured rules, but no WAF service is available.<br />• `err`: An error occurred during Plugin execution. The `X-APISIX-CHAITIN-WAF-ERROR` header is also included with details.<br />• `waf-err`: Error while interacting with the WAF server. The `X-APISIX-CHAITIN-WAF-ERROR` header is also included with details.<br />• `timeout`: Request to the WAF server timed out. |
| `X-APISIX-CHAITIN-WAF-TIME` | Round-trip time (RTT) in milliseconds for the request to the Chaitin WAF server, including both network latency and WAF server processing. |
| `X-APISIX-CHAITIN-WAF-STATUS` | Status code returned to APISIX by the WAF server. |
| `X-APISIX-CHAITIN-WAF-ACTION` | Action returned to APISIX by the WAF server.<br />• `pass`: Request was allowed by the WAF service.<br />• `reject`: Request was blocked by the WAF service. |
| `X-APISIX-CHAITIN-WAF-ERROR` | Debug header. Contains WAF error message. |
| `X-APISIX-CHAITIN-WAF-SERVER` | Debug header. Indicates which WAF server was selected. |

## Attributes

| Name                     | Type          | Required | Default | Valid values             | Description |
|--------------------------|---------------|----------|---------|--------------------------|-------------|
| mode                     | string        | false    | block   | `off`, `monitor`, `block`| Mode to determine how the Plugin behaves for matched requests. In `off` mode, WAF checks are skipped. In `monitor` mode, requests with potential threats are logged but not blocked. In `block` mode, requests with threats are blocked as determined by the WAF service. |
| match                    | array[object] | false    |         |                          | An array of matching rules. The Plugin uses these rules to decide whether to perform a WAF check on a request. If the list is empty, all requests are processed. |
| match.vars               | array[array]  | false    |         |                          | An array of one or more matching conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list) to conditionally execute the plugin. |
| append_waf_resp_header   | boolean       | false    | true    |                          | If true, add response headers `X-APISIX-CHAITIN-WAF`, `X-APISIX-CHAITIN-WAF-TIME`, `X-APISIX-CHAITIN-WAF-ACTION`, and `X-APISIX-CHAITIN-WAF-STATUS`. |
| append_waf_debug_header  | boolean       | false    | false   |                          | If true, add debugging headers `X-APISIX-CHAITIN-WAF-ERROR` and `X-APISIX-CHAITIN-WAF-SERVER` to the response. Effective only when `append_waf_resp_header` is `true`. |
| config                   | object        | false    |         |                          | Chaitin WAF service configurations. These settings override the corresponding metadata defaults when specified. |
| config.connect_timeout   | integer       | false    | 1000    |                          | The connection timeout to the WAF service, in milliseconds. |
| config.send_timeout      | integer       | false    | 1000    |                          | The sending timeout for transmitting data to the WAF service, in milliseconds. |
| config.read_timeout      | integer       | false    | 1000    |                          | The reading timeout for receiving data from the WAF service, in milliseconds. |
| config.req_body_size     | integer       | false    | 1024    |                          | The maximum allowed request body size, in KB. |
| config.keepalive_size    | integer       | false    | 256     |                          | The maximum number of idle connections to the WAF detection service that can be maintained concurrently. |
| config.keepalive_timeout | integer       | false    | 60000   |                          | The idle connection timeout for the WAF service, in milliseconds. |
| config.real_client_ip    | boolean       | false    | true    |                          | If true, the client IP is obtained from the `X-Forwarded-For` header. If false, the Plugin uses the client IP from the connection. |

## Plugin Metadata

| Name                     | Type          | Required | Default | Valid values | Description |
|--------------------------|---------------|----------|---------|--------------|-------------|
| nodes                    | array[object] | True     |         |              | An array of addresses for the Chaitin WAF service. |
| nodes.host               | string        | True     |         |              | Address of Chaitin WAF service. Supports IPv4, IPv6, Unix Socket, etc. |
| nodes.port               | integer       | False    | 80      |              | Port of Chaitin WAF service. |
| mode                     | string        | False    |         |    block     | Mode to determine how the Plugin behaves for matched requests. In `off` mode, WAF checks are skipped. In `monitor` mode, requests with potential threats are logged but not blocked. In `block` mode, requests with threats are blocked as determined by the WAF service. |
| config                   | object        | False    |         |              | Chaitin WAF service configurations. |
| config.connect_timeout   | integer       | False    | 1000    |              | The connection timeout to the WAF service, in milliseconds. |
| config.send_timeout      | integer       | False    | 1000    |              | The sending timeout for transmitting data to the WAF service, in milliseconds. |
| config.read_timeout      | integer       | False    | 1000    |              | The reading timeout for receiving data from the WAF service, in milliseconds. |
| config.req_body_size     | integer       | False    | 1024    |              | The maximum allowed request body size, in KB. |
| config.keepalive_size    | integer       | False    | 256     |              | The maximum number of idle connections to the WAF detection service that can be maintained concurrently. |
| config.keepalive_timeout | integer       | False    | 60000   |              | The idle connection timeout for the WAF service, in milliseconds. |
| config.real_client_ip    | boolean       | False    | true    |              | If true, the client IP is obtained from the `X-Forwarded-For` header. If false, the Plugin uses the client IP from the connection. |

## Examples

The examples below demonstrate how you can configure chaitin-waf Plugin for different scenarios.

Before proceeding, make sure you have installed [Chaitin WAF (SafeLine)](https://docs.waf.chaitin.com/en/GetStarted/Deploy).

:::note
Only `X-Forwarded-*` headers sent from addresses in the `apisix.trusted_addresses` configuration (supports IP and CIDR) will be trusted and passed to plugins or upstream. If `apisix.trusted_addresses` is not configured or the IP is not within the configured address range, all `X-Forwarded-*` headers will be overridden with trusted values.
:::

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Block Malicious Requests on a Route

The following example demonstrates how to integrate with Chaitin WAF to protect traffic on a route, rejecting malicious requests immediately.

Configure the Chaitin WAF connection details using Plugin Metadata (update the address accordingly):

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf" -X PUT \
  -H 'X-API-KEY: ${admin_key}' \
  -d '{
    "nodes": [
      {
        "host": "172.22.222.5",
        "port": 8000
      }
    ]
  }'
```

Create a Route and enable `chaitin-waf` on the Route to block requests identified to be malicious:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "chaitin-waf-route",
    "uri": "/anything",
    "plugins": {
      "chaitin-waf": {
        "mode": "block",
        "append_waf_resp_header": true,
        "append_waf_debug_header": true
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

Send a standard request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Send a request with SQL injection to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything" -d 'a=1 and 1=1'
```

You should see an `HTTP/1.1 403 Forbidden` response similar to the following:

```text
...
X-APISIX-CHAITIN-WAF-STATUS: 403
X-APISIX-CHAITIN-WAF-ACTION: reject
X-APISIX-CHAITIN-WAF-SERVER: 172.22.222.5
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-TIME: 3
...

{"code": 403, "success":false, "message": "blocked by Chaitin SafeLine Web Application Firewall", "event_id": "276be6457d8447a4bf1f792501dfba6c"}
```

### Monitor Requests for Malicious Intent

This example shows how to integrate with Chaitin WAF to monitor all routes with `chaitin-waf` without rejection, and to reject potentially malicious requests on a specific route.

Configure the Chaitin WAF connection details using Plugin Metadata (update the address accordingly) and configure the mode:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf" -X PUT \
  -H 'X-API-KEY: ${admin_key}' \
  -d '{
    "nodes": [
      {
        "host": "172.22.222.5",
        "port": 8000
      }
    ],
    "mode": "monitor"
  }'
```

Create a Route and enable `chaitin-waf` without any configuration on the Route:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "chaitin-waf-route",
    "uri": "/anything",
    "plugins": {
      "chaitin-waf": {}
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Send a standard request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Send a request with SQL injection to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything" -d 'a=1 and 1=1'
```

You should also receive an `HTTP/1.1 200 OK` response as the request is not blocked in the `monitor` mode, but observe the following in the log entry:

```text
2025/09/09 11:44:08 [warn] 115#115: *31683 [lua] chaitin-waf.lua:385: do_access(): chaitin-waf monitor mode: request would have been rejected, event_id: 49bed20603e242f9be5ba6f1744bba4b, client: 172.20.0.1, server: _, request: "POST /anything HTTP/1.1", host: "127.0.0.1:9080"
```

If you explicitly configure the `mode` on a route, it will take precedence over the configuration in the Plugin Metadata. For instance, if you create a Route like this:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "chaitin-waf-route",
    "uri": "/anything",
    "plugins": {
      "chaitin-waf": {
        "mode": "block"
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

Send a standard request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Send a request with SQL injection to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything" -d 'a=1 and 1=1'
```

You should see an `HTTP/1.1 403 Forbidden` response similar to the following:

```text
...
X-APISIX-CHAITIN-WAF-STATUS: 403
X-APISIX-CHAITIN-WAF-ACTION: reject
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-TIME: 3
...

{"code": 403, "success":false, "message": "blocked by Chaitin SafeLine Web Application Firewall", "event_id": "c3eb25eaa7ae4c0d82eb8ceebf3600d0"}
```
