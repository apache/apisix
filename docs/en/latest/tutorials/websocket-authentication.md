---
title: WebSocket Authentication
keywords:
  - API Gateway
  - Apache APISIX
  - WebSocket
  - Authentication
description: This article guides you on how to configure authentication for WebSocket connections.
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

Apache APISIX supports [WebSocket](https://en.wikipedia.org/wiki/WebSocket) traffic, but the WebSocket protocol doesn't handle authentication. This article guides you on how to configure authentication for WebSocket connections.

## WebSocket Protocol

To establish a WebSocket connection, the client sends a WebSocket **handshake** request, for which the server returns a WebSocket handshake response, see below:

**Client Request**

```text
GET /chat HTTP/1.1
Host: server.example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==
Sec-WebSocket-Protocol: chat, superchat
Sec-WebSocket-Version: 13
Origin: http://example.com
```

**Server Response**

```text
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: HSmrc0sMlYUkAGmm5OPpG2HaGWk=
Sec-WebSocket-Protocol: chat
```

**Handshake Workflow**

![Websocket Handshake Workflow](https://static.apiseven.com/2022/12/06/638eda2e2415f.png)

## WebSocket Authentication

Apache APISIX supports several ways to do authentication, for example: [basic-auth](https://apisix.apache.org/docs/apisix/plugins/basic-auth/), [key-auth](https://apisix.apache.org/docs/apisix/plugins/key-auth/), [jwt-auth](https://apisix.apache.org/docs/apisix/plugins/jwt-auth/), and so on.

When establishing one connection from Client to Server, in the **handshake** phase, APISIX first checks its authentication information, then chooses to proxy this request or deny it directly.

### Pre-requisite

1. One WebSocket server as the Upstream server. In this article, let's use [Postman's Public Echo Service](https://blog.postman.com/introducing-postman-websocket-echo-service/): `wss://ws.postman-echo.com/raw`.
2. APISIX 3.0 Installed.

:::tip

APISIX 3.0 and APISIX 2.x are using different Admin API endpoint. Please check [APISIX 3.0 Deployment Modes](https://apisix.apache.org/docs/apisix/deployment-modes/).

:::

### Key Auth

#### Create one Route

:::tip
In this article, when using Apache APISIX 3.0:

1. The Upstream server is using `wss` protocol, so we should set `scheme` as `https` in the `upstream` block.
2. Set `enable_websocket` as `true`.
:::

```sh
curl --location --request PUT 'http://127.0.0.1:9180/apisix/admin/routes/1' \
--header 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
--header 'Content-Type: application/json' \
--data-raw '{
    "uri": "/*",
    "methods": ["GET"],
    "enable_websocket": true,
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "ws.postman-echo.com:443": 1
        },
        "scheme": "https"
    }
}'
```

#### Create one Consumer

```sh
curl --location --request PUT 'http://127.0.0.1:9180/apisix/admin/consumers/jack' \
--header 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
--header 'Content-Type: application/json' \
--data-raw '{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "this_is_the_key"
        }
    }
}'
```

#### Connect without Key

Connect `ws://127.0.0.1:9080/raw` without `key`, APISIX returns `401 Unauthorized` status code.

![Connect without Key](https://static.apiseven.com/2022/12/06/638ef6db9dd4b.png)

#### Connect with Key

1. Add one header `apikey` with value `this_is_the_key`;
2. Connect `ws://127.0.0.1:9080/raw` with `key`, it's successfully.

![Connect with key](https://static.apiseven.com/2022/12/06/638efac7c42b6.png)

### Note

Other authentication methods are similar to this one.

## Reference

1. [Wikipedia - WebSocket](https://en.wikipedia.org/wiki/WebSocket)
