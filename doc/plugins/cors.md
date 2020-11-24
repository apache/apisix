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

- [中文](../zh-cn/plugins/cors.md)

# Summary

- [**Description**](#Description)
- [**Attributes**](#Attributes)
- [**How To Enable**](#how-to-Enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Description

`cors` plugin can help you enable [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) easily.

## Attributes

| Name             | Type    | Requirement | Default | Valid | Description                                                  |
| ---------------- | ------- | ----------- | ------- | ----- | ------------------------------------------------------------ |
| allow_origins    | string  | optional    | "*"     |       | Which Origins is allowed to enable CORS, format as：`scheme`://`host`:`port`, for example: https://somehost.com:8081. Multiple origin use `,` to split. When `allow_credential` is `false`, you can use `*` to indicate allow any origin. you also can allow all any origins forcefully using `**` even already enable `allow_credential`, but it will bring some security risks. |
| allow_methods    | string  | optional    | "*"     |       | Which Method is allowed to enable CORS, such as: `GET`, `POST` etc. Multiple method use `,` to split. When `allow_credential` is `false`, you can use `*` to indicate allow all any method. You also can allow any method forcefully using `**` even already enable `allow_credential`, but it will bring some security risks. |
| allow_headers    | string  | optional    | "*"     |       | Which headers are allowed to set in request when access cross-origin resource. Multiple value use `,` to split. When `allow_credential` is `false`, you can use `*` to indicate allow all request headers. You also can allow any header forcefully using `**` even already enable `allow_credential`, but it will bring some security risks. |
| expose_headers   | string  | optional    | "*"     |       | Which headers are allowed to set in response when access cross-origin resource. Multiple value use `,` to split. |
| max_age          | integer | optional    | 5       |       | Maximum number of seconds the results can be cached.. Within this time range, the browser will reuse the last check result. `-1` means no cache. Please note that the maximum value is depended on browser, please refer to [MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age#Directives) for details. |
| allow_credential | boolean | optional    | false   |       | Enable request include credential (such as Cookie etc.). According to CORS specification, if you set this option to `true`, you can not use '*' for other options. |

> **Tips**
>
> Please note that `allow_credential` is a very sensitive option, so choose to enable it carefully. After set it be `true`, the default `*` of other parameters will be invalid, you must specify their values explicitly.
> When using `**`, you must fully understand that it introduces some security risks, such as CSRF, so make sure that this security level meets your expectations before using it。

## How To Enable

Create a `Route` or `Service` object and configure `cors` plugin.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

curl to server, you will find the headers about `CORS` is be returned, which means plugin is working fine.

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

Remove plugin from configuration.

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
