---
title: grpc-web
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

The `grpc-web` plugin is a proxy plugin used to process [gRPC Web](https://github.com/grpc/grpc-web) client requests to `gRPC Server`.

gRPC Web Client -> APISIX -> gRPC server

## How To Enable

To enable the `gRPC Web` proxy plugin, routing must use the `Prefix matching` pattern (for example: `/*` or `/grpc/example/*`),
Because the `gRPC Web` client will pass the `package name`, `service interface name`, `method name` and other information declared in the `proto` in the URI (for example: `/path/a6.RouteService/Insert`) ,
When using `Absolute Match`, it will not be able to hit the plugin and extract the `proto` information.

```bash
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri":"/grpc/web/*",
    "plugins":{
        "grpc-web":{}
    },
    "upstream":{
        "scheme":"grpc",
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    }
}'
```

## Test Plugin

- The request method only supports `POST` and `OPTIONS`, refer to: [CORS support](https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support).
- The `Content-Type` supports `application/grpc-web`, `application/grpc-web-text`, `application/grpc-web+proto`, `application/grpc-web-text+proto`, refer to: [Protocol differences vs gRPC over HTTP2](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md#protocol-differences-vs-grpc-over-http2).
- Client deployment, refer to: [gRPC-Web Client Runtime Library](https://www.npmjs.com/package/grpc-web) or [Apache APISIX gRPC Web Test Framework](https://github.com/apache/apisix/tree/master/t/plugin/grpc-web).
- After the `gRPC Web` client is deployed, you can initiate a `gRPC Web` proxy request to `APISIX` through `browser` or `node`.

## Disable Plugin

Just delete the JSON configuration of `grpc-web` in the plugin configuration.
The APISIX plug-in is hot-reloaded, so there is no need to restart APISIX.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri":"/grpc/web/*",
    "plugins":{},
    "upstream":{
        "scheme":"grpc",
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    }
}'
```
