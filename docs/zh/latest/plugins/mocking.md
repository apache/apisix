---
title: mocking
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Mocking
  - mocking
description: mocking 插件无需转发请求到上游服务即可模拟 API 响应，支持自定义状态码、响应体、标头等，适用于 API 测试和开发场景。
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

## 描述

`mocking` 插件允许您在不将请求转发到上游服务的情况下模拟 API 响应。该插件支持自定义响应状态码、响应体、响应头等。在开发、测试或调试阶段，当实际上游服务不可用、正在维护或调用成本较高时，该插件尤为有用。

## 属性

| 名称             | 类型    | 必选项 | 默认值                        | 描述                                                                                                                                   |
|------------------|---------|--------|-------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| delay            | integer | 否     | 0                             | 延迟返回响应的时间，单位为秒。                                                                                                         |
| response_status  | integer | 否     | 200                           | 响应的 HTTP 状态码。                                                                                                                   |
| content_type     | string  | 否     | application/json;charset=utf8 | 响应的 `Content-Type` 标头值。                                                                                                         |
| response_example | string  | 否     |                               | 响应体内容。支持 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)，例如 `$remote_addr`。不应与 `response_schema` 同时配置。 |
| response_schema  | object  | 否     |                               | 用于生成随机模拟响应体的 [JSON Schema](https://json-schema.org) 对象。未配置 `response_example` 时生效。                                |
| with_mock_header | boolean | 否     | true                          | 设置为 `true` 时，将添加响应头 `x-mock-by: APISIX/{version}`。                                                                        |
| response_headers | object  | 否     |                               | 要添加到模拟响应中的标头。例如：`{"X-Foo": "bar"}`。                                                                                  |

`response_schema` 支持以下字段类型：

- `string`
- `number`
- `integer`
- `boolean`
- `object`
- `array`

## 示例

下面的示例演示了如何在不同场景中在路由上配置 `mocking`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 生成特定模拟响应

以下示例演示如何配置插件以生成特定的模拟响应和响应状态码，而不将请求转发到上游服务。

创建带有 `mocking` 插件的路由：

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

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该收到 `HTTP/1.1 201 Created` 模拟响应，响应体如下：

```text
{"Lastname":"Brown","Age":56}
```

### 生成模拟响应标头

以下示例演示如何配置插件以生成模拟响应标头，并在响应体中使用内置的 NGINX 变量。

创建带有 `mocking` 插件的路由：

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

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该收到类似以下内容的响应：

```text
HTTP/1.1 200 OK
...
X-Product-Id: apac-398-472
X-User-Id: 100

Client IP: 192.168.65.1
```

### 使用 JSON Schema 生成模拟响应

以下示例演示如何配置插件以按照特定的 [JSON Schema](https://json-schema.org) 生成模拟响应。

创建带有 `mocking` 插件的路由，并定义 JSON Schema：

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

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该看到类似以下内容的模拟响应，而非来自上游服务的实际响应：

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
