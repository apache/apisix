---
title: request-validation
keywords:
  - Apache APISIX
  - API Gateway
  - Request Validation
description: This document describes the information about the Apache APISIX request-validation Plugin, you can use it to validate the requests before forwarding them to an Upstream service.
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

## Description

The `request-validation` Plugin can be used to validate the requests before forwarding them to an Upstream service. This Plugin uses [JSON Schema](https://github.com/api7/jsonschema) for validation and can be used to validate the headers and body of the request.

## Attributes

| Name          | Type    | Required | Default | Valid values  | Description                                       |
|---------------|---------|----------|---------|---------------|---------------------------------------------------|
| header_schema | object  | False    |         |               | Schema for the request header data.               |
| body_schema   | object  | False    |         |               | Schema for the request body data.                 |
| rejected_code | integer | False    | 400     | [200,...,599] | Status code to show when the request is rejected. |
| rejected_msg  | string  | False    |         |               | Message to show when the request is rejected.     |

:::note

At least one of `header_schema` or `body_schema` should be filled in.

:::

## Enable Plugin

You can configure the Plugin on a specific Route as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
    "plugins": {
        "request-validation": {
            "body_schema": {
                "type": "object",
                "required": ["required_payload"],
                "properties": {
                    "required_payload": {"type": "string"},
                    "boolean_payload": {"type": "boolean"}
                },
                "rejected_msg": "customize reject message"
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

The examples below shows how you can configure this Plugin for different validation scenarios:

### Enum validation

```json
{
    "body_schema": {
        "type": "object",
        "required": ["required_payload"],
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

### Boolean validation

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

### Number or Integer validation

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

### String validation

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

### Regular expression validation

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

### Array validation

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

### Header validation

```json
{
    "header_schema": {
        "type": "object",
        "required": ["Content-Type"],
        "properties": {
            "Content-Type": {
                "type": "string",
                "pattern": "^application\/json$"
            }
        }
    }
}
```

### Combined validation

```json
{
    "body_schema": {
        "type": "object",
        "required": ["boolean_payload", "array_payload", "regex_payload"],
        "properties": {
            "boolean_payload": {
                "type": "boolean"
            },
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
            },
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

### Custom rejection message

```json
{
  "uri": "/get",
  "plugins": {
    "request-validation": {
      "body_schema": {
        "type": "object",
        "required": ["required_payload"],
        "properties": {
          "required_payload": {"type": "string"},
          "boolean_payload": {"type": "boolean"}
        },
        "rejected_msg": "customize reject message"
      }
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:8080": 1
    }
  }
}
```

## Example usage

Once you have configured the Plugin, it will only allow requests that are valid based on the configuration to reach the Upstream service. If not, the requests are rejected with a 400 or a custom status code you configured.

A valid request for the above configuration could look like this:

```shell
curl --header "Content-Type: application/json" \
  --request POST \
  --data '{"boolean-payload":true,"required_payload":"hello"}' \
  http://127.0.0.1:9080/get
```

## Delete Plugin

To remove the `request-validation` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
