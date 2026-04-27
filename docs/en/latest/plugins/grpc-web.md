---
title: grpc-web
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - gRPC Web
  - grpc-web
description: The grpc-web Plugin enables the gateway to handle gRPC-Web requests from browsers and JavaScript clients by translating them into standard gRPC calls and forwarding them to upstream gRPC services.
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

## Description

gRPC is a high-performance RPC framework based on HTTP/2 and Protocol Buffers, but it is not natively supported by browsers. gRPC-Web defines a browser-compatible protocol for sending gRPC requests over HTTP/1.1 or HTTP/2.

The `grpc-web` Plugin translates gRPC-Web requests into native gRPC calls and forwards them to upstream gRPC services.

## Attributes

| Name                 | Type    | Required | Default                                   | Description                                                                                             |
|----------------------|---------|----------|-------------------------------------------|---------------------------------------------------------------------------------------------------------|
| cors_allow_headers   | string  | False    | `content-type,x-grpc-web,x-user-agent`   | Comma-separated list of request headers allowed for cross-origin requests.                              |

## Request Handling

The `grpc-web` Plugin processes client requests with specific HTTP methods, content types, and CORS rules.

### Supported HTTP Methods

The Plugin supports:

- `POST` for gRPC-Web requests
- `OPTIONS` for CORS preflight checks

See [CORS support](https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support) for details.

### Supported Content Types

The Plugin recognizes the following content types:

- `application/grpc-web`
- `application/grpc-web-text`
- `application/grpc-web+proto`
- `application/grpc-web-text+proto`

It automatically decodes messages in binary or base64 text format and translates them into standard gRPC for the upstream server. See [Protocol differences vs gRPC over HTTP2](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md#protocol-differences-vs-grpc-over-http2) for more details.

### CORS Handling

The Plugin automatically handles cross-origin requests. By default:

- All origins (`*`) are allowed
- `POST` requests are permitted
- Accepted request headers: `content-type`, `x-grpc-web`, `x-user-agent`
- Exposed response headers: `grpc-status`, `grpc-message`

## Examples

The following examples demonstrate how to configure and use the `grpc-web` Plugin with a gRPC-Web client.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Prerequisites

Before proceeding with the examples, complete the following steps to set up an upstream server and gRPC-Web client.

#### Start an Upstream Server

Start a [grpcbin server](https://github.com/moul/grpcbin) to serve as the example upstream:

```shell
docker run -d \
  --name grpcbin \
  -p 9000:9000 \
  moul/grpcbin
```

#### Generate gRPC-Web Client Code

Download the Protocol Buffer definition `hello.proto`:

```shell
curl -O https://raw.githubusercontent.com/moul/pb/master/hello/hello.proto
```

Install [`protobuf`](https://github.com/protocolbuffers/protobuf/releases) and [`protoc-gen-grpc-web`](https://github.com/grpc/grpc-web/releases).

Generate the gRPC-Web client code from `hello.proto`:

```shell
protoc \
  --js_out=import_style=commonjs:. \
  --grpc-web_out=import_style=commonjs,mode=grpcwebtext:. \
  hello.proto
```

You should see two files generated in the current directory: `hello_pb.js` for Protocol Buffers message classes and `hello_grpc_web_pb.js` for gRPC-Web client stubs.

#### Create a Client

Create a Node.js project and install the required dependencies:

```shell
npm init -y
npm install xhr2 grpc-web google-protobuf
```

Create a client file:

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

  stream.on('data', (response) => {
    console.log('Reply:', response.getReply());
  });

  stream.on('end', () => {
    console.log('Stream ended');
  });

  stream.on('error', (err) => {
    console.error('Error:', err);
  });
}

lotsOfReplies()
sayHello()
```

You can run the client with `node client.js` to send both unary and server-streaming requests to your gRPC server via the gateway.

### Proxy gRPC-Web (Prefix Match Route)

The following example demonstrates how to configure and use the `grpc-web` Plugin with the gRPC-Web client set up previously.

Create a Route with the `grpc-web` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/grpc-web-route" -H "X-API-KEY: $admin_key" -X PUT -d '
{
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

In APISIX versions prior to 3.15.0, the Route URI must use a prefix match because gRPC-Web clients include the package name, service name, and method name in the request URI. Using an absolute URI match in these versions will prevent the request from matching the Route.

In this example, the Route URI must be configured as `/grpc/web/*` to correctly match client requests such as `/grpc/web/hello.HelloService/SayHello`. Using a broader prefix like `/grpc/*` would prevent the gateway from correctly extracting the full service path, resulting in errors such as `unknown service web/hello.HelloService`.

:::

Run the client to send requests to the gateway Route:

```shell
node client.js
```

You should see a reply from the upstream gRPC server:

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
