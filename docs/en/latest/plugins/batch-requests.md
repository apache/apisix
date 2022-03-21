---
title: batch-requests
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

## Description

`batch-requests` can accept multiple request and send them from `apisix` via [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining), and return an aggregated response to client, which can significantly improve performance when the client needs to access multiple APIs.

> **Tips**
>
> The HTTP headers for the outer batch request, except for the Content- headers such as Content-Type, apply to every request in the batch. If you specify a given HTTP header in both the outer request and the individual call, the header's value of individual call would override the outer batch request header's value. The headers for an individual call apply only to that call.

## Attributes

None

## API

This plugin will add `/apisix/batch-requests` as the endpoint.
You may need to use [public-api](public-api.md) plugin to expose it.

## How To Enable

Enable the batch-requests plugin in the `config.yaml`:

```
# Add this in config.yaml
plugins:
  - ... # plugin you need
  - batch-requests
```

## How To Configure

By default, the maximum body size sent to the `/apisix/batch-requests` can't be larger than 1 MiB.
You can configure it via `apisix/admin/plugin_metadata/batch-requests`:

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/batch-requests -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "max_body_size": 4194304
}'
```

## Metadata

| Name             | Type    | Requirement | Default       | Valid   | Description                                                                              |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| max_body_size       | integer  | required   |  1048576  |    > 0  | the maximum of request body size in bytes |

## Batch API Request/Response

The plugin will create a API in `apisix` to handle your batch request.

### Batch API Request:

| Name     | Type                        | Requirement | Default | Valid | Description                           |
| -------- | --------------------------- | ----------- | ------- | ----- | ------------------------------------- |
| query    | object                      | optional    |         |       | Specify `query string` for all request |
| headers  | object                      | optional    |         |       | Specify `header` for all request      |
| timeout  | integer                     | optional    | 30000   |       | Aggregate API timeout in `ms`         |
| pipeline | [HttpRequest](#httprequest) | required    |         |       | Request's detail                      |

#### HttpRequest

| Name       | Type    | Requirement | Default | Valid                                                                            | Description                                                                                             |
| ---------- | ------- | ----------- | ------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| version    | string  | optional    | 1.1     | [1.0, 1.1]                                                                       | http version                                                                                            |
| method     | string  | optional    | GET     | ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "CONNECT", "TRACE"] | http method                                                                                             |
| query      | object  | optional    |         |                                                                                  | request's `query string`, if `Key` is conflicted with global `query`, this setting's value will be used. |
| headers    | object  | optional    |         |                                                                                  | request's `header`, if `Key` is conflicted with global `headers`, this setting's value will be used.    |
| path       | string  | required    |         |                                                                                  | http request's path                                                                                     |
| body       | string  | optional    |         |                                                                                  | http request's body                                                                                     |
| ssl_verify | boolean | optional    | false   |                                                                                  | verify if SSL cert matches hostname.                                                                    |

### Batch API Response：

Response is `Array` of [HttpResponse](#httpresponse).

#### HttpResponse

| Name    | Type    | Description           |
| ------- | ------- | --------------------- |
| status  | integer | http status code      |
| reason  | string  | http reason phrase    |
| body    | string  | http response body    |
| headers | object  | http response headers |

## How to specify custom uri

We have the [public-api](public-api.md) plugin, customizing the uri becomes even easier. We just need to set the `uri` you want when creating the route and change the configuration of the `public-api` plugin.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/br -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/batch-requests",
    "plugins": {
        "public-api": {
            "uri": "/apisix/batch-requests"
        }
    }
}'
```

## Test Plugin

First you need to setup the route for the API that batch request, which will use the [public-api](public-api.md) plugin.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/br -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/apisix/batch-requests",
    "plugins": {
        "public-api": {}
    }
}'
```

Then, you can pass your request detail to batch API(`/apisix/batch-requests`), APISIX can automatically complete requests via [http pipeline](https://en.wikipedia.org/wiki/HTTP_pipelining). Such as:

```shell
curl --location --request POST 'http://127.0.0.1:9080/apisix/batch-requests' \
--header 'Content-Type: application/json' \
--data '{
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

Normally, you don't need to disable this plugin. If you do need, please make a new list of `plugins` you need in `/conf/config.yaml` to cover the original one.
