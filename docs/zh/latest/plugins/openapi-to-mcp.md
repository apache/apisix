---
title: openapi-to-mcp
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - MCP
  - OpenAPI
  - openapi-to-mcp
description: openapi-to-mcp 插件将 OpenAPI 文档中的每个操作转换为 MCP 工具，并直接由网关提供 MCP 服务。
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

## 描述

`openapi-to-mcp` 插件无需修改已有的 HTTP API，即可将其提供给 [Model Context Protocol](https://modelcontextprotocol.io/)（MCP）客户端（例如 LLM Agent）使用。插件会获取 API 的 OpenAPI 文档，为每个操作生成一个 MCP 工具，并由插件自身应答 MCP 协议。客户端调用工具时，插件向 API 发送对应的 HTTP 请求，并将响应作为工具结果返回。

MCP 服务运行在 APISIX 内部，不需要额外的进程或服务。

插件支持：

* Streamable HTTP 传输（无状态）和 HTTP+SSE 传输。
* MCP 协议版本 `2024-10-07`、`2024-11-05`、`2025-03-26`、`2025-06-18` 和 `2025-11-25`，在 `initialize` 时协商。
* `initialize`、`ping`、`tools/list` 和 `tools/call` 方法。
* JSON 或 YAML 格式的 OpenAPI 3.x 文档，支持解析内部引用和 `http(s)` 形式的 `$ref`。Swagger 2.0 文档尽力兼容：`in: body` 和 `in: formData` 参数不会转换为工具输入。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| transport | string | 否 | `sse` | [`sse`, `streamable_http`] | 路由上提供的 MCP 传输方式。 |
| openapi_url | string | 是 | | | OpenAPI 文档的 URL。文档在首次请求时获取，生成的工具缓存一小时。返回内容必须是带 `paths` 对象的 OpenAPI 或 Swagger 文档，否则每次 MCP 请求都会返回错误。 |
| base_url | string | 是 | | | 工具调用的 API 基础地址，每个操作的路径拼接在其后。支持 [APISIX 变量](../apisix-variable.md) 和 [NGINX 变量](http://nginx.org/en/docs/varindex.html)，例如 `http://${http_x_backend}`。 |
| headers | object | 否 | | | 发往 API 的每个请求都会携带的请求头。值支持变量，例如 `"Authorization": "Bearer ${http_x_api_token}"`。 |
| flatten_parameters | boolean | 否 | `false` | | 为 `false` 时，工具输入中的参数分别嵌套在 `pathParameters`、`queryParameters` 和 `headerParameters` 下；为 `true` 时，参数直接放在输入对象的顶层。 |
| allowed_hosts | array | 否 | | | 允许 `base_url` 解析到的主机列表。每一项是精确的主机名（如 `api.example.com`），或匹配一级及以上前缀标签的 `*.example.com` 通配符。解析后的 `base_url` 主机不在列表中时，请求返回 HTTP 400。 |

调用 API 之前，插件会按生成的输入 Schema 校验工具参数。调用不存在的工具或参数不合法时，返回 `isError` 为 `true` 的结果。校验之前会先填入文档中声明的 `default`，因此同时带有 `required` 和 `default` 的参数或请求体属性可以由客户端省略；客户端显式传入的参数不会被默认值覆盖。

调用工具时，插件根据操作定义构造请求：

* 声明在 Path Item 上的参数适用于该路径下的所有操作；操作中同名且位置相同的参数会覆盖它。
* 查询参数按其 `style` 和 `explode` 序列化，规则见 [OpenAPI Parameter Object](https://spec.openapis.org/oas/v3.0.3#style-values)。使用默认值（`form`，展开）时，`tags: ["a", "b"]` 发送为 `tags=a&tags=b`，而不是 `tags[]=a&tags[]=b`；声明为 `explode: false` 的数组参数发送为 `tags=a,b`。同时支持 `spaceDelimited`、`pipeDelimited` 和 `deepObject`。如果 API 要求方括号形式，需要另外通过改写查询字符串的插件处理。
* 请求体使用操作中声明的媒体类型发送，除非 `headers` 中已设置 `Content-Type`。

当 `base_url` 由变量拼接时，建议配置 `allowed_hosts`：不配置时，请求解析出什么主机就会调用什么主机；配置后，会在获取文档和调用 API 之前先校验主机，并拒绝非 `http`/`https` 协议的地址。由于解析后的 `base_url` 可能包含来自请求的内容，拒绝信息中不会回显 URL 或主机名。

当文档把某个操作的成功响应描述为 JSON 对象时，生成的工具会以 `outputSchema` 公布该 Schema。响应按 `200`、`201`、其它明确的 `2xx`、`2XX` 的顺序选取；只有媒体类型为 `application/json` 且为带属性的对象才会被采用，因此数组、`default` 响应以及文档中未合并的组合（如 `allOf`）不会公布 Schema。

调用这类工具时，API 的响应体会作为 `structuredContent` 返回，文本块中也是同一份响应体。当响应无法满足该 Schema（状态码不在 `2xx`、响应体不是 JSON 对象，或校验不通过）时，结果仍为 `{status, statusText, headers, data}` 信封，并将 `isError` 置为 `true`——MCP 允许错误结果不携带结构化内容。未公布 `outputSchema` 的工具则始终返回该信封，与状态码无关。

使用 SSE 传输时，`base_url` 和 `headers` 中的变量在打开事件流的那次请求上解析，解析结果用于该会话的所有消息。`"Authorization": "Bearer ${http_x_api_token}"` 这类配置因此在 SSE 下同样可用：后续的消息请求只携带会话 ID，此时已无从解析变量。

使用 SSE 传输时，会话保存在共享字典 `mcp-session` 中，因此同一会话的事件流请求和消息请求可以由不同的 worker 进程处理。会话只在单个 APISIX 实例内有效：多个实例部署在负载均衡之后时，同一 SSE 会话的请求必须到达同一实例。Streamable HTTP 传输是无状态的，没有这一限制。

## 使用示例

以下示例使用 ID 为 `mcp` 的路由。调用 Admin API 需要 [admin key](../admin-api.md)：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

### 通过 Streamable HTTP 提供 API

创建一个路由，提供 Swagger Petstore API 的工具：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mcp",
    "uri": "/mcp",
    "plugins": {
      "openapi-to-mcp": {
        "transport": "streamable_http",
        "openapi_url": "https://petstore3.swagger.io/api/v3/openapi.json",
        "base_url": "https://petstore3.swagger.io/api/v3"
      }
    }
  }'
```

列出工具：

```shell
curl "http://127.0.0.1:9080/mcp" -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

响应是一个携带 JSON-RPC 结果的 SSE 事件：

```text
event: message
data: {"result":{"tools":[{"name":"updatePet","description":"Update an existing pet by Id", ...}]},"jsonrpc":"2.0","id":1}
```

调用工具：

```shell
curl "http://127.0.0.1:9080/mcp" -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "findPetsByStatus",
      "arguments": { "queryParameters": { "status": "sold" } }
    }
  }'
```

工具结果以 JSON 文本的形式包含 API 返回的状态码、状态文本、响应头和响应体：

```text
event: message
data: {"result":{"content":[{"type":"text","text":"{\n  \"status\": 200,\n  \"statusText\": \"OK\", ..."}]},"jsonrpc":"2.0","id":2}
```

MCP 客户端使用其 Streamable HTTP 传输连接 `http://127.0.0.1:9080/mcp` 即可。

### 通过 SSE 提供 API

`transport` 设置为 `sse` 或不设置时，客户端通过 `GET` 请求建立事件流。第一个事件告诉客户端消息应发往哪里：

```shell
curl -N "http://127.0.0.1:9080/mcp"
```

```text
event: endpoint
data: /mcp?sessionId=4c9b0a4e-1bb0-4f4d-9b0b-2f3c3e0f7a51
```

之后客户端将每条 JSON-RPC 消息 `POST` 到该地址，收到 `202 Accepted`，并从事件流中读取应答。

### 将凭证透传给 API

从请求头中读取调用方的令牌并透传给 API：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mcp",
    "uri": "/mcp",
    "plugins": {
      "openapi-to-mcp": {
        "transport": "streamable_http",
        "openapi_url": "https://petstore3.swagger.io/api/v3/openapi.json",
        "base_url": "https://petstore3.swagger.io/api/v3",
        "headers": {
          "Authorization": "Bearer ${http_x_api_token}"
        }
      }
    }
  }'
```

路由上的其他插件照常生效。例如 `key-auth` 或 `limit-count` 会在 MCP 请求被应答之前执行，被它们拒绝的请求不会到达工具。

## 删除插件

如需删除 `openapi-to-mcp` 插件，从路由配置中移除即可，APISIX 会自动重新加载配置：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mcp",
    "uri": "/mcp",
    "plugins": {},
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1980": 1
      }
    }
  }'
```
