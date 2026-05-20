---
title: fault-injection
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Fault Injection
  - fault-injection
description: The fault-injection Plugin tests application resiliency by simulating controlled faults or delays, making it ideal for chaos engineering and failure condition analysis.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/fault-injection" />
</head>

## Description

The `fault-injection` Plugin is designed to test your application's resiliency by simulating controlled faults or delays. It executes before other configured Plugins, ensuring that faults are applied consistently. This makes it ideal for scenarios like chaos engineering, where the behavior of your system under failure conditions is analyzed.

The Plugin supports two key actions:

- `abort`: immediately terminates a request with a specified HTTP status code (e.g., `503 Service Unavailable`), skipping all subsequent Plugins.
- `delay`: introduces a specified delay before processing the request further.

:::info

At least one of `abort` or `delay` must be configured.

:::

## Attributes

| Name              | Type    | Required | Default | Valid values | Description                                                                                                                                                                             |
|-------------------|---------|----------|---------|--------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| abort             | object  | False    |         |              | Configuration to abort a request and return a specific HTTP status code to the client. At least one of `abort` or `delay` must be configured.                                                |
| abort.http_status | integer | False    |         | [200, ...]   | HTTP status code of the response to return to the client. Required when `abort` is configured.                                                                                              |
| abort.body        | string  | False    |         |              | Body of the response returned to the client. Supports [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html), such as `client addr: $remote_addr\n`.                   |
| abort.headers     | object  | False    |         |              | Headers of the response returned to the client. Header values can contain [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html), such as `$remote_addr`.              |
| abort.percentage  | integer | False    |         | [0, 100]     | Percentage of requests to be aborted. If `vars` is also configured, both conditions must be satisfied.                                                                                      |
| abort.vars        | array[] | False    |         |              | Rules to match before aborting a request. Supports [lua-resty-expr](https://github.com/api7/lua-resty-expr) expressions. Multiple conditions can be combined with AND/OR logic.             |
| delay             | object  | False    |         |              | Configuration to delay a request. At least one of `abort` or `delay` must be configured.                                                                                                   |
| delay.duration    | number  | False    |         |              | Duration of the delay in seconds. Can be decimal. Required when `delay` is configured.                                                                                                     |
| delay.percentage  | integer | False    |         | [0, 100]     | Percentage of requests to be delayed. If `vars` is also configured, both conditions must be satisfied.                                                                                      |
| delay.vars        | array[] | False    |         |              | Rules to match before delaying a request. Supports [lua-resty-expr](https://github.com/api7/lua-resty-expr) expressions. Multiple conditions can be combined with AND/OR logic.             |

:::tip

`vars` supports [lua-resty-expr](https://github.com/api7/lua-resty-expr) expressions that can flexibly implement AND/OR relationships between rules. For example:

```json
[
    [
        [ "arg_name","==","jack" ],
        [ "arg_age","==",18 ]
    ],
    [
        [ "arg_name2","==","allen" ]
    ]
]
```

The first two expressions have an AND relationship, and the relationship between them and the third expression is OR.

:::

## Examples

The examples below demonstrate how you can configure `fault-injection` on a Route in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Inject Faults

The following example demonstrates how to configure the `fault-injection` Plugin on a Route to intercept requests and respond with a specific HTTP status code, without forwarding to the Upstream service.

Create a Route with the `fault-injection` Plugin using the `abort` action:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "fault-injection-route",
    "uri": "/anything",
    "plugins": {
      "fault-injection": {
        "abort": {
          "http_status": 404,
          "body": "APISIX Fault Injection"
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
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 404 Not Found` response with the following body, without the request being forwarded to the Upstream service:

```text
APISIX Fault Injection
```

### Inject Latencies

The following example demonstrates how to configure the `fault-injection` Plugin on a Route to inject request latency.

Create a Route with the `fault-injection` Plugin using the `delay` action to delay responses by 3 seconds:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "fault-injection-route",
    "uri": "/anything",
    "plugins": {
      "fault-injection": {
        "delay": {
          "duration": 3
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

Send a request to the Route and use `time` to measure how long it takes:

```shell
time curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response from the Upstream service, and the timing summary should show approximately 3 seconds total:

```text
real    0m3.034s
user    0m0.007s
sys     0m0.010s
```

### Inject Faults Conditionally

The following example demonstrates how to configure the `fault-injection` Plugin on a Route to inject faults only when specific request conditions are met.

Create a Route with the `fault-injection` Plugin configured to abort requests only when the URL parameter `name` equals `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "fault-injection-route",
    "uri": "/anything",
    "plugins": {
      "fault-injection": {
        "abort": {
          "http_status": 404,
          "body": "APISIX Fault Injection",
          "headers": {
            "X-APISIX-Remote-Addr": "$remote_addr"
          },
          "vars": [
            [
              [ "arg_name","==","john" ]
            ]
          ]
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

Send a request to the Route with the URL parameter `name` set to `john`:

```shell
curl -i "http://127.0.0.1:9080/anything?name=john"
```

You should receive an `HTTP/1.1 404 Not Found` response similar to the following:

```text
HTTP/1.1 404 Not Found
...
X-APISIX-Remote-Addr: 192.168.65.1

APISIX Fault Injection
```

Send a request with a different `name` value:

```shell
curl -i "http://127.0.0.1:9080/anything?name=jane"
```

You should receive an `HTTP/1.1 200 OK` response from the Upstream service, without faults injected.
