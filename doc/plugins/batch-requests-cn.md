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

# [English](batch-requests.md)

# 目录

- [**简介**](#简介)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**批量接口请求/响应**](#批量接口请求/响应)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 简介

`batch-requests` 插件可以一次接受多个请求并以 [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining) 的方式在网关发起多个http请求，合并结果后再返回客户端，这在客户端需要访问多个接口时可以显著地提升请求性能。

## 属性

无

## 如何启用

本插件默认启用。

## 批量接口请求/响应
插件会为 `apisix` 创建一个 `/apisix/batch-requests` 的接口来处理你的批量请求。

### 接口请求参数:

| 参数名 | 类型 | 可选 | 默认值 | 描述 |
| --- | --- | --- | --- | --- |
| query | Object | Yes | | 给所有请求都携带的 `QueryString` |
| headers | Object | Yes | | 给所有请求都携带的 `Header` |
| timeout | Number | Yes | 3000 | 聚合请求的超时时间，单位为 `ms` |
| pipeline | [HttpRequest](#Request) | No | | Http 请求的详细信息 |

#### HttpRequest
| 参数名 | 类型 | 可选 | 默认值 | 描述 |
| --- | --- | --- | --- | --- |
| version | Enum | Yes | 1.1 | 请求用的 `http` 协议版本，可以使用 `1.0` or `1.1` |
| method | Enum | Yes | GET | 请求使用的 `http` 方法，例如：`GET`. |
| query | Object | Yes | | 独立请求所携带的 `QueryString`, 如果 `Key` 和全局的有冲突，以此设置为主。 |
| headers | Object | Yes | | 独立请求所携带的 `Header`, 如果 `Key` 和全局的有冲突，以此设置为主。 |
| path | String | No | | 请求路径 |
| body | String | Yes | | 请求体 |

### 接口响应参数：
返回值为一个 [HttpResponse](#HttpResponse) 的 `数组`。

#### HttpResponse
| 参数名 | 类型 | 描述 |
| --- | --- | --- |
| status | Integer | Http 请求的状态码 |
| reason | String | Http 请求的返回信息 |
| body | String | Http 请求的响应体 |
| headers | Object | Http 请求的响应头 |

## 测试插件

你可以将要访问的请求信息传到网关的批量请求接口( `/apisix/batch-requests` )，网关会以 [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining) 的方式自动帮你完成请求。
```shell
curl --location --request POST 'http://127.0.0.1:9080/apisix/batch-requests' \
--header 'Content-Type: application/json' \
--d '{
    "headers": {
        "Content-Type": "application/json",
        "admin-jwt":"xxxx"
    },
    "timeout": 500,
    "pipeline": [
        {
            "method": "POST",
            "path": "/community.GiftSrv/GetGifts",
            "body": "test"
        },
        {
            "method": "POST",
            "path": "/community.GiftSrv/GetGifts",
            "body": "test2"
        }
    ]
}'
```

返回如下：
```json
[
    {
        "status": 200,
        "reason": "OK",
        "body": "{\"ret\":500,\"msg\":\"error\",\"game_info\":null,\"gift\":[],\"to_gets\":0,\"get_all_msg\":\"\"}",
        "headers": {
            "Connection": "keep-alive",
            "Date": "Sat, 11 Apr 2020 17:53:20 GMT",
            "Content-Type": "application/json",
            "Content-Length": "81",
            "Server": "APISIX web server"
        }
    },
    {
        "status": 200,
        "reason": "OK",
        "body": "{\"ret\":500,\"msg\":\"error\",\"game_info\":null,\"gift\":[],\"to_gets\":0,\"get_all_msg\":\"\"}",
        "headers": {
            "Connection": "keep-alive",
            "Date": "Sat, 11 Apr 2020 17:53:20 GMT",
            "Content-Type": "application/json",
            "Content-Length": "81",
            "Server": "APISIX web server"
        }
    }
]
```

## 禁用插件

正常来说你不需要禁用本插件，如果有特殊情况，请从 `/conf/config.yaml` 的 `plugins` 节点中移除即可。
