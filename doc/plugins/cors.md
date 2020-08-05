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

# [Chinese](../zh-cn/plugins/cors.md)

# Summary

- [**Description**](#Description)
- [**Attributes**](#Attributes)
- [**How To Enable**](#how-to-Enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Description

`cors` plugin can help you enable [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) easily.

## Attributes

- `allow_origins`: `optional`, Which Origins is allowed to enable CORS, format as：`scheme`://`host`:`port`, for example: https://somehost.com:8081. Multiple origin use `,` to split. When `allow_credential` is `false`, you can use `*` to indicate allow all any origin. you alse can allow all any origins forcefully using `**` even already enable `allow_credential`, but it will bring some securiy risks. Default value: `*`.
- `allow_methods`: `optional`, Which Method is allowed to enable CORS, such as: `GET`, `POST` etc. Multiple method use `,` to split. When `allow_credential` is `false`, you can use `*` to indicate allow all any method. You alse can allow all any method forcefully using `**` even already enable `allow_credential`, but it will bring some securiy risks. Default value: `*`.
- `allow_headers`: `optional`, Which headers are allowed to set in requst when access cross-origin resource. Multiple value use `,` to split. Default value: `*`.
- `expose_headers`: `optional`, Which headers are allowed to set in response when access cross-origin resource. Multiple value use `,` to split. Default value: `*`.
- `max_age`: `optional`, Maximum number of seconds the results can be cached.. Within this time range, the browser will reuse the last check result. `-1` means no cache. Please note that the maximum value is depended on browser, please refer to [MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age#Directives) for details.Default value: `5`.
- `allow_credential`: Enable request include credentia (such as Cookie etc.), Default avlue: `false`.

## How To Enable

Create a `Route` or `Service` object and configure `cors` plugin.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "cors": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## Test Plugin

curl to server, you will find the headers about `CORS` is be returned, it means plugin is working fine.

```shell
curl http://127.0.0.1:9080/hello -v
...
< Server: APISIX web server
< Access-Control-Allow-Origin: *
< Access-Control-Allow-Methods: *
< Access-Control-Allow-Headers: *
< Access-Control-Expose-Headers: *
< Access-Control-Max-Age: 5
...
```

## Disable Plugin

Remove plugin from configuraion.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
