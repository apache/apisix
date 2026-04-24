---
title: API Mocking (mocking)
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Mocking
  - mocking
description: The mocking Plugin simulates API responses without forwarding requests to upstream services, offering customization of status codes, response bodies, headers, and more for API testing and development.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/mocking" />
</head>

## Description

The `mocking` Plugin allows you to simulate API responses without forwarding requests to Upstream services. The Plugin supports customization of the response status code, body, headers, and more. This is particularly useful during development, testing, or debugging phases, where the actual Upstream service might be unavailable, under maintenance, or expensive to call.

## Attributes

| Name             | Type    | Required                         | Default                      | Description                                                                                                                                                |
|------------------|---------|----------------------------------|------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| delay            | integer | False                            | 0                            | Response delay in seconds.                                                                                                                                 |
| response_status  | integer | False                            | 200                          | HTTP status code of the response.                                                                                                                          |
| content_type     | string  | False                            | application/json;charset=utf8 | `Content-Type` header value of the response.                                                                                                              |
| response_example | string  | One of this or `response_schema` |                              | Body of the response. Supports [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html), such as `$remote_addr`. One of `response_example` or `response_schema` must be configured, and they must not be configured together. |
| response_schema  | object  | One of this or `response_example` |                              | A [JSON schema](https://json-schema.org) object to generate a random mock response body. One of `response_schema` or `response_example` must be configured, and they must not be configured together. |
| with_mock_header | boolean | False                            | true                         | When set to `true`, adds a response header `x-mock-by: APISIX/{version}`.                                                                                 |
| response_headers | object  | False                            |                              | Headers to be added in the mocked response. For example: `{"X-Foo": "bar"}`.                                                                              |

The `response_schema` supports the following field types:

- `string`
- `number`
- `integer`
- `boolean`
- `object`
- `array`

## Examples

The examples below demonstrate how you can configure `mocking` on a Route in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Generate Specific Mock Responses

The following example demonstrates how to configure the Plugin to generate a specific mock response and response status code without forwarding the request to the Upstream service.

Create a Route with the `mocking` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mocking-route",
    "uri": "/anything",
    "plugins": {
      "mocking": {
        "response_status": 201,
        "response_example": "{\"Lastname\":\"Brown\",\"Age\":56}"
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

You should receive an `HTTP/1.1 201 Created` mock response with the following body:

```text
{"Lastname":"Brown","Age":56}
```

### Generate Mock Response Headers

The following example demonstrates how to configure the Plugin to generate mock response headers and use a built-in NGINX variable in the response body.

Create a Route with the `mocking` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mocking-route",
    "uri": "/anything",
    "plugins": {
      "mocking": {
        "response_headers": {
          "X-User-Id": "100",
          "X-Product-Id": "apac-398-472"
        },
        "response_example": "Client IP: $remote_addr"
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

You should receive a response similar to the following:

```text
HTTP/1.1 200 OK
...
X-Product-Id: apac-398-472
X-User-Id: 100

Client IP: 192.168.65.1
```

### Generate Mock Responses Using JSON Schema

The following example demonstrates how to configure the Plugin to generate mock responses following a specific [JSON schema](https://json-schema.org).

Create a Route with the `mocking` Plugin and define a JSON schema for the expected mock responses:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mocking-route",
    "uri": "/anything",
    "plugins": {
      "mocking": {
        "response_schema": {
          "type": "object",
          "properties": {
            "id": {
              "type": "string",
              "example": "abcd"
            },
            "ip": {
              "type": "number",
              "example": 192.168
            },
            "random_str_arr": {
              "type": "array",
              "items": {
                "type": "string"
              }
            },
            "nested_obj": {
              "type": "object",
              "properties": {
                "random_str": {
                  "type": "string"
                },
                "child_nested_obj": {
                  "type": "object",
                  "properties": {
                    "random_bool": {
                      "type": "boolean",
                      "example": true
                    },
                    "random_int_arr": {
                      "type": "array",
                      "items": {
                        "type": "integer",
                        "example": 155
                      }
                    }
                  }
                }
              }
            }
          }
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

You should see a mock response similar to the following, without an actual response from the Upstream service:

```text
{
  "ip": 192.168,
  "random_str_arr": [
    "fb", "lyquibkwc", "r"
  ],
  "id": "abcd",
  "nested_obj": {
    "random_str": "bzbb",
    "child_nested_obj": {
      "random_bool": true,
      "random_int_arr": [155, 155, 155]
    }
  }
}
```
