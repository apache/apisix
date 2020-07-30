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

# 目录
- [**定义**](#定义)
- [**属性列表**](#属性列表)
- [**如何开启**](#how-to-enable)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)
- [**样例**](#样例)


## 定义

`request-validation` 插件在转发到上游服务之前先验证请求。验证插件使用json-schema验证。该插件可用于验证头部和正文数据。

更多信息可以参考[JSON schema](https://github.com/api7/jsonschema)。

## 属性列表

|Name           |Requirement    |Description|
|---------      |--------       |-----------|
| header_schema |可选       |头部数据模式|
| body_schema   |可选       |正文数据模式|

## 如何开启

创建一条路由并在该路由上启用请求验证插件：

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

如果违反了定义的模式，则插件将产生`400`错误请求。

## 禁用插件

在插件配置中删除相应的json配置以禁用`request-validation`。
APISIX插件是热重载的，因此无需重新启动APISIX。

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


## 样例：

**使用 ENUMS：**

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

**具有多个级别的JSON：**

```json
{
    "body_schema": {
        "type": "object",
        "required": ["required_payload"],
        "properties": {
            "boolean_payload": {"type": "boolean"},
            "child_element_name": {
                "type": "object",
                "properties": {
                    "http_statuses": {
                        "type": "array",
                        "minItems": 1,
                        "items": {
                            "type": "integer",
                            "minimum": 200,
                            "maximum": 599
                        },
                        "uniqueItems": true,
                        "default": [200, 201, 202, 203]
                    }
                }
            }
        }
    }
}
```
