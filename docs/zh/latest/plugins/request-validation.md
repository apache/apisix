---
title: request-validation
keywords:
  - APISIX
  - API 网关
  - Request Validation
description: request-validation 插件会在将请求转发到上游服务之前对其进行验证。此插件使用 JSON Schema 进行验证，并且可以验证请求的标头和正文。
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

## 描述

`request-validation` 插件会在将请求转发到上游服务之前对其进行验证。此插件使用 [JSON Schema](https://github.com/api7/jsonschema) 进行验证，并且可以验证请求的标头和正文。

请参阅 [JSON Schema 规范](https://json-schema.org/specification) 了解有关语法的更多信息。

## 属性

| 名称             | 类型   | 必选项 | 默认值 | 有效值 | 描述                       |
| ---------------- | ------ | ----------- | ------- | ----- | --------------------------------- |
| header_schema    | object | 否        |         |       | `header` 数据的 `schema` 数据结构。 |
| body_schema      | object | 否        |         |       | `body` 数据的 `schema` 数据结构。   |
| rejected_code | integer | 否        | 400      | [200,...,599]   | 当请求被拒绝时要返回的状态码。 |
| rejected_msg | string | 否        |         |       | 当请求被拒绝时返回的信息。 |

:::note

`header_schema` 和 `body_schema` 属性至少需要配置其一。

:::

## 示例

以下示例演示了如何针对不同场景配置 `request-validation`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 验证请求标头

下面的示例演示如何根据定义的 JSON Schema 验证请求标头，该模式需要两个特定的标头和标头值符合指定的要求。

使用 `request-validation` 插件创建路由，如下所示：

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

#### 使用符合架构的请求进行验证

发送带有标头 `Host: httpbin` 的请求，该请求符合架构：

```shell
curl -i "http://127.0.0.1:9080/get" -H "Host: httpbin"
```

您应该收到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

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

#### 验证请求是否符合架构

发送不带任何标头的请求：

```shell
curl -i "http://127.0.0.1:9080/get"
```

您应该收到 `HTTP/1.1 400 Bad Request` 响应，表明请求未能通过验证：

```text
property "Host" validation failed: matches none of the enum value
```

发送具有所需标头但标头值不符合的请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "Host: httpbin" -H "User-Agent: cli-mock"
```

您应该收到一个 `HTTP/1.1 400 Bad Request` 响应，显示 `User-Agent` 标头值与预期模式不匹配：

```text
property "User-Agent" validation failed: failed to match pattern "^curl/" with "cli-mock"
```

### 自定义拒绝消息和状态代码

以下示例演示了如何在验证失败时自定义响应状态和消息。

使用 `request-validation` 配置路由，如下所示：

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

发送一个在标头中配置错误的 `Host` 的请求：

```shell
curl -i "http://127.0.0.1:9080/get" -H "Host: httpbin2"
```

您应该收到带有自定义消息的 `HTTP/1.1 403 Forbidden` 响应：

```text
Request header validation failed.
```

### 验证请求主体

以下示例演示如何根据定义的 JSON Schema 验证请求主体。

`request-validation` 插件支持两种媒体类型的验证：

* `application/json`
* `application/x-www-form-urlencoded`

#### 验证 JSON 请求主体

使用 `request-validation` 插件创建路由，如下所示：

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

发送符合架构的 JSON Schema 的请求以验证：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{"required_payload":"hello", "array_payload":[301]}'
```

您应该收到类似于以下内容的 `HTTP/1.1 200 OK` 响应：

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

如果你发送请求时没有指定 `Content-Type：application/json`：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -d '{"required_payload":"hello,world"}'
```

您应该收到类似于以下内容的 `HTTP/1.1 400 Bad Request` 响应：

```text
property "Content-Type" validation failed: failed to match pattern "^application/json$" with "application/x-www-form-urlencoded"
```

如果你发送的请求没有必需的 JSON 字段 `required_pa​​yload`：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{}'
```

您应该收到 `HTTP/1.1 400 Bad Request` 响应：

```text
property "required_payload" is required
```

#### 验证 URL 编码的表单主体

使用 `request-validation` 插件创建路由，如下所示：

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

发送带有 URL 编码的表单数据的请求来验证：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "required_payload=hello&enum_payload=enum_string_1"
```

您应该收到类似于以下内容的 `HTTP/1.1 400 Bad Request` 响应：

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

发送不带 URL 编码字段 `enum_payload` 的请求：

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "required_payload=hello"
```

您应该收到以下 `HTTP/1.1 400 Bad Request`：

```text
property "enum_payload" is required
```

## 附录：JSON 模式

以下部分提供了样板 JSON 模式，供您调整、组合和使用此插件。有关完整参考，请参阅 [JSON 模式规范](https://json-schema.org/specification)。

### 枚举值

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

### 布尔值

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

### 数值

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

### 字符串

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

### 字符串的正则表达式

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

### 数组

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
