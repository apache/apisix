---
title: cors
keywords:
  - APISIX
  - API Gateway
  - CORS
description: This document contains information about the Apache APISIX cors Plugin.
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

The `cors` Plugins lets you enable [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) easily.

## Attributes

| Name                      | Type    | Required | Default | Description                                                                                                                                                                                                                                                                                                                                                                                        |
|---------------------------|---------|----------|---------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| allow_origins             | string  | False    | "*"     | Origins to allow CORS. Use the `scheme://host:port` format. For example, `https://somedomain.com:8081`. If you have multiple origins, use a `,` to list them. If `allow_credential` is set to `false`, you can enable CORS for all origins by using `*`. If `allow_credential` is set to `true`, you can forcefully allow CORS on all origins by using `**` but it will pose some security issues. |
| allow_methods             | string  | False    | "*"     | Request methods to enable CORS on. For example `GET`, `POST`. Use `,` to add multiple methods. If `allow_credential` is set to `false`, you can enable CORS for all methods by using `*`. If `allow_credential` is set to `true`, you can forcefully allow CORS on all methods by using `**` but it will pose some security issues.                                                                |
| allow_headers             | string  | False    | "*"     | Headers in the request allowed when accessing a cross-origin resource. Use `,` to add multiple headers. If `allow_credential` is set to `false`, you can enable CORS for all request headers by using `*`. If `allow_credential` is set to `true`, you can forcefully allow CORS on all request headers by using `**` but it will pose some security issues.                                       |
| expose_headers            | string  | False    | "*"     | Headers in the response allowed when accessing a cross-origin resource. Use `,` to add multiple headers. If `allow_credential` is set to `false`, you can enable CORS for all response headers by using `*`. If `allow_credential` is set to `true`, you can forcefully allow CORS on all response headers by using `**` but it will pose some security issues.                                    |
| max_age                   | integer | False    | 5       | Maximum time in seconds the result is cached. If the time is within this limit, the browser will check the cached result. Set to `-1` to disable caching. Note that the maximum value is browser dependent. See [Access-Control-Max-Age](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age#Directives) for more details.                                            |
| allow_credential          | boolean | False    | false   | When set to `true`, allows requests to include credentials like cookies. According to CORS specification, if you set this to `true`, you cannot use '*' to allow all for the other attributes.                                                                                                                                                                                                     |
| allow_origins_by_regex    | array   | False    | nil     | Regex to match with origin for enabling CORS. For example, `[".*\.test.com"]` can match all subdomain of `test.com`.                                                                                                                                                                                                                                                                               |
| allow_origins_by_metadata | array   | False    | nil     | Origins to enable CORS referenced from `allow_origins` set in the Plugin metadata. For example, if `"allow_origins": {"EXAMPLE": "https://example.com"}` is set in the Plugin metadata, then `["EXAMPLE"]` can be used to allow CORS on the origin `https://example.com`.                                                                                                                          |

:::info IMPORTANT

1. The `allow_credential` attribute is sensitive and must be used carefully. If set to `true` the default value `*` of the other attributes will be invalid and they should be specified explicitly.
2. When using `**` you are vulnerable to security risks like CSRF. Make sure that this meets your security levels before using it.

:::

## Metadata

| Name          | Type   | Required | Description                                                                                                                                                                                             |
|---------------|--------|----------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| allow_origins | object | False    | A map with origin reference and allowed origins. The keys in the map are used in the attribute `allow_origins_by_metadata` and the value are equivalent to the `allow_origins` attribute of the Plugin. |

## Enabling the Plugin

You can enable the Plugin on a specific Route or Service:

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

## Example usage

After enabling the Plugin, you can make a request to the server and see the CORS headers returned:

```shell
curl http://127.0.0.1:9080/hello -v
```

```shell
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

To disable the `cors` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
