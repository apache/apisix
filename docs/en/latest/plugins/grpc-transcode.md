---
title: grpc-transcode
keywords:
  - APISIX
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

### Options for pb_option

| Type            | Valid values                                                                              |
|-----------------|-------------------------------------------------------------------------------------------|
| enum as result  | `enum_as_name`, `enum_as_value`                                                           |
| int64 as result | `int64_as_number`, `int64_as_string`, `int64_as_hexstring`                                |
| default values  | `auto_default_values`, `no_default_values`, `use_default_values`, `use_default_metatable` |
| hooks           | `enable_hooks`, `disable_hooks`                                                           |

## Enabling the Plugin

Before enabling the Plugin, you have to add the content of your `.proto` or `.pb` files to APISIX.

You can use the `/admin/protos/id` endpoint and add the contents of the file to the `content` field:

```shell
curl http://127.0.0.1:9180/apisix/admin/protos/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

As the content of the proto is binary, we encode it in `base64` using this Python script:

```python title="upload_pb.py"
#!/usr/bin/env python
# coding: utf-8

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
api_key = "edd1c9f034335f136f87ad84b625c8f1" # use a different API key

reqParam = {
    "content": content,
}
resp = requests.put("http://127.0.0.1:9180/apisix/admin/protos/" + id, json=reqParam, headers={
    "X-API-KEY": api_key,
})
print(resp.status_code)
print(resp.text)
```

This script will take in a `.pb` file and the `id` to create, encodes the content of the proto to `base64`, and calls the Admin API with this encoded content.

To run the script:

```bash
chmod +x ./upload_pb.py
```

```
./upload_pb.py proto.pb 1
```

Response:

```
# 200
# {"node":{"value":{"create_time":1643879753,"update_time":1643883085,"content":"CmgKEnByb3RvL2ltcG9ydC5wcm90bxIDcGtnIhoKBFVzZXISEgoEbmFtZRgBIAEoCVIEbmFtZSIeCghSZXNwb25zZRISCgRib2R5GAEgASgJUgRib2R5QglaBy4vcHJvdG9iBnByb3RvMwq9AQoPcHJvdG8vc3JjLnByb3RvEgpoZWxsb3dvcmxkGhJwcm90by9pbXBvcnQucHJvdG8iPAoHUmVxdWVzdBIdCgR1c2VyGAEgASgLMgkucGtnLlVzZXJSBHVzZXISEgoEYm9keRgCIAEoCVIEYm9keTI5CgpUZXN0SW1wb3J0EisKA1J1bhITLmhlbGxvd29ybGQuUmVxdWVzdBoNLnBrZy5SZXNwb25zZSIAQglaBy4vcHJvdG9iBnByb3RvMw=="},"key":"\/apisix\/proto\/1"}}
```

Now, we can enable the `grpc-transcode` Plugin to a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/111 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
curl http://127.0.0.1:9180/apisix/admin/routes/23 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Disable Plugin

To disable the `grpc-transcode` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/111 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
