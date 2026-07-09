---
title: mcp-bridge
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - MCP Bridge
  - mcp-bridge
description: This document contains information about the Apache APISIX mcp-bridge Plugin, which bridges an SSE/HTTP client to a stdio-based MCP server process.
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

The `mcp-bridge` Plugin bridges an HTTP client speaking the [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) over SSE to a stdio-based MCP server. APISIX spawns the configured command as a backend process and relays messages between the SSE connection and the process's standard input and output.

:::warning

The `mcp-bridge` Plugin is deprecated and will be removed in a future release. We recommend not using it for new deployments.

:::

## Attributes

| Name     | Type            | Required | Default | Description                                                    |
|----------|-----------------|----------|---------|----------------------------------------------------------------|
| command  | string          | True     |         | Command used to launch the MCP server process, e.g. `npx`.     |
| args     | array[string]   | False    |         | Arguments passed to the command.                               |
| base_uri | string          | False    | ""      | Base URI used to build the SSE and message endpoint paths.     |

## Example usage

Create a Route with the `mcp-bridge` Plugin, pointing `command` and `args` at the MCP server you want to expose:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mcp-route",
    "uri": "/mcp/*",
    "plugins": {
      "mcp-bridge": {
        "base_uri": "/mcp",
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/"]
      }
    }
  }'
```

An MCP client can then connect to the SSE endpoint at `/mcp/sse` and exchange messages through `/mcp/message`.
