---
title: grpc-transcode
keywords:
  - APISIX
  - Plugin
  - gRPC Web
  - grpc-web
description: 本文介绍了关于 Apache APISIX `grpc-transcode` 插件的基本信息及使用方法。
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

## 描述

使用 `grpc-transcode` 插件可以在 HTTP 和 gRPC 请求之间进行转换。

APISIX 接收 HTTP 请求后，首先对请求进行转码，并将转码后的请求转发到 gRPC 服务，获取响应并以 HTTP 格式将其返回给客户端。

<!-- TODO: use an image here to explain the concept better -->

## 属性

| 名称      | 类型                                                                       | 必选项 | 默认值 | 描述                               |
| --------- | -------------------------------------------------  | ----- | ------  ------------------------------ |
| proto_id  | string/integer                                     | 是    |        | `.proto` 内容的 id。             |
| service   | string                                             | 是    |        | gRPC 服务名。                    |
| method    | string                                             | 是    |        | gRPC 服务中要调用的方法名。        |
| deadline  | number                                             | 否    | 0      | gRPC 服务的 deadline，单位为：ms。 |
| pb_option | array[string([pb_option_def](#pb_option-的选项))]    | 否    |        | proto 编码过程中的转换选项。       |

### pb_option 的选项

| 类型            | 有效值                                                                                     |
|-----------------|-------------------------------------------------------------------------------------------|
| enum as result  | `enum_as_name`, `enum_as_value`                                                           |
| int64 as result | `int64_as_number`, `int64_as_string`, `int64_as_hexstring`                                |
| default values  | `auto_default_values`, `no_default_values`, `use_default_values`, `use_default_metatable` |
| hooks           | `enable_hooks`, `disable_hooks`                                                           |

## 启用插件

在启用插件之前，你必须将 `.proto` 或 `.pb` 文件的内容添加到 APISIX。

可以使用 `/admin/protos/id` 接口将文件的内容添加到 `content` 字段：

```shell
curl http://127.0.0.1:9180/apisix/admin/protos/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

如果你的 `.proto` 文件包含 `import`，或者想要把多个 `.proto` 文件合并成一个 proto，你可以生成一个 `.pb` 文件并在 APISIX 中使用它。

假设已经有一个 `.proto` 文件（`proto/helloworld.proto`），它导入了另一个 `proto` 文件：

```proto
syntax = "proto3";

package helloworld;
import "proto/import.proto";
...
```

首先，让我们从 `.proto` 文件创建一个 `.pb` 文件。

```shell
protoc --include_imports --descriptor_set_out=proto.pb proto/helloworld.proto
```

输出的二进制文件 `proto.pb` 将同时包含 `helloworld.proto` 和 `import.proto`。

然后将 `proto.pb` 的内容作为 proto 的 `content` 字段提交。

由于 proto 的内容是二进制的，我们需要使用以下 Python 脚本将其转换成 `base64`：

```python
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
api_key = "edd1c9f034335f136f87ad84b625c8f1" # use your API key

reqParam = {
    "content": content,
}
resp = requests.put("http://127.0.0.1:9180/apisix/admin/protos/" + id, json=reqParam, headers={
    "X-API-KEY": api_key,
})
print(resp.status_code)
print(resp.text)
```

该脚本将使用 `.pb` 文件和要创建的 `id`，将 proto 的内容转换成 `base64`，并使用转换后的内容调用 Admin API。

运行脚本：

```shell
chmod +x ./upload_pb.py
./upload_pb.py proto.pb 1
```

返回结果：

```
# 200
# {"node":{"value":{"create_time":1643879753,"update_time":1643883085,"content":"CmgKEnByb3RvL2ltcG9ydC5wcm90bxIDcGtnIhoKBFVzZXISEgoEbmFtZRgBIAEoCVIEbmFtZSIeCghSZXNwb25zZRISCgRib2R5GAEgASgJUgRib2R5QglaBy4vcHJvdG9iBnByb3RvMwq9AQoPcHJvdG8vc3JjLnByb3RvEgpoZWxsb3dvcmxkGhJwcm90by9pbXBvcnQucHJvdG8iPAoHUmVxdWVzdBIdCgR1c2VyGAEgASgLMgkucGtnLlVzZXJSBHVzZXISEgoEYm9keRgCIAEoCVIEYm9keTI5CgpUZXN0SW1wb3J0EisKA1J1bhITLmhlbGxvd29ybGQuUmVxdWVzdBoNLnBrZy5SZXNwb25zZSIAQglaBy4vcHJvdG9iBnByb3RvMw=="},"key":"\/apisix\/proto\/1"}}
```

现在我们可以在指定路由中启用 `grpc-transcode` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

此处使用的 Upstream 应该是 gRPC 服务。请注意，`scheme` 需要设置为 `grpc`。

可以使用 [grpc_server_example](https://github.com/api7/grpc_server_example) 进行测试。

:::

## 测试插件

通过上述示例配置插件后，你可以向 APISIX 发出请求以从 gRPC 服务（通过 APISIX）获得响应：

访问上面配置的 route：

```shell
curl -i http://127.0.0.1:9080/grpctest?name=world
```

返回结果

```Shell
HTTP/1.1 200 OK
Date: Fri, 16 Aug 2019 11:55:36 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server
Proxy-Connection: keep-alive

{"message":"Hello world"}
```

你也可以配置 `pb_option`，如下所示：

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

可以通过如下命令检查刚刚配置的路由：

```shell
curl -i "http://127.0.0.1:9080/zeebe/WorkflowInstanceCreate?bpmnProcessId=order-process&version=1&variables=\{\"orderId\":\"7\",\"ordervalue\":99\}"
```

```Shell
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

## 禁用插件

当你需要禁用 `grpc-transcode` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
