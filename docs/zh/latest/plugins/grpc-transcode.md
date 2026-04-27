---
title: gRPC Transcoding (grpc-transcode)
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - gRPC Transcode
  - grpc-transcode
description: grpc-transcode 插件在 HTTP 请求与 gRPC 请求及其对应响应之间进行转换。
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/grpc-transcode" />
</head>

## 描述

`grpc-transcode` 插件在 HTTP 请求与 gRPC 请求及其对应响应之间进行转换。

启用此插件后，APISIX 接收来自客户端的 HTTP 请求，转码后转发给上游 gRPC 服务。当 APISIX 收到 gRPC 响应时，会将其转换回 HTTP 响应并发送给客户端。

## 属性

| 名称                 | 类型                                                   | 必选项 | 默认值                                                                     | 描述                                                                                                                                                                                                                        |
|----------------------|--------------------------------------------------------|--------|----------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| proto_id             | string/integer                                         | 是     |                                                                            | proto 资源的 ID，包含 Protocol Buffer 定义。                                                                                                                                                                                |
| service              | string                                                 | 是     |                                                                            | gRPC 服务名称。                                                                                                                                                                                                             |
| method               | string                                                 | 是     |                                                                            | gRPC 服务的方法名称。                                                                                                                                                                                                       |
| deadline             | number                                                 | 否     | 0                                                                          | gRPC 服务的超时时间，单位为毫秒。即 APISIX 等待 gRPC 调用完成的时间。                                                                                                                                                      |
| pb_option            | array[string([pb_option_def](#pb_option-的选项))]      | 否     | `["enum_as_name","int64_as_number","auto_default_values","disable_hooks"]` | 编码器和解码器[选项](https://github.com/starwing/lua-protobuf?tab=readme-ov-file#options)。                                                                                                                                 |
| show_status_in_body  | boolean                                                | 否     | false                                                                      | 若为 `true`，则在响应体中展示解析后的 `grpc-status-details-bin`。                                                                                                                                                          |
| status_detail_type   | string                                                 | 否     |                                                                            | `grpc-status-details-bin` 中 [details](https://github.com/googleapis/googleapis/blob/master/google/rpc/status.proto#L46) 部分对应的消息类型。若未指定，错误消息将不会被解码。                                               |

### pb_option 的选项

| 类型            | 有效值                                                                                     |
|-----------------|-------------------------------------------------------------------------------------------|
| enum as result  | `enum_as_name`, `enum_as_value`                                                           |
| int64 as result | `int64_as_number`, `int64_as_string`, `int64_as_hexstring`                                |
| default values  | `auto_default_values`, `no_default_values`, `use_default_values`, `use_default_metatable` |
| hooks           | `enable_hooks`, `disable_hooks`                                                           |

## 示例

以下示例演示了如何针对不同场景配置 `grpc-transcode` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

在跟随示例操作之前，请先启动一个[示例 gRPC 服务器](https://github.com/api7/grpc_server_example)：

```shell
docker run -d \
  --name grpc-example-server \
  -p 50051:50051 \
  api7/grpc-server-example:1.0.2
```

### 在 HTTP 和 gRPC 请求之间转换

以下示例演示了如何在 APISIX 中配置 protobuf，并使用 `grpc-transcode` 插件在 HTTP 和 gRPC 请求之间进行转换。

创建 proto 资源以存储 protobuf：

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos/echo-proto" -H "X-API-KEY: $admin_key" -X PUT -d '
{
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

创建启用 `grpc-transcode` 插件的路由：

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

验证时，使用 `EchoMsg` 中定义的参数向路由发送 HTTP 请求：

```shell
curl "http://127.0.0.1:9080/echo?msg=Hello"
```

您应该收到以下响应：

```text
{"msg":"Hello"}
```

### 使用 .pb 文件配置 Protobuf

以下示例演示了如何使用 `.pb` 文件在 APISIX 中配置 protobuf，并使用 `grpc-transcode` 插件在 HTTP 和 gRPC 请求之间进行转换。

如果您的 proto 文件包含 import，或者想合并多个 proto 文件，可以使用 [protoc](https://google.github.io/proto-lens/installing-protoc.html) 工具生成 `.pb` 文件并在 APISIX 中使用。

将 Protocol Buffer 定义保存到名为 `echo.proto` 的文件中：

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

使用 [protoc](https://google.github.io/proto-lens/installing-protoc.html) 工具生成 `.pb` 文件：

```shell
protoc --include_imports --descriptor_set_out=echo_proto.pb echo.proto
```

将 `.pb` 文件从二进制转换为 base64 并在 APISIX 中配置：

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos/echo-proto" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "content" : "'"$(base64 -w0 /path/to/echo_proto.pb)"'"
}'
```

创建启用 `grpc-transcode` 插件的路由：

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

验证时，向路由发送 HTTP 请求：

```shell
curl "http://127.0.0.1:9080/echo?msg=Hello"
```

您应该收到以下响应：

```text
{"msg":"Hello"}
```

### 在响应体中显示错误详情

以下示例演示了如何配置 `grpc-transcode` 插件，使其在 gRPC 服务器提供 `grpc-status-details-bin` 字段时，将其包含在响应头中用于错误报告，并将消息解码后展示在响应体中。

创建 proto 资源以存储 protobuf：

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos/hello-proto" -H "X-API-KEY: $admin_key" -X PUT -d '
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

创建启用 `grpc-transcode` 插件的路由并将 `show_status_in_body` 设为 `true`：

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

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/hello?name=world"
```

您应看到类似以下的错误响应：

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

注意响应中某些信息未被完全解码。

要解码消息，请更新 protobuf 定义以添加 `ErrorDetail` 消息类型：

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos/hello-proto" -H "X-API-KEY: $admin_key" -X PUT -d '
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

更新路由以配置 `status_detail_type`：

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

再次向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/hello?name=world"
```

您应看到错误消息已完全解码的响应：

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

### 配置编码器/解码器选项

以下示例演示了如何为 `grpc-transcode` 插件配置编码器和解码器[选项](https://github.com/starwing/lua-protobuf?tab=readme-ov-file#options)。具体来说，您将对执行加法运算的方法应用 `int64_as_string` 选项，以观察其效果。

创建 proto 资源以存储 protobuf：

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

创建启用 `grpc-transcode` 插件的路由：

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

向路由发送请求：

```shell
curl "http://127.0.0.1:9080/plus?a=1237528374197491&b=1237528374197491"
```

您应看到显示两数之和的响应：

```text
{"result":2.475056748395e+15}
```

注意当结果以数字形式返回时会损失精度。更新路由以使用 `int64_as_string` 选项：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
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

再次向路由发送请求：

```shell
curl "http://127.0.0.1:9080/plus?a=1237528374197491&b=1237528374197491"
```

您应看到精度完整的两数之和：

```text
{"result":"#2475056748394982"}
```
