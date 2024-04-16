---
title: Route
keywords:
  - API Gateway
  - Apache APISIX
  - Route
description: This article describes the concept of Route and how to use it.
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

Routes match the client's request based on defined rules, load and execute the corresponding [plugins](./plugin.md), and forwards the request to the specified [Upstream](./upstream.md).

A Route mainly consists of three parts:

1. Matching rules (`uri`, `host`, `remote address`)
2. Plugin configuration (current-limit, rate-limit)
3. Upstream information

The image below shows some example Route rules. Note that the values are of the same color if they are identical.

![routes-example](../../../assets/images/routes-example.png)

All the parameters are configured directly in the Route. It is easy to set up, and each Route has a high degree of freedom.

When Routes have repetitive configurations (say, enabling the same plugin configuration or Upstream information), to update it, we need to traverse all the Routes and modify them. This adds a lot of complexity, making it difficult to maintain.

These shortcomings are independently abstracted in APISIX by two concepts: [Service](service.md) and [Upstream](upstream.md).

## Example

The Route example shown below proxies the request with the URL `/index.html` to the Upstream service with the address `127.0.0.1:1980`.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -i -d '
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

```shell
HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

{"node":{"value":{"uri":"\/index.html","upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"}},"createdIndex":61925,"key":"\/apisix\/routes\/1","modifiedIndex":61925}}
```

A successful response indicates that the route was created.

## Configuration

For specific options of Route, please refer to the [Admin API](../admin-api.md#route).
