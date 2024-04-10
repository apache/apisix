---
title: mocking
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Mocking
description: 本文介绍了关于 Apache APISIX `mocking` 插件的基本信息及使用方法。
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

`mocking` 插件用于模拟 API。当执行该插件时，它将随机返回指定格式的模拟数据，并且请求不会转发到上游。

## 属性

| 名称            | 类型    | 必选项 | 默认值           |  描述                                                           |
| -------------   | -------| ----- | ---------------- | --------------------------------------------------------------------------- |
| delay           | integer| 否    |                  | 延时返回的时间，单位为秒。                                            |
| response_status | integer| 否    | 200              | 返回响应的 HTTP 状态码。                                            |
| content_type    | string | 否    | application/json | 返回响应的 Header `Content-Type`。                                            |
| response_example| string | 否    |                  | 返回响应的 Body，支持使用变量，例如 `$remote_addr $consumer_name`，与 `response_schema` 字段二选一。 |
| response_schema | object | 否    |                  | 指定响应的 `jsonschema` 对象，未指定 `response_example` 字段时生效。                        |
| with_mock_header| boolean| 否    | true             | 当设置为 `true` 时，将添加响应头 `x-mock-by: APISIX/{version}`。设置为 `false` 时则不添加该响应头。   |
| response_headers| object | 否    |                  | 要在模拟响应中添加的标头。示例：`{"X-Foo": "bar", "X-Few": "baz"}`                               |

JSON Schema 在其字段中支持以下类型：

- `string`
- `number`
- `integer`
- `boolean`
- `object`
- `array`

以下是一个 JSON Schema 示例：

```json
{
    "properties":{
        "field0":{
            "example":"abcd",
            "type":"string"
        },
        "field1":{
            "example":123.12,
            "type":"number"
        },
        "field3":{
            "properties":{
                "field3_1":{
                    "type":"string"
                },
                "field3_2":{
                    "properties":{
                        "field3_2_1":{
                            "example":true,
                            "type":"boolean"
                        },
                        "field3_2_2":{
                            "items":{
                                "example":155.55,
                                "type":"integer"
                            },
                            "type":"array"
                        }
                    },
                    "type":"object"
                }
            },
            "type":"object"
        },
        "field2":{
            "items":{
                "type":"string"
            },
            "type":"array"
        }
    },
    "type":"object"
}
```

以下为上述 JSON Schema 可能生成的返回对象：

```json
{
    "field1": 123.12,
    "field3": {
        "field3_1": "LCFE0",
        "field3_2": {
            "field3_2_1": true,
            "field3_2_2": [
                155,
                155
            ]
        }
    },
    "field0": "abcd",
    "field2": [
        "sC"
    ]
}
```

## 启用插件

你可以通过如下命令在指定路由上启用 `mocking` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "mocking": {
            "delay": 1,
            "content_type": "application/json",
            "response_status": 200,
            "response_schema": {
               "properties":{
                   "field0":{
                       "example":"abcd",
                       "type":"string"
                   },
                   "field1":{
                       "example":123.12,
                       "type":"number"
                   },
                   "field3":{
                       "properties":{
                           "field3_1":{
                               "type":"string"
                           },
                           "field3_2":{
                               "properties":{
                                   "field3_2_1":{
                                       "example":true,
                                       "type":"boolean"
                                   },
                                   "field3_2_2":{
                                       "items":{
                                           "example":155.55,
                                           "type":"integer"
                                       },
                                       "type":"array"
                                   }
                               },
                               "type":"object"
                           }
                       },
                       "type":"object"
                   },
                   "field2":{
                       "items":{
                           "type":"string"
                       },
                       "type":"array"
                   }
               },
               "type":"object"
           }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 测试插件

通过上述命令启用插件后，可以使用如下方式测试插件是否启用成功：

当 `mocking` 插件配置如下：

```JSON
{
  "delay":0,
  "content_type":"",
  "with_mock_header":true,
  "response_status":201,
  "response_example":"{\"a\":1,\"b\":2}"
}
```

通过如下命令进行测试：

```shell
curl http://127.0.0.1:9080/test-mock -i
```

```Shell
HTTP/1.1 201 Created
Date: Fri, 14 Jan 2022 11:49:34 GMT
Content-Type: application/json;charset=utf8
Transfer-Encoding: chunked
Connection: keep-alive
x-mock-by: APISIX/2.10.0
Server: APISIX/2.10.0

{"a":1,"b":2}
```

## 删除插件

当你需要禁用 `mocking` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
