---
title: grpc-transcode
keywords:
  - Apache APISIX
  - API 网关
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
| show_status_in_body  | boolean                                 | 否    | false    | 是否在返回体中展示解析过的 `grpc-status-details-bin` |
| status_detail_type | string                                    | 否    |        | `grpc-status-details-bin` 中 [details](https://github.com/googleapis/googleapis/blob/b7cb84f5d42e6dba0fdcc2d8689313f6a8c9d7b9/google/rpc/status.proto#L46) 部分对应的 message type，如果不指定，此部分不进行解码  |

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

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/protos/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

由于 proto 的内容是二进制的，我们需要使用以下 shell 命令将其转换成 `base64`：

```shell
curl http://127.0.0.1:9180/apisix/admin/protos/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "content" : "'"$(base64 -w0 /path/to/proto.pb)"'"
}'
```

返回 `HTTP/1.1 201 Created` 结果如下：

```
{"node":{"value":{"create_time":1643879753,"update_time":1643883085,"content":"CmgKEnByb3RvL2ltcG9ydC5wcm90bxIDcGtnIhoKBFVzZXISEgoEbmFtZRgBIAEoCVIEbmFtZSIeCghSZXNwb25zZRISCgRib2R5GAEgASgJUgRib2R5QglaBy4vcHJvdG9iBnByb3RvMwq9AQoPcHJvdG8vc3JjLnByb3RvEgpoZWxsb3dvcmxkGhJwcm90by9pbXBvcnQucHJvdG8iPAoHUmVxdWVzdBIdCgR1c2VyGAEgASgLMgkucGtnLlVzZXJSBHVzZXISEgoEYm9keRgCIAEoCVIEYm9keTI5CgpUZXN0SW1wb3J0EisKA1J1bhITLmhlbGxvd29ybGQuUmVxdWVzdBoNLnBrZy5SZXNwb25zZSIAQglaBy4vcHJvdG9iBnByb3RvMw=="},"key":"\/apisix\/proto\/1"}}
```

现在我们可以在指定路由中启用 `grpc-transcode` 插件：

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

## 在返回体中展示 `grpc-status-details-bin`

如果 gRPC 服务返回了错误，返回头中可能存在 `grpc-status-details-bin` 字段对错误进行描述，你可以解码该字段，并展示在返回体中。

上传 proto 文件：

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

启用 `grpc-transcode` 插件，并设置选项 `show_status_in_body` 为 `true`：

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

访问上面配置的 route：

```shell
curl -i http://127.0.0.1:9080/grpctest?name=world
```

返回结果

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

注意返回体中还存在未解码的字段，如果需要解码该字段，需要在上传的 proto 文件中加上该字段对应的 `message type`。

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

同时配置选项 `status_detail_type` 为 `helloworld.ErrorDetail`：

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

此时就能返回完全解码后的结果

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

## 删除插件

当你需要禁用 `grpc-transcode` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
