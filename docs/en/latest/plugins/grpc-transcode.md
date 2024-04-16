---
title: grpc-transcode
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - gRPC Transcode
  - grpc-transcode
description: This document contains information about the Apache APISIX grpc-transcode Plugin.
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

The `grpc-transcode` Plugin converts between HTTP and gRPC requests.

APISIX takes in an HTTP request, transcodes it and forwards it to a gRPC service, gets the response and returns it back to the client in HTTP format.

<!-- TODO: use an image here to explain the concept better -->

## Attributes

| Name      | Type                                                   | Required | Default | Description                          |
| --------- | ------------------------------------------------------ | -------- | ------- | ------------------------------------ |
| proto_id  | string/integer                                         | True     |         | id of the the proto content.         |
| service   | string                                                 | True     |         | Name of the gRPC service.            |
| method    | string                                                 | True     |         | Method name of the gRPC service.     |
| deadline  | number                                                 | False    | 0       | Deadline for the gRPC service in ms. |
| pb_option | array[string([pb_option_def](#options-for-pb_option))] | False    |         | protobuf options.                    |
| show_status_in_body  | boolean                                     | False    | false   | Whether to display the parsed `grpc-status-details-bin` in the response body |
| status_detail_type | string                                        | False    |         | The message type corresponding to the [details](https://github.com/googleapis/googleapis/blob/b7cb84f5d42e6dba0fdcc2d8689313f6a8c9d7b9/google/rpc/status.proto#L46) part of `grpc-status-details-bin`, if not specified, this part will not be decoded  |

### Options for pb_option

| Type            | Valid values                                                                              |
|-----------------|-------------------------------------------------------------------------------------------|
| enum as result  | `enum_as_name`, `enum_as_value`                                                           |
| int64 as result | `int64_as_number`, `int64_as_string`, `int64_as_hexstring`                                |
| default values  | `auto_default_values`, `no_default_values`, `use_default_values`, `use_default_metatable` |
| hooks           | `enable_hooks`, `disable_hooks`                                                           |

## Enable Plugin

Before enabling the Plugin, you have to add the content of your `.proto` or `.pb` files to APISIX.

You can use the `/admin/protos/id` endpoint and add the contents of the file to the `content` field:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/protos/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

If your proto file contains imports, or if you want to combine multiple proto files, you can generate a `.pb` file and use it in APISIX.

For example, if we have a file called `proto/helloworld.proto` which imports another proto file:

```proto
syntax = "proto3";

package helloworld;
import "proto/import.proto";
...
```

We first generate a `.pb` file from the proto files:

```shell
protoc --include_imports --descriptor_set_out=proto.pb proto/helloworld.proto
```

The output binary file, `proto.pb` will contain both `helloworld.proto` and `import.proto`.

We can now use the content of `proto.pb` in the `content` field of the API request.

As the content of the proto is binary, we encode it in `base64` and configure the content in APISIX:

```shell
curl http://127.0.0.1:9180/apisix/admin/protos/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "content" : "'"$(base64 -w0 /path/to/proto.pb)"'"
}'
```

You should see an `HTTP/1.1 201 Created` response with the following:

```
{"node":{"value":{"create_time":1643879753,"update_time":1643883085,"content":"CmgKEnByb3RvL2ltcG9ydC5wcm90bxIDcGtnIhoKBFVzZXISEgoEbmFtZRgBIAEoCVIEbmFtZSIeCghSZXNwb25zZRISCgRib2R5GAEgASgJUgRib2R5QglaBy4vcHJvdG9iBnByb3RvMwq9AQoPcHJvdG8vc3JjLnByb3RvEgpoZWxsb3dvcmxkGhJwcm90by9pbXBvcnQucHJvdG8iPAoHUmVxdWVzdBIdCgR1c2VyGAEgASgLMgkucGtnLlVzZXJSBHVzZXISEgoEYm9keRgCIAEoCVIEYm9keTI5CgpUZXN0SW1wb3J0EisKA1J1bhITLmhlbGxvd29ybGQuUmVxdWVzdBoNLnBrZy5SZXNwb25zZSIAQglaBy4vcHJvdG9iBnByb3RvMw=="},"key":"\/apisix\/proto\/1"}}
```

Now, we can enable the `grpc-transcode` Plugin to a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/111 -H "X-API-KEY: $admin_key" -X PUT -d '
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

:::note

The Upstream service used here should be a gRPC service. Note that the `scheme` is set to `grpc`.

You can use the [grpc_server_example](https://github.com/api7/grpc_server_example) for testing.

:::

## Example usage

Once you configured the Plugin as mentioned above, you can make a request to APISIX to get a response back from the gRPC service (through APISIX):

```shell
curl -i http://127.0.0.1:9080/grpctest?name=world
```

Response:

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

You can also configure the `pb_option` as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/23 -H "X-API-KEY: $admin_key" -X PUT -d '
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

Now if you check the configured Route:

```shell
curl -i "http://127.0.0.1:9080/zeebe/WorkflowInstanceCreate?bpmnProcessId=order-process&version=1&variables=\{\"orderId\":\"7\",\"ordervalue\":99\}"
```

```
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

## Show `grpc-status-details-bin` in response body

If the gRPC service returns an error, there may be a `grpc-status-details-bin` field in the response header describing the error, which you can decode and display in the response body.

Upload the proto file：

```shell
curl http://127.0.0.1:9180/apisix/admin/protos/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "content" : "syntax = \"proto3\";
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

Enable the `grpc-transcode` plugin，and set the option `show_status_in_body` to `true`：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/grpctest",
    "plugins": {
        "grpc-transcode": {
         "proto_id": "1",
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

Access the route configured above：

```shell
curl -i http://127.0.0.1:9080/grpctest?name=world
```

Response:

```Shell
HTTP/1.1 503 Service Temporarily Unavailable
Date: Wed, 10 Aug 2022 08:59:46 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
grpc-status: 14
grpc-message: Out of service
grpc-status-details-bin: CA4SDk91dCBvZiBzZXJ2aWNlGlcKKnR5cGUuZ29vZ2xlYXBpcy5jb20vaGVsbG93b3JsZC5FcnJvckRldGFpbBIpCAESHFRoZSBzZXJ2ZXIgaXMgb3V0IG9mIHNlcnZpY2UaB3NlcnZpY2U
Server: APISIX web server

{"error":{"details":[{"type_url":"type.googleapis.com\/helloworld.ErrorDetail","value":"\b\u0001\u0012\u001cThe server is out of service\u001a\u0007service"}],"message":"Out of service","code":14}}
```

Note that there is an undecoded field in the return body. If you need to decode the field, you need to add the `message type` of the field in the uploaded proto file.

```shell
curl http://127.0.0.1:9180/apisix/admin/protos/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "content" : "syntax = \"proto3\";
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

Also configure the option `status_detail_type` to `helloworld.ErrorDetail`.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/grpctest",
    "plugins": {
        "grpc-transcode": {
         "proto_id": "1",
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

The fully decoded result is returned.

```Shell
HTTP/1.1 503 Service Temporarily Unavailable
Date: Wed, 10 Aug 2022 09:02:46 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
grpc-status: 14
grpc-message: Out of service
grpc-status-details-bin: CA4SDk91dCBvZiBzZXJ2aWNlGlcKKnR5cGUuZ29vZ2xlYXBpcy5jb20vaGVsbG93b3JsZC5FcnJvckRldGFpbBIpCAESHFRoZSBzZXJ2ZXIgaXMgb3V0IG9mIHNlcnZpY2UaB3NlcnZpY2U
Server: APISIX web server

{"error":{"details":[{"type":"service","message":"The server is out of service","code":1}],"message":"Out of service","code":14}}
```

## Delete Plugin

To remove the `grpc-transcode` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/111 -H "X-API-KEY: $admin_key" -X PUT -d '
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
