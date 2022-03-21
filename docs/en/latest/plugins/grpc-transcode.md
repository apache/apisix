---
title: grpc-transcode
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

HTTP(s) -> APISIX -> gRPC server

### Proto

#### Attributes

* `content`: `.proto` or `.pb` file's content.

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

If your `.proto` file contains imports, or you want to combine multiple `.proto` files into a proto,
you can use `.pb` file to create the proto.

Assumed we have a `.proto` called `proto/helloworld.proto`, which imports another proto file:

```proto
syntax = "proto3";

package helloworld;
import "proto/import.proto";
...
```

First of all, let's create a `.pb` file from `.proto` files:

```shell
protoc --include_imports --descriptor_set_out=proto.pb proto/helloworld.proto
```

The output binary file `proto.pb` will contain both `helloworld.proto` and `import.proto`.

Then we can submit the content of `proto.pb` as the `content` field of the proto.

As the content is binary, we need to encode it in base64 first. Here we use a Python script to do it:

```python
#!/usr/bin/env python
# coding: utf-8
# save this file as upload_pb.py
import base64
import sys
# sudo pip install requests
import requests

if len(sys.argv) <= 1:
    print("bad argument")
    sys.exit(1)
with open(sys.argv[1], 'rb') as f:
    content = base64.b64encode(f.read())
id = sys.argv[2]
api_key = "edd1c9f034335f136f87ad84b625c8f1" # Change it

reqParam = {
    "content": content,
}
resp = requests.put("http://127.0.0.1:9080/apisix/admin/proto/" + id, json=reqParam, headers={
    "X-API-KEY": api_key,
})
print(resp.status_code)
print(resp.text)
```

Create proto:

```bash
chmod +x ./upload_pb.pb
./upload_pb.py proto.pb 1
# 200
# {"node":{"value":{"create_time":1643879753,"update_time":1643883085,"content":"CmgKEnByb3RvL2ltcG9ydC5wcm90bxIDcGtnIhoKBFVzZXISEgoEbmFtZRgBIAEoCVIEbmFtZSIeCghSZXNwb25zZRISCgRib2R5GAEgASgJUgRib2R5QglaBy4vcHJvdG9iBnByb3RvMwq9AQoPcHJvdG8vc3JjLnByb3RvEgpoZWxsb3dvcmxkGhJwcm90by9pbXBvcnQucHJvdG8iPAoHUmVxdWVzdBIdCgR1c2VyGAEgASgLMgkucGtnLlVzZXJSBHVzZXISEgoEYm9keRgCIAEoCVIEYm9keTI5CgpUZXN0SW1wb3J0EisKA1J1bhITLmhlbGxvd29ybGQuUmVxdWVzdBoNLnBrZy5SZXNwb25zZSIAQglaBy4vcHJvdG9iBnByb3RvMw=="},"key":"\/apisix\/proto\/1"},"action":"set"}
```

## Attribute List

| Name      | Type                                                                           | Requirement | Default | Valid | Description                      |
| --------- | ------------------------------------------------------------------------------ | ----------- | ------- | ----- | -------------------------------- |
| proto_id  | string/integer                                                                 | required    |         |       | `.proto` content id.             |
| service   | string                                                                         | required    |         |       | the grpc service name.           |
| method    | string                                                                         | required    |         |       | the method name of grpc service. |
| deadline  | number                                                                         | optional    | 0       |       | deadline for grpc, ms            |
| pb_option | array[string([pb_option_def](#use-pb_option-option-of-grpc-transcode-plugin))] | optional    |         |       | protobuf options                 |

## How To Enable

Here's an example, to enable the grpc-transcode plugin to specified route:

* attention: the `scheme` in the route's upstream must be `grpc`
* the grpc server example：[grpc_server_example](https://github.com/api7/grpc_server_example)

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
