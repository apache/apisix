---
title: websocket-proxy
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - WebSocket proxy
description: This document contains information about the Apache APISIX websocket-proxy Plugin.
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

The `websocket-proxy` plugin configures advanced parameters for a route whose `upstream.scheme` is
`ws` or `wss`. It currently controls the maximum size of a single WebSocket frame APISIX accepts on
each side of the connection.

By default, APISIX accepts a single frame of up to 65535 bytes from either the downstream client or
the upstream; a larger single frame closes the connection. `enable_websocket` has no such limit,
since it lets nginx relay raw bytes without parsing frames, but `scheme: ws`/`wss` parses every
frame in order to run plugin logic against it, and the underlying library caps a single frame's size
unless told otherwise. This plugin raises that cap for routes that need to send or receive larger
messages, such as a client uploading a file in one WebSocket message.

## Attributes

| Name                      | Type    | Required | Default | Valid values | Description |
|---------------------------|---------|----------|---------|--------------|-------------|
| client_max_payload_len    | integer | optional |         | >= 1         | Max size, in bytes, of a single WebSocket message this route accepts from the downstream client. Left unset, the default of 65535 applies. |
| upstream_max_payload_len  | integer | optional |         | >= 1         | Max size, in bytes, of a single WebSocket message this route accepts from the upstream. Left unset, the default of 65535 applies. |

:::note
This plugin has no effect on a route that uses `enable_websocket` instead of `upstream.scheme: ws`/`wss`.
See the [scheme description in the Admin API reference](../admin-api.md#upstream) for the difference
between the two.
:::

## Example usage

Create a route with `upstream.scheme` set to `ws`, and raise the frame size limit on both sides with
this plugin:

```shell
curl -X PUT 'http://127.0.0.1:9180/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/ws",
    "plugins": {
        "websocket-proxy": {
            "client_max_payload_len": 1048576,
            "upstream_max_payload_len": 1048576
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin",
        "scheme": "ws"
    }
}'
```

Now, a WebSocket message of up to 1 MiB in either direction on `/ws` no longer closes the connection.

## Delete Plugin

To remove the `websocket-proxy` Plugin, you can delete the corresponding JSON configuration from the
Plugin configuration. APISIX will automatically reload and you do not have to restart for this to
take effect.
