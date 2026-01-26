---
title: grpc-web
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - gRPC Web
  - grpc-web
description: This document contains information about the Apache APISIX grpc-web Plugin.
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

The `grpc-web` Plugin is a proxy Plugin that can process [gRPC Web](https://github.com/grpc/grpc-web) requests from JavaScript clients to a gRPC service.

## Attributes

| Name                    | Type    | Required | Default                                 | Description                                                                                              |
|-------------------------|---------|----------|-----------------------------------------|----------------------------------------------------------------------------------------------------------|
| cors_allow_headers      | string  | False    | "content-type,x-grpc-web,x-user-agent"  | Headers in the request allowed when accessing a cross-origin resource. Use `,` to add multiple headers.  |

## Enable Plugin

You can enable the `grpc-web` Plugin on a specific Route as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

## Example usage

Refer to [gRPC-Web Client Runtime Library](https://www.npmjs.com/package/grpc-web) or [Apache APISIX gRPC Web Test Framework](https://github.com/apache/apisix/tree/master/t/plugin/grpc-web) to learn how to setup your web client.

Once you have your gRPC Web client running, you can make a request to APISIX from the browser or through Node.js.

:::note

The supported request methods are `POST` and `OPTIONS`. See [CORS support](https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support).

The supported `Content-Type` includes `application/grpc-web`, `application/grpc-web-text`, `application/grpc-web+proto`, and `application/grpc-web-text+proto`. See [Protocol differences vs gRPC over HTTP2](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md#protocol-differences-vs-grpc-over-http2).

:::

## Delete Plugin

To remove the `grpc-web` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
