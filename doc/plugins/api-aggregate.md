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

# [Chinese](api-aggregate-cn.md)

# Summary

- [**Description**](#Description)
- [**Attributes**](#Attributes)
- [**How To Enable**](#how-to-Enable)
- [**Aggregation Api Request/Response**](#aggregation-api-request/response)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Description

`api-aggregate` can let you aggregate multiple request on `apisix` via [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining).

## Attributes

None

## How To Enable

Default enbaled

## Aggregation Api Request/Response
The plugin will create a api in `apisix` to handle your aggregation request.

### Aggregate Api Request:

| ParameterName | Type | Optional | Default | Description |
| --- | --- | --- | --- | --- |
| query | Object | Yes | | Specify `QueryString` for all request |
| headers | Object | Yes | | Specify `Header` for all request |
| timeout | Number | Yes | 3000 | Aggregate Api timeout in `ms` |
| pipeline | [HttpRequest](#Request) | No | | Request's detail |

#### HttpRequest
| ParameterName | Type | Optional | Default | Description |
| --- | --- | --- | --- | --- |
| version | Enum | Yes | 1.1 | http version: `1.0` or `1.1` |
| method | Enum | Yes | GET | http method, such as：`GET`. |
| query | Object | Yes | | request's `QueryString`, if `Key` is conflicted with global `query`, this setting's value will be setted.|
| headers | Object | Yes | | request's `Header`, if `Key` is conflicted with global `headers`, this setting's value will be setted.|
| path | String | No | | http request's path |
| body | String | Yes | | http request's body |

### Aggregate Api Response：
Response is `Array` of [HttpResponse](#HttpResponse).

#### HttpResponse
| ParameterName | Type | Description |
| --- | --- | --- | --- | --- |
| status | Integer | http status code |
| reason | String | http reason phrase |
| body | String | http response body |
| headers | Object | http response headers |

## Test Plugin

You can pass your request detail to aggregation api( `/apisix/aggregate` ), `apisix` can automatically complete requests via [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining). Such as: 
```shell
curl --location --request POST 'http://100.109.220.139/apisix/aggregate' \
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

## Disable Plugin

Normally, you don't need to disable this plugin.If you does need please remove it from the `plugins` section of`/conf/config.yaml`.
