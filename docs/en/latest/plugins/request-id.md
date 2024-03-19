---
title: request-id
keywords:
  - Apache APISIX
  - API Gateway
  - Request ID
description: This document describes information about the Apache APISIX request-id Plugin, you can use it to track API requests by adding a unique ID to each request.
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

The `request-id` Plugin adds a unique ID to each request proxied through APISIX.

This Plugin can be used to track API requests.

:::note

The Plugin will not add a unique ID if the request already has a header with the configured `header_name`.

:::

## Attributes

| Name                | Type    | Required | Default        | Valid values                    | Description                                                            |
| ------------------- | ------- | -------- | -------------- | ------------------------------- | ---------------------------------------------------------------------- |
| header_name         | string  | False    | "X-Request-Id" |                                 | Header name for the unique request ID.                                 |
| include_in_response | boolean | False    | true           |                                 | When set to `true`, adds the unique request ID in the response header. |
| algorithm           | string  | False    | "uuid"         | ["uuid", "nanoid", "range_id"] | Algorithm to use for generating the unique request ID.                 |
| range_id.char_set      | string | False | "abcdefghijklmnopqrstuvwxyzABCDEFGHIGKLMNOPQRSTUVWXYZ0123456789| The minimum string length is 6 | Character set for range_id |
| range_id.length    | integer | False | 16             | Minimum 6 | Id length for range_id algorithm |
| nanoid.char_set      | string | False | "abcdefghijklmnopqrstuvwxyzABCDEFGHIGKLMNOPQRSTUVWXYZ0123456789_-| The minimum string length is 6 | Character set for nanoid |
| nanoid.length    | integer | False | 21             | Minimum 6 | Id length for range_id algorithm |

## Enable Plugin

The example below enables the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "request-id": {
            "include_in_response": true
        }
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

Once you have configured the Plugin as shown above, APISIX will create a unique ID for each request you make:

```shell
curl -i http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 200 OK
X-Request-Id: fe32076a-d0a5-49a6-a361-6c244c1df956
```

## Delete Plugin

To remove the `request-id` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
