---
title: mcp-tools-acl
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - MCP
  - ACL
  - mcp-tools-acl
description: This document contains information about the Apache APISIX mcp-tools-acl Plugin, which restricts the MCP tools a client may see and call on a Route served by openapi-to-mcp.
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

The `mcp-tools-acl` Plugin restricts which MCP tools a client may use on a Route that [`openapi-to-mcp`](./openapi-to-mcp.md) serves.

`openapi-to-mcp` turns every operation of an OpenAPI document into a tool, which is rarely what a given client should be given. This Plugin narrows that set per Consumer:

* A `tools/call` for a tool the matched rule does not allow is refused, and the API is never called.
* The same tools are removed from the `tools/list` answer, so a client is not told they exist.

The Plugin runs at priority 539, just below `openapi-to-mcp` (540) and below the authentication Plugins, so the Consumer is already known when a rule is matched.

## Attributes

| Name                 | Type    | Required | Default    | Valid values | Description |
|----------------------|---------|----------|------------|--------------|-------------|
| rules                | array   | True     |            |              | List of rules. The first rule whose `expr` matches is applied; a rule without `expr` always matches. |
| rules[].allow_tools  | array   | False    |            |              | Tool names the rule allows, matched exactly and case-sensitively. When set, every other tool is denied. An empty array denies all tools. |
| rules[].deny_tools   | array   | False    |            |              | Tool names the rule denies, matched exactly and case-sensitively. |
| rules[].rejected_code| integer | False    | `403`      | [200, 599]   | HTTP status code returned when a tool is denied. |
| rules[].rejected_msg | string  | False    |            |              | Message returned in the response body when a tool is denied. |
| rules[].expr         | array   | False    |            |              | [lua-resty-expr](https://github.com/api7/lua-resty-expr) expression selecting the requests the rule applies to. |
| max_resp_body_size   | integer | False    | `67108864` | >= 1         | Largest response body, in bytes, buffered in memory to filter `tools/list`. A larger body is truncated. |

Each rule must set `allow_tools` or `deny_tools`. When both are set, `deny_tools` is checked first.

The Plugin only acts when `openapi-to-mcp` is configured on the same Route and a Consumer has been identified. On any other Route it logs a warning and stands aside, so adding it to a Route that does not serve MCP changes nothing.

## Example usage

The examples below use a Route with the ID `mcp`. An [admin key](../admin-api.md) is required for the Admin API calls:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

### Deny a tool to every Consumer

Create a Consumer and give it a key:

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

Create a Route that serves the Swagger Petstore API as MCP tools, with `deletePet` denied:

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

Call the denied tool:

```shell
curl -i "http://127.0.0.1:9080/mcp" -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "apikey: reader-key" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"deletePet","arguments":{"pathParameters":{"petId":1}}}}'
```

You should receive an `HTTP/1.1 403 Forbidden` response with the following body:

```json
{"message":"deletePet is not allowed"}
```

List the tools:

```shell
curl "http://127.0.0.1:9080/mcp" -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "apikey: reader-key" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

`deletePet` is absent from the result.

### Give each Consumer its own set of tools

Use `expr` to pick a rule per Consumer:

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

`reader` now sees and may call only `getPetById` and `findPetsByStatus`, while `editor` may use every tool except `deletePet`. A Consumer that matches no rule is not restricted.

## Delete Plugin

To remove the Plugin, delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/mcp" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "mcp-tools-acl": null
    }
  }'
```
