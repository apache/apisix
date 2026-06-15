---
title: mcp-bridge
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - mcp-bridge
  - MCP
description: This document contains information about the Apache APISIX mcp-bridge Plugin, which bridges a stdio-based MCP (Model Context Protocol) server to HTTP clients over SSE.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/mcp-bridge" />
</head>

## Description

The `mcp-bridge` Plugin bridges a stdio-based [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) server to HTTP clients. APISIX spawns the MCP server as a subprocess and exposes it over the MCP [SSE transport](https://modelcontextprotocol.io/docs/concepts/transports), so that clients can talk to a local MCP server through the gateway without managing the process themselves.

When a client connects, APISIX starts the configured `command` as a subprocess and relays data between them:

- The subprocess's standard output is forwarded to the client as JSON-RPC messages.
- The subprocess's standard error is forwarded to the client as `notifications/stderr` notifications.
- Messages sent by the client are written to the subprocess's standard input.

:::caution

The `mcp-bridge` Plugin is currently experimental and under active development. Its configuration and behavior may change in future releases.

:::

## Attributes

| Name       | Type            | Required | Default | Description                                                                                                                  |
|------------|-----------------|----------|---------|------------------------------------------------------------------------------------------------------------------------------|
| command    | string          | True     |         | Command used to start the MCP server subprocess, for example `npx`. The command must be available in the `PATH` of the APISIX process. |
| args       | array[string]   | False    |         | List of arguments passed to `command`.                                                                                       |
| base_uri   | string          | False    | ""      | Base path under which the SSE and message endpoints are exposed. It should match the prefix of the Route's `uri`.            |

With a given `base_uri`, the Plugin serves two endpoints:

- `GET <base_uri>/sse`: establishes the SSE stream and advertises the message endpoint to the client.
- `POST <base_uri>/message?sessionId=<id>`: the endpoint to which the client posts JSON-RPC messages.

The Route should therefore be configured with a wildcard `uri` such as `<base_uri>/*` so that both endpoints are matched.

## Example usage

The following example bridges the [filesystem MCP server](https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem) and exposes it under `/mcp`.

Create a Route with the `mcp-bridge` Plugin. The `uri` uses a wildcard so that both `/mcp/sse` and `/mcp/message` are matched, and `base_uri` is set to `/mcp`:

```shell
curl -i "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/mcp/*",
    "plugins": {
      "mcp-bridge": {
        "base_uri": "/mcp",
        "command": "npx",
        "args": [
          "-y",
          "@modelcontextprotocol/server-filesystem",
          "/path/to/serve"
        ]
      }
    }
  }'
```

Connect to the SSE endpoint to establish a session:

```shell
curl -N "http://127.0.0.1:9080/mcp/sse"
```

```text
event: endpoint
data: /mcp/message?sessionId=0d9...e3a
```

The `data` field contains the message endpoint, including the `sessionId` to use for this session. Using that endpoint, send JSON-RPC requests to the MCP server. For example, to list the available tools:

```shell
curl "http://127.0.0.1:9080/mcp/message?sessionId=0d9...e3a" -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

The MCP server's responses are streamed back over the SSE connection opened in the previous step.

## Delete Plugin

To remove the `mcp-bridge` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/mcp/*",
    "plugins": {}
  }'
```
