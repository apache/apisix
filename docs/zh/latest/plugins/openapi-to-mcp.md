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
| max_response_body_size | integer | 否 | `1048576` | >= 1024 | 读取到工具结果中的上游响应体大小上限（字节）。超出时调用失败并返回 `RESPONSE_TOO_LARGE`，不会把响应缓冲下来。超过 256 KiB 的工具结果以紧凑 JSON 返回，不再缩进。 |
| max_document_size | integer | 否 | `4194304` | >= 1024 | OpenAPI 文档，以及文档内 `http(s)` 形式 `$ref` 拉取的文档的大小上限（字节）。超出上限的文档不会读入 worker，该路由直接报错。 |
| max_expanded_nodes | integer | 否 | `50000` | >= 1000 | 单次 `$ref` 展开在工具输入 Schema 中最多产生的节点数。超出后该次展开的剩余部分降级为通用对象；足够大的正常文档也可能触及此上限。只有 `paths` 会被展开，文档其他部分不计入。 |
| allowed_ref_hosts | array[string] | 否 | | | 文档内 `http(s)` 形式的 `$ref` 除 `openapi_url` 自身所在来源（scheme、主机与端口）外还可以指向的主机。每项为主机名或 `*.example.com` 形式的通配符，可加 `:port`；不带端口时匹配该主机的任意端口。 |
| allowed_origins | array[string] | 否 | | | MCP 请求中允许的 `Origin` 头取值，写成 `scheme://host[:port]`。配置后完全以列表为准；`["*"]` 表示接受任意 origin。不配置时，`Origin` 只有在其主机是路由 `host`/`hosts` 声明的字面量主机（`*.example.com` 这类通配项不算），或它与请求两端都是回环地址时才被接受。不带 `Origin` 头的请求始终放行。 |

调用 API 之前，插件会按生成的输入 Schema 校验工具参数，并按操作声明的参数过滤：文档中未声明的参数会被丢弃，不会发往 API。调用不存在的工具或参数不合法时，返回 `isError` 为 `true` 的结果。校验之前会先填入文档中声明的 `default`，因此同时带有 `required` 和 `default` 的参数或请求体属性可以由客户端省略；客户端显式传入的参数不会被默认值覆盖。

调用工具时，插件根据操作定义构造请求：

* 声明在 Path Item 上的参数适用于该路径下的所有操作；操作中同名且位置相同的参数会覆盖它。
* 查询参数按其 `style` 和 `explode` 序列化，规则见 [OpenAPI Parameter Object](https://spec.openapis.org/oas/v3.0.3#style-values)。使用默认值（`form`，展开）时，`tags: ["a", "b"]` 发送为 `tags=a&tags=b`，而不是 `tags[]=a&tags[]=b`；声明为 `explode: false` 的数组参数发送为 `tags=a,b`。同时支持 `spaceDelimited`、`pipeDelimited` 和 `deepObject`。如果 API 要求方括号形式，需要另外通过改写查询字符串的插件处理。
* 请求体使用操作中声明的媒体类型发送，除非 `headers` 中已设置 `Content-Type`。
* header 参数在插件自身的 `headers` 之前写入，因此工具调用无法覆盖路由添加的凭据；取值中含换行符的 header 会被丢弃。

使用 SSE 传输时，`base_url` 和 `headers` 中的变量在打开事件流的那次请求上解析，解析结果用于该会话的所有消息。`"Authorization": "Bearer ${http_x_api_token}"` 这类配置因此在 SSE 下同样可用：后续的消息请求只携带会话 ID，此时已无从解析变量。解析结果会随会话记录存放在共享字典 `mcp-session` 中直到会话结束，因此调用方以这种方式提供的凭据会在网关内存中最长保留 30 分钟；配置中不含变量时则不存储。

使用 SSE 传输时，会话保存在共享字典 `mcp-session` 中，因此同一会话的事件流请求和消息请求可以由不同的 worker 进程处理。会话只在单个 APISIX 实例内有效：多个实例部署在负载均衡之后时，同一 SSE 会话的请求必须到达同一实例。Streamable HTTP 传输是无状态的，没有这一限制。会话归属于签发它的路由以及该路由上通过认证的 consumer，因此会话 ID 无法在另一条路由上使用。

每条 SSE 事件流最长占用连接 30 分钟，客户端异常断开只有在向其写入失败时才会被发现。对可被不可信客户端访问的 SSE 路由，请配合 [`limit-conn`](limit-conn.md) 使用。

## 安全注意事项

* **带 `Origin` 的请求默认一律拒绝，除非有运维显式配置的依据。** MCP 要求 HTTP 传输校验 `Origin`，否则浏览器页面可以访问只监听 localhost 或位于用户防火墙内的服务并读取响应。`Origin` 不会与同一请求的其他头相比——DNS rebinding 下攻击者掌握域名，`Origin` 和 `Host` 都是他的且彼此一致。校验依据只有三处：`allowed_origins`；路由 `host`/`hosts` 声明的字面量主机；两者都没有时，只接受 origin 与请求两端均为回环地址的情况——攻击者的页面无法拥有这样的 origin。不带 `Origin` 的请求不受影响：非浏览器 MCP 客户端都不发这个头，而它们是多数。 `host`/`hosts` 中的 `*.example.com` 是路由谓词而非 origin 白名单——拿到该域名下任一名字的人都能在上面建页面——因此靠通配匹配到的路由只能通过 `allowed_origins` 接受 origin。
* **OpenAPI 文档是输入，不是可信配置。** 工具名称、描述和 Schema 都来自文档并会被模型读取，文档来源一旦被攻陷，就可以左右使用该路由的 Agent。`openapi_url` 应指向自己可控的来源。
* **`base_url` 不应由客户端可控的变量拼成。** `http://${http_x_backend}` 会让调用方决定工具请求发往何处；请使用固定主机，或网关自身设置的变量。
* **文档内 `http(s)` 形式的 `$ref` 默认只跟随文档自身的 scheme、主机与端口。** 因此从 `127.0.0.1` 提供的文档无法指向同一地址上的其他端口。需要跨来源时用 `allowed_ref_hosts` 显式声明，并避免把内部地址写进去。
* **插件的 `headers` 会附加到文档中的每一个操作上。** 如果其中的凭据并非对所有操作都适用，请用 [`consumer-restriction`](consumer-restriction.md) 等方式限制 consumer 可调用的工具。
* **插件的 `headers` 优先于调用方传入的同名 header**，两者大小写写法不同也一样，因此工具调用无法替换网关附加的凭据。调用方也不能设置决定请求分帧或属于连接本身的 header —— `Transfer-Encoding`、`Content-Length`、`Host`、`Connection`、`Upgrade`、`Expect` 以及其他 hop-by-hop header —— 即使文档把它们声明成了 header 参数。

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
