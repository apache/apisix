---
title: mcp-bridge
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - mcp-bridge
  - MCP
description: The mcp-bridge Plugin exposes a stdio-based MCP server through HTTP SSE endpoints.
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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `mcp-bridge` Plugin exposes a stdio-based Model Context Protocol
(MCP) server through HTTP Server-Sent Events (SSE) endpoints. When a
client connects to the SSE endpoint, APISIX starts the configured MCP
server process, forwards client messages to the process through stdin,
and streams MCP responses back to the client.

For a Route configured with `base_uri: /mcp`, the Plugin exposes:

- `GET /mcp/sse`: the SSE endpoint used by MCP clients.
- `POST /mcp/message?sessionId=<session-id>`: the endpoint used to send
  client messages to the MCP session.

Only configure commands that you trust. The configured process runs on
the same host as APISIX and is managed by the APISIX worker handling the
MCP session.

## Attributes

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `base_uri` | string | False | `""` | URI prefix for the generated MCP SSE and message endpoints. |
| `command` | string | True | | Command used to start the stdio-based MCP server. |
| `args` | array[string] | False | | Arguments passed to `command`. |

## Examples

The following example demonstrates how to expose a stdio-based MCP
server through APISIX.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an
environment variable with the following command:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Expose an MCP Server

Create a Route with the `mcp-bridge` Plugin:

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/mcp-bridge" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/mcp/*",
    "plugins": {
      "mcp-bridge": {
        "base_uri": "/mcp",
        "command": "node",
        "args": [
          "path/to/mcp-server.js"
        ]
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

```yaml title="adc.yaml"
services:
  - name: mcp-bridge-service
    routes:
      - name: mcp-bridge-route
        uris:
          - /mcp/*
        plugins:
          mcp-bridge:
            base_uri: /mcp
            command: node
            args:
              - path/to/mcp-server.js
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
</Tabs>

Connect an MCP client to the SSE endpoint:

```text
http://127.0.0.1:9080/mcp/sse
```

The Plugin sends an `endpoint` SSE event that contains the message
endpoint for the session. MCP clients use that endpoint to send
JSON-RPC messages back to APISIX.
