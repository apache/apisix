---
title: request-validation
keywords:
  - APISIX
  - API 网关
  - Request Validation
description: 本文介绍了 Apache APISIX request-validation 插件的相关操作，你可以使用此插件验证将要转发给上游服务的请求。
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

## 描述

`request-validation` 插件用于提前验证向上游服务转发的请求。该插件使用 [JSON Schema](https://github.com/api7/jsonschema) 机制进行数据验证，可以验证请求的 `body` 及 `header` 数据。

## 属性

| 名称             | 类型   | 必选项 | 默认值 | 有效值 | 描述                       |
| ---------------- | ------ | ----------- | ------- | ----- | --------------------------------- |
| header_schema    | object | 否        |         |       | `header` 数据的 `schema` 数据结构。 |
| body_schema      | object | 否        |         |       | `body` 数据的 `schema` 数据结构。   |
| rejected_code | integer | 否        | 400      | [200,...,599]   | 当请求被拒绝时要返回的状态码。 |
| rejected_msg | string | 否        |         |       | 当请求被拒绝时返回的信息。 |

:::note 注意

启用该插件时，至少需要配置 `header_schema` 和 `body_schema` 属性中的任意一个，两者也可以同时使用。

:::

## 启用插件

以下示例展示了如何在指定路由上启用 `request-validation` 插件，并设置 `body_schema` 字段：

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
                }
            }
            "rejected_msg": "customize reject message"
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

以下示例展示了不同验证场景下该插件的 JSON 配置：

### 枚举（Enum）验证

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

### 布尔（Boolean）验证

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

### 数字范围（Number or Integer）验证

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

### 字符串长度（String）验证

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

### 正则表达式（Regex）验证

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

### 数组（Array）验证

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

### 多字段组合（Combined）验证

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

### 自定义拒绝信息

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
        }
      },
      "rejected_msg": "customize reject message"
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

按上述配置启用插件后，使用 `curl` 命令请求该路由：

```shell
curl --header "Content-Type: application/json" \
  --request POST \
  --data '{"boolean-payload":true,"required_payload":"hello"}' \
  http://127.0.0.1:9080/get
```

现在只允许符合已配置规则的有效请求到达上游服务。不符合配置的请求将被拒绝，并返回 `400` 或自定义状态码。

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
