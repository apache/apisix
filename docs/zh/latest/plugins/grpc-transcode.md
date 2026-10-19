---
title: grpc-transcode
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

默认情况下，插件保持原有的 JSON 映射：字段名与 `.proto` 文件中的写法-致，取值为 [lua-protobuf](https://github.com/starwing/lua-protobuf) 解码的结果。将 `protojson` 设置为 `true`，即可按照其他 gRPC 转码器所使用的 [ProtoJSON](https://protobuf.dev/programming-guides/json/) 规则映射请求和响应。详见 [ProtoJSON 映射](#protojson-映射)。

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
| protojson | boolean | 否 | false | 若为 `true`，则按照 ProtoJSON 规则映射请求和响应。详见 [ProtoJSON 映射](#protojson-映射)。 |
| any_empty_format | string | 否 | `spec` | 当 `protojson` 为 `true` 时，承载 `google.protobuf.Empty` 的 `google.protobuf.Any` 的输出形式：`spec` 省略 `value`，`go` 与 Go `protojson` -样输出 `"value": {}`。请求中两种形式均可接受。 |
| error_response_format | string | 否 | `legacy` | 当 `show_status_in_body` 为 `true` 时错误响应体的格式：`legacy` 为 `{"error": {"code": ..., "message": ...}}`，`flat` 为 `{"code": ..., "message": ...}`。 |
| max_req_body_size | integer | 否 | | 转码时读取的请求体的最大字节数。超出时以 `413` 拒绝请求。未设置时不限制。 |
| max_resp_body_size | integer | 否 | 67108864 | 转码时缓存在内存中的响应体的最大字节数。超出时，若上游返回了 `Content-Length` 则以 `502` 拒绝，否则中断响应。 |

### pb_option 的选项

| 类型            | 有效值                                                                                     |
|-----------------|-------------------------------------------------------------------------------------------|
| enum as result  | `enum_as_name`, `enum_as_value`                                                           |
| int64 as result | `int64_as_number`, `int64_as_string`, `int64_as_hexstring`                                |
| default values  | `auto_default_values`, `no_default_values`, `use_default_values`, `use_default_metatable` |
| hooks           | `enable_hooks`, `disable_hooks`                                                           |

## ProtoJSON 映射

当 `protojson` 为 `true` 时，插件在请求和响应两个方向上都遵循 [ProtoJSON](https://protobuf.dev/programming-guides/json/) 映射：

* 响应使用每个字段的 `json_name`（除非 `.proto` 文件另行指定，否则为 lowerCamelCase）。请求同时接受 `json_name` 和原始字段名，并忽略未知字段。
* 64 位整数在响应中为字符串。请求接受字符串，以及不超过 2^53 的数字。
* 枚举在响应中为名称。请求接受名称和数值。
* `bytes` 为 base64 字符串。
* `float` 和 `double` 的特殊值为 `"NaN"`、`"Infinity"` 和 `"-Infinity"`。请求也接受以字符串形式书写的数字。
* 知名类型（well-known types）使用其 JSON 形式：`Timestamp` 为 RFC 3339 字符串，`Duration` 为 `"1.5s"`，`FieldMask` 为 `"fieldA,fieldB.subField"`，包装类型为被包装的值，`Struct`、`Value` 和 `ListValue` 为普通 JSON，`Any` 为带有 `@type` 字段的嵌入消息（知名类型放在 `value` 字段中）。
* 未跟踪存在性（presence）的 proto3 字段在取默认值时会被省略，空的 repeated 和 map 字段同样会被省略。跟踪存在性的字段（`optional`、`oneof` 成员、消息字段以及 proto2 字段）即使取默认值也会保留。
* `pb_option` 中的 64 位整数、枚举和默认值选项不再生效。

对于 `Content-Type: application/json` 的请求，除 `GET` 和 `HEAD` 外的所有方法都从 JSON 请求体读取，无效的 JSON 会以 `400` 拒绝。其他请求从表单参数（`POST` 且为 `application/x-www-form-urlencoded`）或查询字符串读取，此时 `bool` 和 32 位整数字段也接受字符串形式。

下表对比了两种模式：

| 取值 | `protojson: false` | `protojson: true` |
|------|--------------------|-------------------|
| 字段 `user_id` | `"user_id"` | `"userId"`，请求两者均接受 |
| `int64` 值 `9007199254740993` | 丢失精度的数字，或使用 `int64_as_string` 时为 `"#9007199254740993"` | `"9007199254740993"` |
| `bytes` | 原始字符串 | base64 字符串 |
| `google.protobuf.Timestamp` | `{"seconds": 1700000000, "nanos": 0}` | `"2023-11-14T22:13:20Z"` |
| `google.protobuf.Int32Value` | `{"value": 5}` | `5` |
| 空的 repeated 字段 | `[]` | 省略 |
| 取默认值的 proto3 字段 | 包含（默认使用 `auto_default_values`） | 省略 |
| 无效的 JSON 请求体 | 改为从表单参数或查询字符串读取 | 以 `400` 拒绝 |

## 错误响应

当上游在响应头中返回非 `OK` 的 gRPC 状态时，插件会将其映射为 HTTP 状态码。若 `show_status_in_body` 为 `true`，响应体会描述该错误：

* 当 `protojson` 为 `false` 时，响应体包含解码后的 `grpc-status-details-bin`。若无法解码，响应体包含错误信息，并记录错误日志。
* 当 `protojson` 为 `true` 时，响应体始终为 JSON。`status_detail_type` 类型的状态详情遵循 ProtoJSON 映射，其他详情保留其 `@type` 和 base64 编码的 `value`。若状态详情缺失或无法解码，响应体包含 `grpc-status` 状态码和解码后的 `grpc-message`。

将 `error_response_format` 设置为 `flat`，即可直接返回 `{"code": ..., "message": ...}`，而不是包裹在 `error` 中。

## 限制

* 上游响应必须恰好包含-条未压缩的 gRPC 消息。流式 RPC 在只产生-条响应消息时可以转码。包含多条消息或压缩消息的响应会被中断，而不是返回损坏的 JSON。
* 响应头在转码响应体之前发送，因此上游仅在 trailers 中发送的 gRPC 状态无法改变 HTTP 状态。若这类响应不包含消息，则会被中断。
* 对于 gRPC-Web 客户端，请使用 [grpc-web](./grpc-web.md) 插件。

## 示例

以下示例演示了如何针对不同场景配置 `grpc-transcode` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

在跟随示例操作之前，请先启动-个[示例 gRPC 服务器](https://github.com/api7/grpc_server_example)：

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
curl "http://127.0.0.1:9180/apisix/admin/routes/grpc-transcode-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
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
curl "http://127.0.0.1:9180/apisix/admin/routes/grpc-transcode-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
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
curl "http://127.0.0.1:9180/apisix/admin/routes/grpc-transcode-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
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
curl "http://127.0.0.1:9180/apisix/admin/routes/grpc-transcode-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
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
curl "http://127.0.0.1:9180/apisix/admin/routes/grpc-transcode-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
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
curl "http://127.0.0.1:9180/apisix/admin/routes/grpc-transcode-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
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

### 使用 ProtoJSON 映射

以下示例演示了 ProtoJSON 映射如何改变上-个示例中方法的响应。

更新路由，将 `protojson` 设置为 `true`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/grpc-transcode-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/plus",
  "plugins": {
    "grpc-transcode": {
      "proto_id": "plus-proto",
      "service": "helloworld.Greeter",
      "method": "Plus",
      "protojson": true
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

发送带有 JSON 请求体的请求：

```shell
curl "http://127.0.0.1:9080/plus" -H "Content-Type: application/json" -d '
{
  "a": "1237528374197491",
  "b": 1237528374197491
}'
```

您应看到以十进制字符串表示、精度完整的两数之和：

```text
{"result":"2475056748394982"}
```
