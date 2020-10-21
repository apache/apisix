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

- [English](../../plugins/request-validation.md)

# 目录
- [**名称**](#名称)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)
- [**示例**](#示例)

## 名称

`request-validation` 插件用于提前验证请求向上游转发请求，可以验证请求的 `body` 及 `header` 数据。

该插件使用 `Json Schema` 进行数据验证，有关 `Json Schema` 的更多信息，请参阅 [JSON schema](https://github.com/api7/jsonschema)。


## 属性

| Name          | Type   | Requirement | Default | Valid | Description                       |
| ------------- | ------ | ----------- | ------- | ----- | --------------------------------- |
| header_schema | object | 可选        |         |       | `header` 数据的 `schema` 数据结构 |
| body_schema   | object | 可选        |         |       | `body` 数据的 `schema` 数据结构   |

## 如何启用

创建一条路由并在该路由上启用 `request-validation` 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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


## 测试插件

```shell
curl --header "Content-Type: application/json" \
  --request POST \
  --data '{"boolean-payload":true,"required_payload":"hello"}' \
  http://127.0.0.1:9080/get
```

如果 `Schema` 验证失败，将返回 `400 bad request` 错误。


## 禁用插件

在路由 `plugins` 配置块中删除 `request-validation` 配置，即可禁用该插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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


## 示例

**枚举（Enums）验证:**

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

**布尔（Boolean）验证:**

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

**数字范围（Number or Integer）验证:**

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

**字符串长度（String）验证:**

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

**正则表达式（Regex）验证:**

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


**数组（Array）验证:**

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

**多字段组合（Multiple Fields）验证:**

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
