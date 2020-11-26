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

- [中文](../zh-cn/plugins/request-validation.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)
- [**Examples**](#examples)


## Name

`request-validation` plugin validates the requests before forwarding to an upstream service. The validation plugin uses
json-schema to validate the schema. The plugin can be used to validate the headers and body data.

For more information on schema, refer to [JSON schema](https://github.com/api7/jsonschema) for more information.

## Attributes

| Name          | Type   | Requirement | Default | Valid | Description                |
| ------------- | ------ | ----------- | ------- | ----- | -------------------------- |
| header_schema | object | optional    |         |       | schema for the header data |
| body_schema   | object | optional    |         |       | schema for the body data   |

## How To Enable

Create a route and enable the request-validation plugin on the route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
                }
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

## Test Plugin

```shell
curl --header "Content-Type: application/json" \
  --request POST \
  --data '{"boolean-payload":true,"required_payload":"hello"}' \
  http://127.0.0.1:9080/get
```

If the schema is violated the plugin will yield a `400` bad request.

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `request-validation`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
}
```


## Examples:

**`Enum` validate:**

```json
{
    "body_schema": {
        "type": "object",
        "required": ["required_payload"],
        "properties": {
                "emum_payload": {
                "type": "string",
                "enum": ["enum_string_1", "enum_string_2"],
                "default": "enum_string_1"
            }
        }
    }
}
```


**`Boolean` validate:**

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

**`Number` or `Integer` validate:**

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

**`String` validate:**

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

**`Regex` validate:**

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


**`Array` validate:**

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

**Multi-field combination verification:**

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
