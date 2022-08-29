---
title: uri-blocker
keywords:
  - APISIX
  - API Gateway
  - URI Blocker
description: This document contains information about the Apache APISIX uri-blocker Plugin.
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

The `uri-blocker` Plugin intercepts user requests with a set of `block_rules`.

## Attributes

| Name             | Type          | Required | Default | Valid values | Description                                                                                                                                                                                           |
|------------------|---------------|----------|---------|--------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| block_rules      | array[string] | True     |         |              | List of regex filter rules. If the request URI hits any one of the rules, the response code is set to the `rejected_code` and the user request is terminated. For example, `["root.exe", "root.m+"]`. |
| rejected_code    | integer       | False    | 403     | [200, ...]   | HTTP status code returned when the request URI hits any of the `block_rules`.                                                                                                                         |
| rejected_msg     | string        | False    |         | non-empty    | HTTP response body returned when the request URI hits any of the `block_rules`.                                                                                                                       |
| case_insensitive | boolean       | False    | false   |              | When set to `true`, ignores the case when matching request URI.                                                                                                                                       |

## Enabling the Plugin

The example below enables the `uri-blocker` Plugin on a specific Route:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/*",
    "plugins": {
        "uri-blocker": {
            "block_rules": ["root.exe", "root.m+"]
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

Once you have configured the Plugin as shown above, you can try accessing the file:

```shell
curl -i http://127.0.0.1:9080/root.exe?a=a
```

```shell
HTTP/1.1 403 Forbidden
Date: Wed, 17 Jun 2020 13:55:41 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 150
Connection: keep-alive
Server: APISIX web server

... ...
```

You can also set a `rejected_msg` and it will be added to the response body:

```shell
HTTP/1.1 403 Forbidden
Date: Wed, 17 Jun 2020 13:55:41 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 150
Connection: keep-alive
Server: APISIX web server

{"error_msg":"access is not allowed"}
```

## Disable Plugin

To disable the `uri-blocker` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/*",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
