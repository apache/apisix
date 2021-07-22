---
title: gzip
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

## Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

The `gzip` plugin dynamically set the gzip behavior of Nginx.

This plugin requires APISIX to run on [APISIX-OpenResty](../how-to-build.md#6-build-openresty-for-apisix).

## Attributes

| Name      | Type          | Requirement | Default    | Valid                                                                    | Description                                                                                                                                         |
| --------- | ------------- | ----------- | ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| types | array        | optional    |  ["text/html"]            | | dynamically set the `gzip_types` directive |
| min_length | integer        | optional    |  20            | >= 1 | dynamically set the `gzip_min_length` directive |
| comp_level | integer        | optional    |  1            | [1, 9] | dynamically set the `gzip_comp_level` directive |
| http_version | number        | optional    |  1.1            | 1.1, 1.0 | dynamically set the `gzip_http_version` directive |
| buffers.number | integer        | optional    |  32            | >= 1 | dynamically set the `gzip_buffers` directive |
| buffers.size | integer        | optional    |  4096            | >= 1 | dynamically set the `gzip_buffers` directive |
| vary | boolean        | optional    |  false            | | dynamically set the `gzip_vary` directive |

## How To Enable

Here's an example, enable this plugin on the specified route:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "gzip": {
            "buffers": {
                "number": 8
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

## Test Plugin

Use curl to access:

```shell
curl http://127.0.0.1:9080/index.html -i -H "Accept-Encoding: gzip"
HTTP/1.1 404 Not Found
Content-Type: text/html; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 21 Jul 2021 03:52:55 GMT
Server: APISIX/2.7
Content-Encoding: gzip

Warning: Binary output can mess up your terminal. Use "--output -" to tell
Warning: curl to output it to your terminal anyway, or consider "--output
Warning: <FILE>" to save to a file.
```

## Disable Plugin

When you want to disable this plugin, it is very simple,
you can delete the corresponding JSON configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

This plugin has been disabled now. It works for other plugins.
