---
title: mocking
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

Mock API 插件，绑定该插件后将随机返回指定格式的`mock`数据，不再转发到后端。

## 属性

| 名称            | 类型    | 必选项 | 默认值 | 有效值                                                            | 描述                                                                                                                                              |
| -------------   | -------| ----- | ----- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| delay           | integer | 可选 |        |                                                                 | 延时返回的时间，单位为秒                                            |
| response_status | integer| 可选  | 200 |                                                                 | 返回的响应 http status code                                            |
| content_type    | string | 可选  | application/json |                                                                 | 返回的响应头的 Content-Type。                                            |
| response_example| string | 可选  |        |                                                                 | 返回的响应体，与`response_schema`字段二选一                                            |
| response_schema | object | 可选  |        |                                                                 | 指定响应的`jsonschema`对象，未指定`response_example`字段时生效，具体结构看后文说明                                            |
| with_mock_header | boolean | 可选 | true  |                                                                 | 是否返回响应头："x-mock-by: APISIX/{version}"，默认返回，指定为 false 则不返回        |

支持的字段类型：`string`, `number`, `integer`, `boolean`, `object`, `array`
基础数据类型（`string`,`number`,`integer`,`boolean`）可通过配置`example`属性指定生成的响应值，未配置时随机返回。
以下是一个`jsonschema`实例：

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

以下为该`jsonschema`可能生成的返回对象：

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

## 如何启用

这里以`route`为例(`service`的使用是同样的方法)，在指定的 `route` 上启用 `mocking` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

当`mocking`插件配置如下时：

```json
{
  "delay":0,
  "content_type":"",
  "with_mock_header":true,
  "response_status":201,
  "response_example":"{\"a\":1,\"b\":2}"
}
```

curl访问将返回如下结果：

```shell
$ curl http://127.0.0.1:9080/test-mock -i
HTTP/1.1 201 Created
Date: Fri, 14 Jan 2022 11:49:34 GMT
Content-Type: application/json;charset=utf8
Transfer-Encoding: chunked
Connection: keep-alive
x-mock-by: APISIX/2.10.0
Server: APISIX/2.10.0

{"a":1,"b":2}
```

## 移除插件

当你想去掉`mocking`插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

现在就已经移除了`mocking`插件了。其他插件的开启和移除也是同样的方法。
