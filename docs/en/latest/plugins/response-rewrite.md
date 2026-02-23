---
title: response-rewrite
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Response Rewrite
  - response-rewrite
description: The response-rewrite Plugin offers options to rewrite responses that APISIX and its Upstream services return to clients. With the Plugin, you can modify HTTP status codes, request headers, response body, and more.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/response-rewrite" />
</head>

## Description

The `response-rewrite` Plugin offers options to rewrite responses that APISIX and its Upstream services return to clients. With the Plugin, you can modify HTTP status codes, request headers, response body, and more.

For instance, you can use this Plugin to:

- Support [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) by setting `Access-Control-Allow-*` headers.
- Indicate redirection by setting HTTP status codes and `Location` header.

:::tip

You can also use the [redirect](./redirect.md) Plugin to set up redirects.

:::

## Attributes

| Name            | Type    | Required | Default | Valid values                                                                                                  | Description                                                                                                                                                                                                                                                                         |
|-----------------|---------|----------|---------|---------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| status_code     | integer | False    |         | [200, 598]                                                                                                    | New HTTP status code in the response. If unset, falls back to the original status code.                                                                                                                                                                                             |
| body            | string  | False    |         |                                                                                                               | New response body. The `Content-Length` header would also be reset. Should not be configured with `filters`.                                                                                                                                                                                                                   |
| body_base64     | boolean | False    | false   |                                                                                                               | If true, decode the response body configured in `body` before sending to client, which is useful for image and protobuf decoding. Note that this configuration cannot be used to decode Upstream response.                                                                                                   |
| headers         | object  | False    |         |                                                                                                               |  Actions to be executed in the order of `add`, `remove`, and `set`.                                                                           |
| headers.add     | array[string]   | False    |         |                                                                                                               | Headers to append to requests. If a header already present in the request, the header value will be appended. Header value could be set to a constant, or one or more [Nginx variables](https://nginx.org/en/docs/http/ngx_http_core_module.html).                                                                                                          |
| headers.set     | object  | False    |         |                                                                                                               |Headers to set to requests. If a header already present in the request, the header value will be overwritten. Header value could be set to a constant, or one or more[Nginx variables](https://nginx.org/en/docs/http/ngx_http_core_module.html). |
| headers.remove  | array[string]   | False    |         |                                                                                                               | Headers to remove from requests.      |
| vars            | array[array] | False    |         |  | An array of one or more matching conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list).                                           |
| filters         | array[object] | False    |         |                                                                                                               | List of filters that modify the response body by replacing one specified string with another. Should not be configured with `body`.                                                         |
| filters.regex   | string  | True     |         |                                                                                                               | RegEx pattern to match on the response body.    |
| filters.scope   | string  | False    | "once"  | ["once","global"]                                                                                               | Scope of substitution. `once` substitutes the first matched instance and `global` substitutes globally.                                                                                                                                                                   |
| filters.replace | string  | True     |         |                                                                                                               |   Content to substitute with.             |
| filters.options | string  | False    | "jo"    |                                                                                                               | RegEx options to control how the match operation should be performed. See [Lua NGINX module](https://github.com/openresty/lua-nginx-module#ngxrematch) for the available options.                                                                                                                                                                                     |

## Examples

The examples below demonstrate how you can configure `response-rewrite` on a Route in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Rewrite Header and Body

The following example demonstrates how to add response body and headers, only to responses with `200` HTTP status codes.

Create a Route with the `response-rewrite` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "response-rewrite-route",
    "methods": ["GET"],
    "uri": "/headers",
    "plugins": {
      "response-rewrite": {
        "body": "{\"code\":\"ok\",\"message\":\"new json body\"}",
        "headers": {
          "set": {
            "X-Server-id": 3,
            "X-Server-status": "on",
            "X-Server-balancer-addr": "$balancer_ip:$balancer_port"
          }
        },
        "vars": [
          [ "status","==",200 ]
        ]
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

Send a request to verify:

```shell
curl -i "http://127.0.0.1:9080/headers"
```

You should receive a `HTTP/1.1 200 OK` response similar to the following:

```text
...
X-Server-id: 3
X-Server-status: on
X-Server-balancer-addr: 50.237.103.220:80

{"code":"ok","message":"new json body"}
```

### Rewrite Header With RegEx Filter

The following example demonstrates how to use RegEx filter matching to replace `X-Amzn-Trace-Id` for responses.

Create a Route with the `response-rewrite` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "response-rewrite-route",
    "methods": ["GET"],
    "uri": "/headers",
    "plugins":{
      "response-rewrite":{
        "filters":[
          {
            "regex":"X-Amzn-Trace-Id",
            "scope":"global",
            "replace":"X-Amzn-Trace-Id-Replace"
          }
        ]
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

Send a request to verify:

```shell
curl -i "http://127.0.0.1:9080/headers"
```

You should see a response similar to the following:

```text
{
  "headers": {
    "Accept": "*/*",
    "Host": "127.0.0.1",
    "User-Agent": "curl/8.2.1",
    "X-Amzn-Trace-Id-Replace": "Root=1-6500095d-1041b05e2ba9c6b37232dbc7",
    "X-Forwarded-Host": "127.0.0.1"
  }
}
```

### Decode Body from Base64

The following example demonstrates how to Decode Body from Base64 format.

Create a Route with the `response-rewrite` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "response-rewrite-route",
    "methods": ["GET"],
    "uri": "/get",
    "plugins":{
      "response-rewrite": {
        "body": "SGVsbG8gV29ybGQ=",
        "body_base64": true
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

Send a request to verify:

```shell
curl "http://127.0.0.1:9080/get"
```

You should see a response of the following:

```text
Hello World
```

### Rewrite Response and Its Connection with Execution Phases

The following example demonstrates the connection between the `response-rewrite` Plugin and [execution phases](/apisix/key-concepts/plugins#plugins-execution-lifecycle) by configuring the Plugin with the `key-auth` Plugin, and see how the response is still rewritten to `200 OK` in the case of an unauthenticated request.

Create a Consumer `jack`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jack"
  }'
```

Create `key-auth` credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jack/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jack-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jack-key"
      }
    }
  }'
```

Create a Route with `key-auth` and configure `response-rewrite` to rewrite the response status code and body:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
   -H "X-API-KEY: ${admin_key}" \
   -d '{
    "id": "response-rewrite-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "response-rewrite": {
        "status_code": 200,
        "body": "{\"code\": 200, \"msg\": \"success\"}"
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

Send a request to the Route with the valid key:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jack-key'
```

You should receive an `HTTP/1.1 200 OK` response of the following:

```text
{"code": 200, "msg": "success"}
```

Send a request to the Route without any key:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should still receive an `HTTP/1.1 200 OK` response of the same, instead of `HTTP/1.1 401 Unauthorized` from the `key-auth` Plugin. This shows that the `response-rewrite` Plugin still rewrites the response.

This is because **header_filter** and **body_filter** phase logics of the `response-rewrite` Plugin will continue to run after [`ngx.exit`](https://openresty-reference.readthedocs.io/en/latest/Lua_Nginx_API/#ngxexit) in the **access** or **rewrite** phases from other plugins.

The following table summarizes the impact of `ngx.exit` on execution phases.

| Phase         | rewrite  | access   | header_filter | body_filter |
|---------------|----------|----------|---------------|-------------|
| **rewrite**       | ngx.exit |          |               |           |
| **access**        | ×        | ngx.exit |               |           |
| **header_filter** | ✓        | ✓        | ngx.exit      |           |
| **body_filter**   | ✓        | ✓        | ×             | ngx.exit  |

For example, if `ngx.exit` takes places in the **rewrite** phase, it will interrupt the execution of **access** phase but not interfere with **header_filter** and **body_filter** phases.
