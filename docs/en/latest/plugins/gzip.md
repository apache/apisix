---
title: gzip
keywords:
  - APISIX
  - Plugin
  - gzip
description: This document contains information about the Apache APISIX gzip Plugin.
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

The `gzip` Plugin dynamically sets the behavior of [gzip in Nginx](https://docs.nginx.com/nginx/admin-guide/web-server/compression/).

:::info IMPORTANT

This Plugin requires APISIX to run on [APISIX-Base](../FAQ.md#how-do-i-build-the-apisix-base-environment).

:::

## Attributes

| Name           | Type                 | Required | Default       | Valid values | Description                                                                             |
|----------------|----------------------|----------|---------------|--------------|-----------------------------------------------------------------------------------------|
| types          | array[string] or "*" | False    | ["text/html"] |              | Dynamically sets the `gzip_types` directive. Special value `"*"` matches any MIME type. |
| min_length     | integer              | False    | 20            | >= 1         | Dynamically sets the `gzip_min_length` directive.                                       |
| comp_level     | integer              | False    | 1             | [1, 9]       | Dynamically sets the `gzip_comp_level` directive.                                       |
| http_version   | number               | False    | 1.1           | 1.1, 1.0     | Dynamically sets the `gzip_http_version` directive.                                     |
| buffers.number | integer              | False    | 32            | >= 1         | Dynamically sets the `gzip_buffers` directive.                                          |
| buffers.size   | integer              | False    | 4096          | >= 1         | Dynamically sets the `gzip_buffers` directive.                                          |
| vary           | boolean              | False    | false         |              | Dynamically sets the `gzip_vary` directive.                                             |

## Enabling the Plugin

The example below enables the `gzip` Plugin on the specified Route:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Example usage

Once you have configured the Plugin as shown above, you can make a request as shown below:

```shell
curl http://127.0.0.1:9080/index.html -i -H "Accept-Encoding: gzip"
```

```
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

To disable the `gzip` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
