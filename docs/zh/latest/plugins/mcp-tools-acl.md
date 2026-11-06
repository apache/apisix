---
title: mcp-tools-acl
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - MCP
  - ACL
  - mcp-tools-acl
description: 本文介绍了 Apache APISIX mcp-tools-acl 插件的相关操作，你可以使用此插件限制客户端在 openapi-to-mcp 提供服务的路由上可以看到和调用的 MCP 工具。
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

`mcp-tools-acl` 插件用于限制客户端在由 [`openapi-to-mcp`](./openapi-to-mcp.md) 提供服务的路由上可以使用哪些 MCP 工具。

`openapi-to-mcp` 会把 OpenAPI 文档中的每一个操作都转换成一个工具，而某个具体的客户端通常不应该拿到全部工具。该插件按消费者收窄这个集合：

* 对匹配规则不允许的工具发起 `tools/call` 时请求被拒绝，后端 API 不会被调用。
* 同样的工具会从 `tools/list` 的响应中移除，客户端不会知道它们的存在。

该插件的优先级为 539，低于 `openapi-to-mcp`（540），也低于各认证插件，因此在匹配规则时消费者已经确定。

## 属性

| 名称                  | 类型    | 必选项 | 默认值      | 有效值       | 描述 |
|-----------------------|---------|--------|-------------|--------------|------|
| rules                 | array   | 是     |             |              | 规则列表。第一个 `expr` 匹配成功的规则生效；未设置 `expr` 的规则总是匹配。 |
| rules[].allow_tools   | array   | 否     |             |              | 允许的工具名称，精确匹配且区分大小写。设置后其他工具全部被拒绝，空数组表示拒绝所有工具。 |
| rules[].deny_tools    | array   | 否     |             |              | 拒绝的工具名称，精确匹配且区分大小写。 |
| rules[].rejected_code | integer | 否     | `403`       | [200, 599]   | 工具被拒绝时返回的 HTTP 状态码。 |
| rules[].rejected_msg  | string  | 否     |             |              | 工具被拒绝时响应体中返回的消息。 |
| rules[].expr          | array   | 否     |             |              | [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式，用于筛选该规则适用的请求。 |
| max_resp_body_size    | integer | 否     | `67108864`  | >= 1         | 为过滤 `tools/list` 而缓存在内存中的响应体的最大字节数，超出部分会被截断。 |

每条规则必须设置 `allow_tools` 或 `deny_tools`。两者同时设置时先判断 `deny_tools`。

只有当同一条路由上配置了 `openapi-to-mcp` 并且已经识别出消费者时，该插件才会生效。在其他路由上它只会记录一条警告日志并放行，因此把它配置到不提供 MCP 服务的路由上不会产生任何影响。

## 使用示例

以下示例使用 ID 为 `mcp` 的路由。调用 Admin API 需要 [admin key](../admin-api.md)：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

### 对所有消费者拒绝某个工具

创建一个消费者并为其配置密钥：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "reader",
    "plugins": {
      "key-auth": {
        "key": "reader-key"
      }
    }
  }'
```

创建一条把 Swagger Petstore API 作为 MCP 工具提供服务的路由，并拒绝 `deletePet`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "mcp",
    "uri": "/mcp",
    "plugins": {
      "key-auth": {},
      "openapi-to-mcp": {
        "transport": "streamable_http",
        "openapi_url": "https://petstore3.swagger.io/api/v3/openapi.json",
        "base_url": "https://petstore3.swagger.io/api/v3"
      },
      "mcp-tools-acl": {
        "rules": [
          {
            "deny_tools": ["deletePet"],
            "rejected_code": 403,
            "rejected_msg": "deletePet is not allowed"
          }
        ]
      }
    }
  }'
```

调用被拒绝的工具：

```shell
curl -i "http://127.0.0.1:9080/mcp" -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "apikey: reader-key" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"deletePet","arguments":{"pathParameters":{"petId":1}}}}'
```

将会收到 `HTTP/1.1 403 Forbidden` 响应，响应体如下：

```json
{"message":"deletePet is not allowed"}
```

列出工具：

```shell
curl "http://127.0.0.1:9080/mcp" -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "apikey: reader-key" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

结果中不会出现 `deletePet`。

### 为每个消费者配置各自的工具集合

使用 `expr` 为不同消费者选择不同的规则：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/mcp" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "mcp-tools-acl": {
        "rules": [
          {
            "expr": [["consumer_name", "==", "reader"]],
            "allow_tools": ["getPetById", "findPetsByStatus"]
          },
          {
            "expr": [["consumer_name", "==", "editor"]],
            "deny_tools": ["deletePet"]
          }
        ]
      }
    }
  }'
```

此时 `reader` 只能看到并调用 `getPetById` 和 `findPetsByStatus`，而 `editor` 除 `deletePet` 外可以使用所有工具。没有匹配到任何规则的消费者不受限制。

## 删除插件

当你需要禁用该插件时，可以从插件配置中删除对应的 JSON 配置，APISIX 会自动重新加载，无需重启服务：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/mcp" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "mcp-tools-acl": null
    }
  }'
```
