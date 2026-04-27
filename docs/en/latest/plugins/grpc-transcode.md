---
title: gRPC Transcoding (grpc-transcode)
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - gRPC Transcode
  - grpc-transcode
description: The grpc-transcode Plugin transforms between HTTP requests and gRPC requests, as well as their corresponding responses.
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

<link rel="canonical" href="https://docs.api7.ai/hub/grpc-transcode" />

## Description

The `grpc-transcode` Plugin transforms between HTTP requests and gRPC requests, as well as their corresponding responses.

With this Plugin enabled, APISIX accepts an HTTP request from the client, transcodes and forwards it to an upstream gRPC service. When APISIX receives the gRPC response, it will transform the response back to an HTTP response and send it to the client.

## Attributes

| Name                 | Type                                                   | Required | Default                                                                     | Description                                                                                                                                                                                                               |
|----------------------|--------------------------------------------------------|----------|-----------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| proto_id             | string/integer                                         | True     |                                                                             | ID of the proto resource, which contains the protocol buffer definitions.                                                                                                                                                 |
| service              | string                                                 | True     |                                                                             | Name of the gRPC service.                                                                                                                                                                                                 |
| method               | string                                                 | True     |                                                                             | Method name of the gRPC service.                                                                                                                                                                                          |
| deadline             | number                                                 | False    | 0                                                                           | Deadline for the gRPC service in ms. This is the time APISIX will wait for a gRPC call to complete.                                                                                                                       |
| pb_option            | array[string([pb_option_def](#options-for-pb_option))] | False    | `["enum_as_name","int64_as_number","auto_default_values","disable_hooks"]`  | Encoder and decoder [options](https://github.com/starwing/lua-protobuf?tab=readme-ov-file#options).                                                                                                                       |
| show_status_in_body  | boolean                                                | False    | false                                                                       | If `true`, display the parsed `grpc-status-details-bin` in the response body.                                                                                                                                             |
| status_detail_type   | string                                                 | False    |                                                                             | The message type corresponding to the [details](https://github.com/googleapis/googleapis/blob/master/google/rpc/status.proto#L46) part of `grpc-status-details-bin`. If not specified, the error message will not be decoded. |

### Options for pb_option

| Type            | Valid values                                                                              |
|-----------------|-------------------------------------------------------------------------------------------|
| enum as result  | `enum_as_name`, `enum_as_value`                                                           |
| int64 as result | `int64_as_number`, `int64_as_string`, `int64_as_hexstring`                                |
| default values  | `auto_default_values`, `no_default_values`, `use_default_values`, `use_default_metatable` |
| hooks           | `enable_hooks`, `disable_hooks`                                                           |

## Examples

The examples below demonstrate how you can configure the `grpc-transcode` Plugin for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

To follow along the examples, start an [example gRPC server](https://github.com/api7/grpc_server_example):

```shell
docker run -d \
  --name grpc-example-server \
  -p 50051:50051 \
  api7/grpc-server-example:1.0.2
```

### Transform between HTTP and gRPC Requests

The following example demonstrates how to configure protobuf in APISIX and transform between HTTP and gRPC requests using the `grpc-transcode` Plugin.

Create a proto resource to store the protobuf:

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "echo-proto",
  "content": "syntax = \"proto3\";
  package echo;
  service EchoService {
    rpc Echo (EchoMsg) returns (EchoMsg);
  }
  message EchoMsg {
    string msg = 1;
  }"
}'
```

Create a Route with the `grpc-transcode` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "grpc-transcode-route",
  "methods": ["GET"],
  "uri": "/echo",
  "plugins": {
    "grpc-transcode": {
      "proto_id": "echo-proto",
      "service": "echo.EchoService",
      "method": "Echo"
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

To verify, send an HTTP request to the Route with parameters defined in `EchoMsg`:

```shell
curl "http://127.0.0.1:9080/echo?msg=Hello"
```

You should receive the following response:

```text
{"msg":"Hello"}
```

### Configure Protobuf with .pb File

The following example demonstrates how to configure protobuf with a `.pb` file and transform between HTTP and gRPC requests using the `grpc-transcode` Plugin.

If your proto file contains imports, or if you want to combine multiple proto files, you can generate a `.pb` file using the [protoc](https://google.github.io/proto-lens/installing-protoc.html) utility and use it in APISIX.

Save the protocol buffer definition to a file called `echo.proto`:

```proto title="echo.proto"
syntax = "proto3";

package echo;

service EchoService {
  rpc Echo (EchoMsg) returns (EchoMsg);
}

message EchoMsg {
  string msg = 1;
}
```

Generate the `.pb` file with the [protoc](https://google.github.io/proto-lens/installing-protoc.html) utility:

```shell
protoc --include_imports --descriptor_set_out=echo_proto.pb echo.proto
```

Convert the `.pb` file from binary to base64 and configure it in APISIX:

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "echo-proto",
  "content" : "'"$(base64 -w0 /path/to/echo_proto.pb)"'"
}'
```

Create a Route with the `grpc-transcode` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "grpc-transcode-route",
  "methods": ["GET"],
  "uri": "/echo",
  "plugins": {
    "grpc-transcode": {
      "proto_id": "echo-proto",
      "service": "echo.EchoService",
      "method": "Echo"
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

To verify, send an HTTP request to the Route:

```shell
curl "http://127.0.0.1:9080/echo?msg=Hello"
```

You should receive the following response:

```text
{"msg":"Hello"}
```

### Display Error Details in Response Body

The following example demonstrates how to configure the `grpc-transcode` Plugin to include the `grpc-status-details-bin` field in the response header for error reporting, when made available by the gRPC server; and decode the message to be displayed in the response body.

Create a proto resource to store the protobuf:

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "hello-proto",
  "content": "syntax = \"proto3\";
  package helloworld;
  service Greeter {
    rpc GetErrResp (HelloRequest) returns (HelloReply) {}
  }
  message HelloRequest {
    string name = 1;
    repeated string items = 2;
  }
  message HelloReply {
    string message = 1;
    repeated string items = 2;
  }"
}'
```

Create a Route with the `grpc-transcode` Plugin and set `show_status_in_body` to `true`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "grpc-transcode-route",
  "uri": "/hello",
  "plugins": {
    "grpc-transcode": {
      "proto_id": "hello-proto",
      "service": "helloworld.Greeter",
      "method": "GetErrResp",
      "show_status_in_body": true
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

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/hello?name=world"
```

You should see an error response similar to the following:

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Date: Wed, 21 Feb 2024 03:08:30 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
grpc-status: 14
grpc-message: Out of service
grpc-status-details-bin: CA4SDk91dCBvZiBzZXJ2aWNlGlcKKnR5cGUuZ29vZ2xlYXBpcy5jb20vaGVsbG93b3JsZC5FcnJvckRldGFpbBIpCAESHFRoZSBzZXJ2ZXIgaXMgb3V0IG9mIHNlcnZpY2UaB3NlcnZpY2U
Server: APISIX/3.8.0

{"error":{"message":"Out of service","code":14,"details":[{"value":"\b\u0001\u0012\u001cThe server is out of service\u001a\u0007service","type_url":"type.googleapis.com/helloworld.ErrorDetail"}]}}
```

Note that certain information is not fully decoded in the error response message.

To decode the message, update the protobuf definition to add the `ErrorDetail` message type:

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "hello-proto",
  "content": "syntax = \"proto3\";
  package helloworld;
  service Greeter {
    rpc GetErrResp (HelloRequest) returns (HelloReply) {}
  }
  message HelloRequest {
    string name = 1;
    repeated string items = 2;
  }
  message HelloReply {
    string message = 1;
    repeated string items = 2;
  }
  message ErrorDetail {
    int64 code = 1;
    string message = 2;
    string type = 3;
  }"
}'
```

Update the Route to configure `status_detail_type`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "grpc-transcode-route",
  "uri": "/hello",
  "plugins": {
    "grpc-transcode": {
      "proto_id": "hello-proto",
      "service": "helloworld.Greeter",
      "method": "GetErrResp",
      "show_status_in_body": true,
      "status_detail_type": "helloworld.ErrorDetail"
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

Send another request to the Route:

```shell
curl -i "http://127.0.0.1:9080/hello?name=world"
```

You should see a response with error message fully decoded:

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Date: Wed, 21 Feb 2024 03:11:43 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
grpc-status: 14
grpc-message: Out of service
grpc-status-details-bin: CA4SDk91dCBvZiBzZXJ2aWNlGlcKKnR5cGUuZ29vZ2xlYXBpcy5jb20vaGVsbG93b3JsZC5FcnJvckRldGFpbBIpCAESHFRoZSBzZXJ2ZXIgaXMgb3V0IG9mIHNlcnZpY2UaB3NlcnZpY2U
Server: APISIX/3.8.0

{"error":{"message":"Out of service","code":14,"details":[{"message":"The server is out of service","code":1,"type":"service"}]}}
```

### Configure Encoder/Decoder Options

The following example demonstrates how to configure encoder and decoder [options](https://github.com/starwing/lua-protobuf?tab=readme-ov-file#options) for the `grpc-transcode` Plugin. Specifically, you will apply the `int64_as_string` option to a method that performs an addition operation to observe its effect.

Create a proto resource to store the protobuf:

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos/plus-proto" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "plus-proto",
  "content": "syntax = \"proto3\";
  package helloworld;
  service Greeter {
    rpc Plus (PlusRequest) returns (PlusReply) {}
  }
  message PlusRequest {
    int64 a = 1;
    int64 b = 2;
  }
  message PlusReply {
    int64 result = 1;
  }"
}'
```

Create a Route with the `grpc-transcode` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "grpc-transcode-route",
  "uri": "/plus",
  "plugins": {
    "grpc-transcode": {
      "proto_id": "plus-proto",
      "service": "helloworld.Greeter",
      "method": "Plus"
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

Send a request to the Route:

```shell
curl "http://127.0.0.1:9080/plus?a=1237528374197491&b=1237528374197491"
```

You should see a response showing a sum of the two numbers:

```text
{"result":2.475056748395e+15}
```

Note that the result loses precision when returned as a number. Update the Route to use the `int64_as_string` option:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/grpc-transcode-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "grpc-transcode-route",
  "uri": "/plus",
  "plugins": {
    "grpc-transcode": {
      "proto_id": "plus-proto",
      "service": "helloworld.Greeter",
      "method": "Plus",
      "pb_option":["int64_as_string"]
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

Send another request to the Route:

```shell
curl "http://127.0.0.1:9080/plus?a=1237528374197491&b=1237528374197491"
```

You should see a response showing a sum of the two numbers with full precision:

```text
{"result":"#2475056748394982"}
```
