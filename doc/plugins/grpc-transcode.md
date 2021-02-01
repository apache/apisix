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

- [中文](../zh-cn/plugins/grpc-transcode.md)

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

| Name      | Type                                                                           | Requirement | Default | Valid | Description                      |
| --------- | ------------------------------------------------------------------------------ | ----------- | ------- | ----- | -------------------------------- |
| proto_id  | string/integer                                                                 | required    |         |       | `.proto` content id.             |
| service   | string                                                                         | required    |         |       | the grpc service name.           |
| method    | string                                                                         | required    |         |       | the method name of grpc service. |
| deadline  | number                                                                         | optional    | 0       |       | deadline for grpc, ms            |
| pb_option | array[string([pb_option_def](#Use-pb_option-option-of-grpc-transcode-plugin))] | optional    |         |       | protobuf options                 |

## How To Enable

Here's an example, to enable the grpc-transcode plugin to specified route:

* attention: the `scheme` in the route's upstream must be `grpc`
* the grpc server example：[grpc_server_example](https://github.com/iresty/grpc_server_example)

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/111 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/grpctest",
    "plugins": {
        "grpc-transcode": {
            "proto_id": "1",
            "service": "helloworld.Greeter",
            "method": "SayHello"
        }
    },
    "upstream": {
        "scheme": "grpc",
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50051": 1
        }
    }
}'
```

## Test Plugin

The above configuration proxy:

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

## Use pb_option option of grpc-transcode plugin

### option list

* enum as result
    * enum_as_name
    * enum_as_value

* int64 as result
    * int64_as_number
    * int64_as_string
    * int64_as_hexstring

* default values option
    * auto_default_values
    * no_default_values
    * use_default_values
    * use_default_metatable

* hooks option
    * enable_hooks
    * disable_hooks

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/23 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/zeebe/WorkflowInstanceCreate",
    "plugins": {
        "grpc-transcode": {
            "proto_id": "1",
            "service": "gateway_protocol.Gateway",
            "method": "CreateWorkflowInstance",
            "pb_option":["int64_as_string"]
        }
    },
    "upstream": {
        "scheme": "grpc",
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:26500": 1
        }
    }
}'
```

### Test pb_option

Visit configured route：

```shell
$ curl -i "http://127.0.0.1:9080/zeebe/WorkflowInstanceCreate?bpmnProcessId=order-process&version=1&variables=\{\"orderId\":\"7\",\"ordervalue\":99\}"
HTTP/1.1 200 OK
Date: Wed, 13 Nov 2019 03:38:27 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
grpc-encoding: identity
grpc-accept-encoding: gzip
Server: APISIX web server
Trailer: grpc-status
Trailer: grpc-message

{"workflowKey":"#2251799813685260","workflowInstanceKey":"#2251799813688013","bpmnProcessId":"order-process","version":1}
```

`"workflowKey":"#2251799813685260"` suggests pb_option configuration success.

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable `grpc-transcode`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/111 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/grpctest",
    "plugins": {},
    "upstream": {
        "scheme": "grpc",
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:50051": 1
        }
    }
}'
```
