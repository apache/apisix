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

[Chinese](../zh-cn/plugins/response-rewrite.md)

# Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

response rewrite plugin, rewrite the content from upstream.

**senario**:

1. can set `Access-Control-Allow-*` series field to support CORS(Cross-origin Resource Sharing).
2. we can set customized `status_code` and `Location` field in header to achieve redirect, you can alse use [redirect](redirect.md) plugin if you just want a redirection.

## Attributes

|Name    |Requirement|Description|
|-------         |-----|------|
|status_code   |optional| New `status code` to client, keep the original response code by default.|
|body          |optional| New `body` to client, and the content-length will be reset too.|
|body_base64   |optional| This is a boolean value，identify if `body` in configuration need base64 decoded before rewrite to client.|
|headers             |optional| Set the new `headers` for client, can set up multiple. If it exists already from upstream, will rewrite the header, otherwise will add the header. You can set the corresponding value to an empty string to remove a header. |

## How To Enable

Here's an example, enable the `response rewrite` plugin on the specified route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "response-rewrite": {
            "body": "{\"code\":\"ok\",\"message\":\"new json body\"}",
            "headers": {
                "X-Server-id": 3,
                "X-Server-status": "on"
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

## Test Plugin

Testing based on the above examples :

```shell
curl -X GET -i  http://127.0.0.1:9080/test/index.html
```

It will output like below,no matter what kind of content from upstream.
```

HTTP/1.1 200 OK
Date: Sat, 16 Nov 2019 09:15:12 GMT
Transfer-Encoding: chunked
Connection: keep-alive
X-Server-id: 3
X-Server-status: on

{"code":"ok","message":"new json body"}
```

This means that the `response rewrite` plugin is in effect.

## Disable Plugin

When you want to disable the `response rewrite` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

The `response rewrite` plugin has been disabled now. It works for other plugins.
