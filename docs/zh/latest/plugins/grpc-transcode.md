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

## 属性

| 名称                 | 类型                                                   | 必选项 | 默认值                                                                     | 描述                                                                                                                                                                                                                        |
|----------------------|--------------------------------------------------------|--------|----------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| proto_id             | string/integer                                         | 是     |                                                                            | proto 资源的 ID，包含 Protocol Buffer 定义。                                                                                                                                                                                |
| service              | string                                                 | 否     |                                                                            | gRPC 服务名称。当 `use_http_annotations` 为 `true` 时不需要配置。                                                                                                                                                            |
| method               | string                                                 | 否     |                                                                            | gRPC 服务的方法名称。当 `use_http_annotations` 为 `true` 时不需要配置。                                                                                                                                                      |
| use_http_annotations | boolean                                                | 否     | false                                                                      | 当设置为 `true` 时，从 proto 中声明的 `google.api.http` 注解解析 gRPC 服务与方法，而不再使用 `service` 与 `method`。详见[根据 google.api.http 注解路由](#根据-googleapihttp-注解路由)。                                        |
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

### 根据 google.api.http 注解路由

配置 `service` 与 `method` 会把一条路由绑定到一个 gRPC 方法，因此包含十个方法的服务需要十条路由。如果 proto 中已声明 [`google.api.http`](https://github.com/googleapis/googleapis/blob/master/google/api/http.proto) 注解，可改为将 `use_http_annotations` 设置为 `true`。插件会读取注解并选出与请求路径和 HTTP 方法匹配的方法，一条路由即可服务整个服务。

:::note

该模式要求使用 `--include_imports` 生成的 `.pb` 描述符文件，因为注解只在其中保留。直接上传到 `/apisix/admin/protos` 的纯文本 `.proto` 无法使用，因为其中的 `import "google/api/annotations.proto"` 无法被解析。

:::

将下面带注解的定义保存为 `item.proto`：

```proto title="item.proto"
syntax = "proto3";

package item;

import "google/api/annotations.proto";

service ItemService {
  rpc GetItem(GetItemRequest) returns (Item) {
    option (google.api.http) = {
      get: "/api/v1/items/{id}"
    };
  }

  rpc CreateItem(CreateItemRequest) returns (Item) {
    option (google.api.http) = {
      post: "/api/v1/items"
      body: "item"
    };
  }
}

message Item {
  string id = 1;
  string title = 2;
}

message GetItemRequest {
  string id = 1;
}

message CreateItemRequest {
  Item item = 1;
}
```

在 `google/api/annotations.proto` 与 `google/api/http.proto` 可被 protoc 找到的前提下生成 `.pb` 文件：

```shell
protoc --include_imports --descriptor_set_out=item.pb item.proto
```

在 APISIX 中配置该文件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/protos/item-proto" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "content" : "'"$(base64 -w0 /path/to/item.pb)"'"
}'
```

创建一条覆盖该服务全部带注解方法的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/item-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/api/v1/*",
  "plugins": {
    "grpc-transcode": {
      "proto_id": "item-proto",
      "use_http_annotations": true
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

发送一个与 `GetItem` 注解匹配的请求：

```shell
curl "http://127.0.0.1:9080/api/v1/items/42"
```

路径中的 `{id}` 会绑定到 `GetItemRequest` 的 `id` 字段，因此你会收到：

```text
{"id":"42","title":"widget"}
```

同一条路由也会服务 `CreateItem`，因为它的注解声明了不同的方法与路径：

```shell
curl "http://127.0.0.1:9080/api/v1/items" -X POST \
  -H "Content-Type: application/json" \
  -d '{"id":"43","title":"gadget"}'
```

由于该注解设置了 `body: "item"`，请求体会映射到 `item` 字段，而不是整个请求消息。

#### 路由的作用范围

路由的 URI 模式决定了暴露面。`/api/v1/*` 会覆盖所有以 `/api/v1/` 开头的注解，包括之后才加入 proto 的注解，因此请将 URI 模式收敛到确实希望对外提供的方法集合。没有注解的方法始终不可访问。

认证插件的优先级高于 `grpc-transcode`，因此 `key-auth`、`jwt-auth` 等会在读取任何注解之前拒绝未认证的请求。

#### 行为与限制

* 匹配使用插件执行时的请求 URI，因此先前插件（如 `proxy-rewrite`）所做的改写会参与注解匹配。
* 从路径中提取的值优先于查询字符串或请求体中绑定到同一字段的值。
* `body` 的取值决定请求体的读取方式：省略时完全不读取请求体，字段只来自路径与查询字符串；`body: "*"` 时整个请求体即为消息，且不再读取查询字符串；`body: "<field>"` 时请求体映射到该字段，其余字段来自查询字符串；此处仅支持顶层字段名，不支持 `body: "item.nested"` 这样的嵌套路径。
* 当多个注解都能匹配同一请求时，字面量片段更多的优先，其次是变量更少的。仍然相同时按服务名与方法名排序，因此匹配顺序不依赖方法在描述符中出现的次序。
* 支持 `additional_bindings`，它们会路由到同一个方法。
* `**` 匹配零个或多个片段，因此 `/v1/{name=**}` 也能匹配 `/v1`。
* 当路径没有匹配到任何注解时，插件返回 `404`；当路径已被绑定但请求方法不在其中时，返回 `405` 并通过 `Allow` 响应头列出被允许的方法。
* 结尾的 `:verb` 会作为独立的部分参与匹配，因此不带 verb 的模板不会接受带 verb 的请求，反之亦然。
* 声明了请求体但无法按 JSON 解析时，返回 `400`。
* 忽略 `custom` 类型的 HTTP 规则，因为它没有固定的 HTTP 方法。
* 不支持 `response_body`：响应始终是完整的消息。
* 与插件的其余部分一样，不支持流式方法。
* 路径参数中被转义的分隔符（`%2F`）会在插件执行前由 NGINX 解码，因此会被当作真正的路径分隔符，无法匹配单片段变量。
* 启用该模式后，配置中的 `service` 与 `method` 会被忽略。

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
