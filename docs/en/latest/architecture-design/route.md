---
title: Route
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

The route matches the client's request by defining rules, then loads and executes the corresponding plugin based on the matching result, and forwards the request to the specified Upstream.

The route mainly consists of three parts: matching rules (e.g uri, host, remote_addr, etc.), plugin configuration (current-limit & rate-limit, etc.) and upstream information.

The following image shows an example of some Route rules. When some attribute values are the same, the figure is identified by the same color.

![routes-example](../../../assets/images/routes-example.png)

We configure all the parameters directly in the Route, it's easy to set up, and each Route has a relatively high degree of freedom. But when our Route has more repetitive configurations (such as enabling the same plugin configuration or upstream information), once we need update these same properties, we have to traverse all the Routes and modify them, so it's adding a lot of complexity of management and maintenance.

The shortcomings mentioned above are independently abstracted in APISIX by the two concepts [Service](service.md) and [Upstream](upstream.md).

The route example created below is to proxy the request with URL `/index.html` to the Upstream service with the address `39.97.63.215:80`:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

{"node":{"value":{"uri":"\/index.html","upstream":{"nodes":{"39.97.63.215:80":1},"type":"roundrobin"}},"createdIndex":61925,"key":"\/apisix\/routes\/1","modifiedIndex":61925},"action":"create"}
```

When we receive a successful response, it indicates that the route was successfully created.

For specific options of Route, please refer to [Admin API](../admin-api.md#route).
