---
title: request-validation
keywords:
  - Apache APISIX
  - API Gateway
  - Request Validation
description: The request-validation Plugin validates requests before forwarding them to Upstream services. This Plugin uses JSON Schema for validation and can validate headers and body of a request.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/request-validation" />
</head>

## Description

The `request-validation` Plugin validates requests before forwarding them to Upstream services. This Plugin uses [JSON Schema](https://github.com/api7/jsonschema) for validation and can validate headers and body of a request.

See [JSON schema specification](https://json-schema.org/specification) to learn more about the syntax.

## Attributes

| Name          | Type    | Required | Default | Valid values  | Description                                       |
|---------------|---------|----------|---------|---------------|---------------------------------------------------|
| header_schema | object  | False    |         |               | Schema for the request header data.               |
| body_schema   | object  | False    |         |               | Schema for the request body data.                 |
| rejected_code | integer | False    | 400     | [200,...,599] | Status code to return when rejecting requests. |
| rejected_msg  | string  | False    |         |               | Message to return when rejecting requests.     |

:::note

At least one of `header_schema` or `body_schema` should be filled in.

:::

## Examples

The examples below demonstrate how you can configure `request-validation` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Validate Request Header

The following example demonstrates how to validate request headers against a defined JSON schema, which requires two specific headers and the header value to conform to specified requirements.

Create a Route with `request-validation` Plugin as follows:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "request-validation-route",
    "uri": "/get",
    "plugins": {
      "request-validation": {
        "header_schema": {
          "type": "object",
          "required": ["User-Agent", "Host"],
          "properties": {
            "User-Agent": {
              "type": "string",
              "pattern": "^curl\/"
            },
            "Host": {
              "type": "string",
              "enum": ["httpbin.org", "httpbin"]
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

#### Verify with Request Conforming to the Schema

Send a request with header `Host: httpbin`, which complies with the schema:

```shell
curl -i "http://127.0.0.1:9080/get" -H "Host: httpbin"
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin",
    "User-Agent": "curl/7.74.0",
    "X-Amzn-Trace-Id": "Root=1-6509ae35-63d1e0fd3934e3f221a95dd8",
    "X-Forwarded-Host": "httpbin"
  },
  "origin": "127.0.0.1, 183.17.233.107",
  "url": "http://httpbin/get"
}
```

#### Verify with Request Not Conforming to the Schema

Send a request without any header:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should receive an `HTTP/1.1 400 Bad Request` response, showing that the request fails to pass validation:

```text
property "Host" validation failed: matches none of the enum value
```

Send a request with the required headers but with non-conformant header value:

```shell
curl -i "http://127.0.0.1:9080/get" -H "Host: httpbin" -H "User-Agent: cli-mock"
```

You should receive an `HTTP/1.1 400 Bad Request` response showing the `User-Agent` header value does not match the expected pattern:

```text
property "User-Agent" validation failed: failed to match pattern "^curl/" with "cli-mock"
```

### Customize Rejection Message and Status Code

The following example demonstrates how to customize response status and message when the validation fails.

Configure the Route with `request-validation` as follows:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "request-validation-route",
    "uri": "/get",
    "plugins": {
      "request-validation": {
        "header_schema": {
          "type": "object",
          "required": ["Host"],
          "properties": {
            "Host": {
              "type": "string",
              "enum": ["httpbin.org", "httpbin"]
            }
          }
        },
        "rejected_code": 403,
        "rejected_msg": "Request header validation failed."
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

Send a request with a misconfigured `Host` in the header:

```shell
curl -i "http://127.0.0.1:9080/get" -H "Host: httpbin2"
```

You should receive an `HTTP/1.1 403 Forbidden` response with the custom message:

```text
Request header validation failed.
```

### Validate Request Body

The following example demonstrates how to validate request body against a defined JSON schema.

The `request-validation` Plugin supports validation of two types of media types:

* `application/json`
* `application/x-www-form-urlencoded`

#### Validate JSON Request Body

Create a Route with `request-validation` Plugin as follows:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "request-validation-route",
    "uri": "/post",
    "plugins": {
      "request-validation": {
        "header_schema": {
          "type": "object",
          "required": ["Content-Type"],
          "properties": {
            "Content-Type": {
            "type": "string",
            "pattern": "^application\/json$"
            }
          }
        },
        "body_schema": {
          "type": "object",
          "required": ["required_payload"],
          "properties": {
            "required_payload": {"type": "string"},
            "boolean_payload": {"type": "boolean"},
            "array_payload": {
              "type": "array",
              "minItems": 1,
              "items": {
                "type": "integer",
                "minimum": 200,
                "maximum": 599
              },
              "uniqueItems": true,
              "default": [200]
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

Send a request with JSON body that conforms to the schema to verify:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{"required_payload":"hello", "array_payload":[301]}'
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  "args": {},
  "data": "{\"array_payload\":[301],\"required_payload\":\"hello\"}",
  "files": {},
  "form": {},
  "headers": {
    ...
  },
  "json": {
    "array_payload": [
      301
    ],
    "required_payload": "hello"
  },
  "origin": "127.0.0.1, 183.17.233.107",
  "url": "http://127.0.0.1/post"
}
```

If you send a request without specifying `Content-Type: application/json`:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -d '{"required_payload":"hello,world"}'
```

You should receive an `HTTP/1.1 400 Bad Request` response similar to the following:

```text
property "Content-Type" validation failed: failed to match pattern "^application/json$" with "application/x-www-form-urlencoded"
```

Similarly, if you send a request without the required JSON field `required_payload`:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{}'
```

You should receive an `HTTP/1.1 400 Bad Request` response:

```text
property "required_payload" is required
```

#### Validate URL-Encoded Form Body

Create a Route with `request-validation` Plugin as follows:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "request-validation-route",
    "uri": "/post",
    "plugins": {
      "request-validation": {
        "header_schema": {
          "type": "object",
          "required": ["Content-Type"],
          "properties": {
            "Content-Type": {
              "type": "string",
              "pattern": "^application\/x-www-form-urlencoded$"
            }
          }
        },
        "body_schema": {
          "type": "object",
          "required": ["required_payload","enum_payload"],
          "properties": {
            "required_payload": {"type": "string"},
            "enum_payload": {
              "type": "string",
              "enum": ["enum_string_1", "enum_string_2"],
              "default": "enum_string_1"
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

Send a request with URL-encoded form data to verify:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "required_payload=hello&enum_payload=enum_string_1"
```

You should receive an `HTTP/1.1 400 Bad Request` response similar to the following:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "enum_payload": "enum_string_1",
    "required_payload": "hello"
  },
  "headers": {
    ...
  },
  "json": null,
  "origin": "127.0.0.1, 183.17.233.107",
  "url": "http://127.0.0.1/post"
}
```

Send a request without the URL-encoded field `enum_payload`:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "required_payload=hello"
```

You should receive an `HTTP/1.1 400 Bad Request` of the following:

```text
property "enum_payload" is required
```

## Appendix: JSON Schema

The following section provides boilerplate JSON schema for you to adjust, combine, and use with this Plugin. For a complete reference, see [JSON schema specification](https://json-schema.org/specification).

### Enumerated Values

```json
{
  "body_schema": {
    "type": "object",
    "required": ["enum_payload"],
    "properties": {
      "enum_payload": {
        "type": "string",
        "enum": ["enum_string_1", "enum_string_2"],
        "default": "enum_string_1"
      }
    }
  }
}
```

### Boolean Values

```json
{
  "body_schema": {
    "type": "object",
    "required": ["bool_payload"],
    "properties": {
      "bool_payload": {
        "type": "boolean",
        "default": true
      }
    }
  }
}
```

### Numeric Values

```json
{
  "body_schema": {
    "type": "object",
    "required": ["integer_payload"],
    "properties": {
      "integer_payload": {
        "type": "integer",
        "minimum": 1,
        "maximum": 65535
      }
    }
  }
}
```

### Strings

```json
{
  "body_schema": {
    "type": "object",
    "required": ["string_payload"],
    "properties": {
      "string_payload": {
        "type": "string",
        "minLength": 1,
        "maxLength": 32
      }
    }
  }
}
```

### RegEx for Strings

```json
{
  "body_schema": {
    "type": "object",
    "required": ["regex_payload"],
    "properties": {
      "regex_payload": {
        "type": "string",
        "minLength": 1,
        "maxLength": 32,
        "pattern": "[[^[a-zA-Z0-9_]+$]]"
      }
    }
  }
}
```

### Arrays

```json
{
  "body_schema": {
    "type": "object",
    "required": ["array_payload"],
    "properties": {
      "array_payload": {
        "type": "array",
        "minItems": 1,
        "items": {
          "type": "integer",
          "minimum": 200,
          "maximum": 599
        },
        "uniqueItems": true,
        "default": [200, 302]
      }
    }
  }
}
```
