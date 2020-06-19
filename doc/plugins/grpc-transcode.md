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

# [Chinese](../zh-cn/plugins/grpc-transcode.md)

## Name

HTTP(s) -> APISIX -> gRPC server

### Proto

#### Attributes

* `content`: `.proto` file's content.

#### Add a proto

Here's an example, adding a proto which `id` is `1`:

```shell
curl http://127.0.0.1:9080/apisix/admin/proto/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "content" : "syntax = \"proto3\";
    package helloworld;
    service Greeter {
        rpc SayHello (HelloRequest) returns (HelloReply) {}
    }
    message HelloRequest {
        string name = 1;
    }
    message HelloReply {
        string message = 1;
    }"
}'
```

## Attribute List

|Name          |Requirement  |Description|
|---------     |--------|-----------|
| proto_id         |required|`.proto` content id.|
| service         |required|the grpc service name.|
| method         |required|the method name of grpc service.|

## How To Enable

Here's an example, to enable the grpc-transcode plugin to specified route:

* attention: the route's option `service_protocol` must be `grpc`
* the grpc server example：[grpc_server_example](https://github.com/iresty/grpc_server_example)

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/111 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/grpctest",
    "service_protocol": "grpc",
    "plugins": {
        "grpc-transcode": {
            "proto_id": "1",
            "service": "helloworld.Greeter",
            "method": "SayHello"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50051": 1
        }
    }
}'
```

## Test Plugin

The above configuration proxy :

```shell
curl -i http://127.0.0.1:9080/grpctest?name=world
```

response:

```shell
HTTP/1.1 200 OK
Date: Fri, 16 Aug 2019 11:55:36 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server
Proxy-Connection: keep-alive

{"message":"Hello world"}
```

This means that the proxying is working.
