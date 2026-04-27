---
title: grpc-web
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - gRPC Web
  - grpc-web
description: grpc-web 插件使网关能够处理来自浏览器和 JavaScript 客户端的 gRPC-Web 请求，将其转换为标准 gRPC 调用并转发给上游 gRPC 服务。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/grpc-web" />
</head>

## 描述

gRPC 是一个基于 HTTP/2 和 Protocol Buffers 的高性能 RPC 框架，但浏览器原生不支持它。gRPC-Web 定义了一种浏览器兼容协议，可通过 HTTP/1.1 或 HTTP/2 发送 gRPC 请求。

`grpc-web` 插件将 gRPC-Web 请求转换为原生 gRPC 调用，并转发给上游 gRPC 服务。

## 属性

| 名称                 | 类型    | 必选项 | 默认值                                    | 描述                                           |
|----------------------|---------|--------|-------------------------------------------|------------------------------------------------|
| cors_allow_headers   | string  | 否     | `content-type,x-grpc-web,x-user-agent`   | 跨域请求中允许携带的请求头，多个请求头用 `,` 分隔。 |

## 请求处理

`grpc-web` 插件使用特定的 HTTP 方法、内容类型和 CORS 规则处理客户端请求。

### 支持的 HTTP 方法

该插件支持：

- `POST`：用于 gRPC-Web 请求
- `OPTIONS`：用于 CORS 预检请求

详情请参阅 [CORS support](https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support)。

### 支持的内容类型

该插件识别以下内容类型：

- `application/grpc-web`
- `application/grpc-web-text`
- `application/grpc-web+proto`
- `application/grpc-web-text+proto`

它会自动解码二进制或 base64 文本格式的消息，并将其转换为标准 gRPC 格式转发给上游服务器。详情请参阅 [Protocol differences vs gRPC over HTTP2](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md#protocol-differences-vs-grpc-over-http2)。

### CORS 处理

该插件自动处理跨域请求。默认情况下：

- 允许所有来源（`*`）
- 允许 `POST` 请求
- 接受的请求头：`content-type`、`x-grpc-web`、`x-user-agent`
- 暴露的响应头：`grpc-status`、`grpc-message`

## 示例

以下示例演示了如何配置并使用带有 gRPC-Web 客户端的 `grpc-web` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 前提条件

在进行示例操作之前，请完成以下步骤来设置上游服务器和 gRPC-Web 客户端。

#### 启动上游服务器

启动一个 [grpcbin 服务器](https://github.com/moul/grpcbin)作为示例上游：

```shell
docker run -d \
  --name grpcbin \
  -p 9000:9000 \
  moul/grpcbin
```

#### 生成 gRPC-Web 客户端代码

下载 Protocol Buffer 定义文件 `hello.proto`：

```shell
curl -O https://raw.githubusercontent.com/moul/pb/master/hello/hello.proto
```

安装 [`protobuf`](https://github.com/protocolbuffers/protobuf/releases) 和 [`protoc-gen-grpc-web`](https://github.com/grpc/grpc-web/releases)。

从 `hello.proto` 生成 gRPC-Web 客户端代码：

```shell
protoc \
  --js_out=import_style=commonjs:. \
  --grpc-web_out=import_style=commonjs,mode=grpcwebtext:. \
  hello.proto
```

您应在当前目录看到两个生成的文件：`hello_pb.js`（Protocol Buffers 消息类）和 `hello_grpc_web_pb.js`（gRPC-Web 客户端存根）。

#### 创建客户端

创建 Node.js 项目并安装所需依赖：

```shell
npm init -y
npm install xhr2 grpc-web google-protobuf
```

创建客户端文件：

```js title="client.js"
const XMLHttpRequest = require('xhr2');
const { HelloServiceClient } = require('./hello_grpc_web_pb');
const { HelloRequest } = require('./hello_pb');

global.XMLHttpRequest = XMLHttpRequest;

function sayHello(){
  const client = new HelloServiceClient('http://127.0.0.1:9080/grpc/web', null, {
    format: 'text',
  });
  const req = new HelloRequest();
  req.setGreeting('jack');

  const call = client.sayHello(req, {}, (err, resp) => {
    if (err) {
      console.error('grpc error:', err.code, err.message);
    } else {
      console.log('reply:', resp.getReply());
    }
  });

  call.on('metadata', (metadata) => {
    console.log('Response headers:', metadata);
  });
}

function lotsOfReplies() {
  const client = new HelloServiceClient('http://127.0.0.1:9080/grpc/web', null, {
    format: 'text',
  });
  const req = new HelloRequest();
  req.setGreeting('rep');
  const stream = client.lotsOfReplies(req, {});

  stream.on('metadata', (metadata) => {
    console.log('Response headers:', metadata);
  });
}

lotsOfReplies()
sayHello()
```

您可以通过 `node client.js` 运行客户端，向 gRPC 服务器通过网关发送一元请求和服务端流式请求。

### 代理 gRPC-Web（前缀匹配路由）

以下示例演示如何使用前面设置的 gRPC-Web 客户端配置并使用 `grpc-web` 插件。

创建启用 `grpc-web` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "id": "grpc-web-route",
  "uri": "/grpc/web/*",
  "plugins": {
    "grpc-web": {}
  },
  "upstream": {
    "scheme": "grpc",
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:9000": 1
    }
  }
}'
```

:::note

在 APISIX 3.15.0 之前的版本中，路由 URI 必须使用前缀匹配，因为 gRPC-Web 客户端会在请求 URI 中包含包名、服务名和方法名。在这些版本中使用绝对 URI 匹配会导致请求无法匹配路由。

在本示例中，路由 URI 必须配置为 `/grpc/web/*`，才能正确匹配如 `/grpc/web/hello.HelloService/SayHello` 这样的客户端请求。使用更宽泛的前缀（如 `/grpc/*`）会导致网关无法正确提取完整的服务路径，从而产生 `unknown service web/hello.HelloService` 等错误。

:::

运行客户端向网关路由发送请求：

```shell
node client.js
```

您应看到来自上游 gRPC 服务器的回复：

```text
Response headers: {
  ...
  'access-control-allow-origin': '*',
  'access-control-expose-headers': 'grpc-message,grpc-status'
}
Response headers: {
  ...
  'access-control-allow-origin': '*',
  'access-control-expose-headers': 'grpc-message,grpc-status'
}
reply: hello jack
```
