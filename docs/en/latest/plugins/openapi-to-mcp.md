---
title: openapi-to-mcp
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - MCP
  - OpenAPI
  - openapi-to-mcp
description: This document contains information about the Apache APISIX openapi-to-mcp Plugin, which turns the operations of an OpenAPI document into MCP tools and serves them from the gateway.
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

The `openapi-to-mcp` Plugin exposes an existing HTTP API to [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) clients, such as LLM agents, without changing the API. It fetches the API's OpenAPI document, generates one MCP tool per operation, and answers the MCP protocol itself. When a client calls a tool, the Plugin sends the corresponding HTTP request to the API and returns the response as the tool result.

The MCP server runs inside APISIX. No additional process or service is required.

The Plugin supports:

* The Streamable HTTP transport (stateless) and the HTTP+SSE transport.
* MCP protocol versions `2024-10-07`, `2024-11-05`, `2025-03-26`, `2025-06-18` and `2025-11-25`, negotiated during `initialize`.
* The `initialize`, `ping`, `tools/list` and `tools/call` methods.
* OpenAPI 3.x documents in JSON or YAML. Internal and `http(s)` `$ref` references are resolved. Swagger 2.0 documents are read on a best-effort basis: `in: body` and `in: formData` parameters are not turned into tool inputs.

## Attributes

| Name               | Type    | Required | Default | Valid values                | Description |
|--------------------|---------|----------|---------|-----------------------------|-------------|
| transport          | string  | False    | `sse`   | [`sse`, `streamable_http`]  | MCP transport served on the Route. |
| openapi_url        | string  | True     |         |                             | URL of the OpenAPI document. The document is fetched on the first request and the generated tools are cached for an hour. The response must be an OpenAPI or Swagger document with a `paths` object; anything else is reported as an error on every MCP request. |
| base_url           | string  | True     |         |                             | Base URL of the API the tools call. The path of each operation is appended to it. Supports [APISIX variables](../apisix-variable.md) and [NGINX variables](http://nginx.org/en/docs/varindex.html), for example `http://${http_x_backend}`. |
| headers            | object  | False    |         |                             | Headers added to every request sent to the API. Values support variables, for example `"Authorization": "Bearer ${http_x_api_token}"`. |
| flatten_parameters | boolean | False    | `false` |                             | When `false`, the tool input nests parameters under `pathParameters`, `queryParameters` and `headerParameters`. When `true`, they are placed directly in the input object. |
| max_response_body_size | integer | False | `1048576` | >= 1024 | Maximum size, in bytes, of an upstream response read into a tool result. A larger response fails the call with `RESPONSE_TOO_LARGE` instead of being buffered. A tool result over 256 KiB is returned as compact JSON rather than indented. |
| max_document_size | integer | False | `4194304` | >= 1024 | Maximum size, in bytes, of the OpenAPI document, and of any document an `http(s)` `$ref` pulls in. A larger document fails the Route rather than being read into the worker. |
| allowed_ref_hosts | array[string] | False | | | Hosts an `http(s)` `$ref` inside the document may point at, besides the origin `openapi_url` itself was fetched from. Each entry is a hostname or a `*.example.com` wildcard, optionally followed by `:port`; without a port it matches any port on that host. |
| allowed_origins | array[string] | False | | | `Origin` header values accepted on MCP requests, written as `scheme://host[:port]`. When unset, a request carrying an `Origin` is accepted only from the origin it was addressed to. When set, the list governs on its own -- the Route's own origin is accepted only if it is listed too, which is what keeps the list meaningful where an attacker controls the name the request was sent to. `["*"]` accepts any origin. A request with no `Origin` header is always accepted. |

Tool call arguments are validated against the generated input schema before the API is called, and then filtered to the parameters the operation declares: an argument the document does not mention is dropped rather than sent. A call to an unknown tool, or with invalid arguments, returns a result with `isError` set to `true`. Every `default` declared in the document is filled in before that validation, so a parameter or a body property that is `required` and has a `default` may be omitted by the client; an argument the client does send is never replaced by the default.

When a tool is called, the Plugin builds the request from the operation:

* Parameters declared on the Path Item apply to every operation under it; an operation parameter with the same name and location overrides them.
* Query parameters are serialized according to their `style` and `explode`, as defined by the [OpenAPI Parameter Object](https://spec.openapis.org/oas/v3.0.3#style-values). With the defaults (`form`, exploded), `tags: ["a", "b"]` is sent as `tags=a&tags=b` -- not as `tags[]=a&tags[]=b`, and an array parameter declared `explode: false` is sent as `tags=a,b`. `spaceDelimited`, `pipeDelimited` and `deepObject` are supported. An API that expects the bracket form has to be reached through a Plugin that rewrites the query string.
* A request body is sent with the media type the operation declares, unless `headers` sets `Content-Type`.
* Header parameters are applied before the Plugin's own `headers`, so a tool call cannot replace a credential the route adds, and a header whose value contains a newline is dropped.

For the SSE transport, variables in `base_url` and in `headers` are resolved on the request that opens the stream, and the resolved values are used for every message of that session. This is what makes a configuration such as `"Authorization": "Bearer ${http_x_api_token}"` usable over SSE: the message requests that follow carry only the session id, so there is nothing left to resolve from at that point. Those resolved values are kept with the session record in the `mcp-session` shared dict for the life of the session, so a credential a caller supplied that way lives in gateway memory for up to 30 minutes; a configuration with no variable in it stores nothing.

For the SSE transport, sessions are kept in the `mcp-session` shared dict, so the stream and the message requests of one session may be handled by different worker processes. Sessions are local to one APISIX instance: when several instances run behind a load balancer, the requests of an SSE session must reach the same instance. The Streamable HTTP transport is stateless and has no such requirement. A session belongs to the Route that issued it, and to the consumer authenticated on it, so a session id cannot be used on another Route.

Each SSE stream holds a connection for up to 30 minutes, and a client that disappears without closing the connection is only noticed when a write to it fails. Configure [`limit-conn`](limit-conn.md) on an SSE Route that is reachable by untrusted clients.

## Security considerations

* **A request from another origin is refused by default.** MCP requires an HTTP transport to validate `Origin`, because a page in a browser can otherwise reach a server that only listens on localhost, or one behind the user's firewall, and read the answer back. A request that carries no `Origin` is left alone -- no non-browser client sends one -- and `allowed_origins` names the other origins a Route accepts, or `["*"]` to accept any. This is not by itself a defence against DNS rebinding, where the attacker owns the name and so both `Origin` and `Host` are theirs; a Route that declares `hosts` is not reachable that way at all, because a request carrying another `Host` does not match it.
* **The OpenAPI document is an input, not a trusted configuration.** Tool names, descriptions and schemas come from it and are read by the model, so a document host that is compromised can steer the agents using the Route. Point `openapi_url` at a source you control.
* **`base_url` should not be built from client-controlled variables.** `http://${http_x_backend}` lets the caller choose where the tool call goes; use a fixed host, or a variable the gateway itself sets.
* **An `http(s)` `$ref` is followed only to the document's own scheme, host and port** by default, so a document served from `127.0.0.1` cannot reach another port on that same address. Add `allowed_ref_hosts` to allow more, and keep internal addresses out of that list.
* **The Plugin's `headers` reach every operation in the document.** If the credential they carry is not meant for all of them, restrict which tools a consumer may call with [`consumer-restriction`](consumer-restriction.md) or an equivalent.
* **The Plugin's `headers` win over a header the caller supplies**, whichever case each is spelled in, so a tool call cannot replace a credential the gateway adds. A call also cannot set the headers that frame the request or belong to the connection -- `Transfer-Encoding`, `Content-Length`, `Host`, `Connection`, `Upgrade`, `Expect` and the other hop-by-hop ones -- even where the document declares them as header parameters.

## Example usage

The examples below use a Route with the ID `mcp`. An [admin key](../admin-api.md) is required for the Admin API calls:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

### Serve an API over Streamable HTTP

Create a Route that serves the tools of the Swagger Petstore API:

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

List the tools:

```shell
curl "http://127.0.0.1:9080/mcp" -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

The response is a single SSE event carrying the JSON-RPC result:

```text
event: message
data: {"result":{"tools":[{"name":"updatePet","description":"Update an existing pet by Id", ...}]},"jsonrpc":"2.0","id":1}
```

Call a tool:

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

The tool result carries the status, status text, headers and body the API returned, as JSON text:

```text
event: message
data: {"result":{"content":[{"type":"text","text":"{\n  \"status\": 200,\n  \"statusText\": \"OK\", ..."}]},"jsonrpc":"2.0","id":2}
```

An MCP client connects to `http://127.0.0.1:9080/mcp` using its Streamable HTTP transport.

### Serve an API over SSE

With `transport` set to `sse`, or left unset, a client opens the stream with a `GET` request. The first event tells it where to send its messages:

```shell
curl -N "http://127.0.0.1:9080/mcp"
```

```text
event: endpoint
data: /mcp?sessionId=4c9b0a4e-1bb0-4f4d-9b0b-2f3c3e0f7a51
```

The client then `POST`s each JSON-RPC message to that endpoint, receives `202 Accepted`, and reads the answer from the stream.

### Forward credentials to the API

Pass the caller's token through to the API by reading it from a request header:

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

Other Plugins on the Route keep working. For example, `key-auth` or `limit-count` run before the MCP request is answered, and a request they reject never reaches the tools.

## Delete Plugin

To remove the `openapi-to-mcp` Plugin, delete it from the Route configuration. APISIX reloads the configuration automatically:

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
