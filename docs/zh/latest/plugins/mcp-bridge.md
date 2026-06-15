---
title: mcp-bridge
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - mcp-bridge
  - MCP
description: 本文档包含有关 Apache APISIX mcp-bridge 插件的信息，该插件通过 SSE 将基于 stdio 的 MCP（Model Context Protocol）服务器桥接给 HTTP 客户端。
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

## 描述

`mcp-bridge` 插件将基于 stdio 的 [MCP（Model Context Protocol）](https://modelcontextprotocol.io/) 服务器桥接给 HTTP 客户端。APISIX 会将 MCP 服务器作为子进程启动，并通过 MCP 的 [SSE 传输](https://modelcontextprotocol.io/docs/concepts/transports)对外暴露，使客户端无需自行管理进程，即可通过网关与本地 MCP 服务器通信。

当客户端连接时，APISIX 会以子进程方式启动所配置的 `command`，并在两者之间转发数据：

- 子进程的标准输出会作为 JSON-RPC 消息转发给客户端。
- 子进程的标准错误会作为 `notifications/stderr` 通知转发给客户端。
- 客户端发送的消息会写入子进程的标准输入。

:::caution

`mcp-bridge` 插件目前处于实验阶段，仍在积极开发中。其配置和行为在未来版本中可能会发生变化。

:::

## 属性

| 名称       | 类型            | 必选项 | 默认值 | 描述                                                                                                       |
|------------|-----------------|--------|--------|----------------------------------------------------------------------------------------------------------|
| command    | string          | 是     |        | 用于启动 MCP 服务器子进程的命令，例如 `npx`。该命令必须位于 APISIX 进程的 `PATH` 中。                       |
| args       | array[string]   | 否     |        | 传递给 `command` 的参数列表。                                                                              |
| base_uri   | string          | 否     | ""     | 暴露 SSE 与 message 端点的基础路径，应与路由 `uri` 的前缀保持一致。                                        |

对于给定的 `base_uri`，插件会提供两个端点：

- `GET <base_uri>/sse`：建立 SSE 流，并向客户端通告 message 端点。
- `POST <base_uri>/message?sessionId=<id>`：客户端用于发送 JSON-RPC 消息的端点。

因此，路由的 `uri` 应配置为通配形式（例如 `<base_uri>/*`），以便同时匹配上述两个端点。

## 使用示例

以下示例桥接 [filesystem MCP 服务器](https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem)，并将其暴露在 `/mcp` 路径下。

创建一个启用 `mcp-bridge` 插件的路由。`uri` 使用通配符以同时匹配 `/mcp/sse` 与 `/mcp/message`，并将 `base_uri` 设置为 `/mcp`：

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

连接 SSE 端点以建立会话：

```shell
curl -N "http://127.0.0.1:9080/mcp/sse"
```

```text
event: endpoint
data: /mcp/message?sessionId=0d9...e3a
```

`data` 字段中包含 message 端点，其中携带了本次会话使用的 `sessionId`。使用该端点向 MCP 服务器发送 JSON-RPC 请求。例如，列出可用的工具：

```shell
curl "http://127.0.0.1:9080/mcp/message?sessionId=0d9...e3a" -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

MCP 服务器的响应会通过上一步建立的 SSE 连接以流的形式返回。

## 删除插件

当你需要删除 `mcp-bridge` 插件时，可以从插件配置中删除对应的 JSON 配置。APISIX 会自动重新加载，无需重启即可生效。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/mcp/*",
    "plugins": {}
  }'
```
