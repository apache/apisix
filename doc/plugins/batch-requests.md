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

# [Chinese](batch-requests-cn.md)

# Summary

- [**Description**](#Description)
- [**Attributes**](#Attributes)
- [**How To Enable**](#how-to-Enable)
- [**Batch Api Request/Response**](#batch-api-request/response)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Description

`batch-requests` can accept mutiple request and send them from `apisix` via [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining),and return a aggregated response to client,this can significantly improve performance when the client needs to access multiple APIs.

## Attributes

None

## How To Enable

Default enbaled

## Batch Api Request/Response
The plugin will create a api in `apisix` to handle your aggregation request.

### Batch Api Request:

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

### Batch Api Response：
Response is `Array` of [HttpResponse](#HttpResponse).

#### HttpResponse
| ParameterName | Type | Description |
| --- | --- | --- |
| status | Integer | http status code |
| reason | String | http reason phrase |
| body | String | http response body |
| headers | Object | http response headers |

## Test Plugin

You can pass your request detail to batch api( `/apisix/batch-requests` ), `apisix` can automatically complete requests via [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining). Such as:
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

response as below：
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
