---
title: mcp-bridge
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - mcp-bridge
  - MCP
description: mcp-bridge 插件用于通过 HTTP SSE 端点暴露基于 stdio 的 MCP 服务器。
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

## 描述

`mcp-bridge` 插件用于通过 HTTP Server-Sent Events（SSE）端点暴露基于 stdio 的 Model Context Protocol（MCP）服务器。当客户端连接到 SSE 端点时，APISIX 会启动配置的 MCP 服务器进程，通过 stdin 将客户端消息转发给该进程，并将 MCP 响应流式返回给客户端。

如果路由配置了 `base_uri: /mcp`，该插件会暴露以下端点：

- `GET /mcp/sse`：MCP 客户端使用的 SSE 端点。
- `POST /mcp/message?sessionId=<session-id>`：用于向 MCP 会话发送客户端消息的端点。

请仅配置你信任的命令。配置的进程会运行在 APISIX 所在主机上，并由处理 MCP 会话的 APISIX worker 管理。

## 插件属性

| 名称 | 类型 | 必选项 | 默认值 | 描述 |
| --- | --- | --- | --- | --- |
| `base_uri` | string | 否 | `""` | 生成 MCP SSE 和消息端点时使用的 URI 前缀。 |
| `command` | string | 是 | | 用于启动基于 stdio 的 MCP 服务器的命令。 |
| `args` | array[string] | 否 | | 传递给 `command` 的参数。 |

## 使用示例

以下示例演示了如何通过 APISIX 暴露一个基于 stdio 的 MCP 服务器。

:::note

你可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量中：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 暴露 MCP 服务器

创建一个配置了 `mcp-bridge` 插件的路由：

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

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
</Tabs>

将 MCP 客户端连接到 SSE 端点：

```text
http://127.0.0.1:9080/mcp/sse
```

插件会发送一个 `endpoint` SSE 事件，该事件包含当前会话的消息端点。MCP 客户端使用该端点将 JSON-RPC 消息发送回 APISIX。
