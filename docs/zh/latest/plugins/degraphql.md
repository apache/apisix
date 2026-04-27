---
title: degraphql
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - degraphql
description: degraphql 插件通过将 GraphQL 查询映射到 HTTP 端点，支持通过标准 HTTP 请求与上游 GraphQL 服务进行通信，简化 API 集成。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/degraphql" />
</head>

## 描述

`degraphql` 插件支持通过将 GraphQL 查询映射到 HTTP 端点，使用普通 HTTP 请求与上游 GraphQL 服务进行通信。

## 属性

| 名称             | 类型           | 必选项 | 描述                                                                                        |
| ---------------- | -------------- | ------ | ------------------------------------------------------------------------------------------- |
| `query`          | string         | 是     | 发送到上游的 GraphQL 查询。                                                                 |
| `operation_name` | string         | 否     | 操作名称，仅在查询中存在多个操作时需要。                                                    |
| `variables`      | array[string]  | 否     | GraphQL 查询中使用的变量名称，从请求体或查询字符串中提取。                                  |

## 示例

以下示例演示了如何针对不同场景配置 `degraphql`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

以下示例使用 [Pokemon GraphQL API](https://graphql-pokemon.js.org/) 作为上游 GraphQL 服务器。

### 转换基本查询

以下示例演示如何转换如下简单 GraphQL 查询：

```graphql
query {
  getAllPokemon {
    key
    color
  }
}
```

按如下方式创建一个带有 `degraphql` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "degraphql-route",
    "methods": ["POST"],
    "uri": "/v8",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "graphqlpokemon.favware.tech": 1
      },
      "scheme": "https",
      "pass_host": "node"
    },
    "plugins": {
      "degraphql": {
        "query": "{\n  getAllPokemon {\n    key\n    color\n  }\n}"
      }
    }
  }'
```

向路由发送请求以验证：

```shell
curl "http://127.0.0.1:9080/v8" -X POST
```

您应该会看到类似以下内容的响应：

```json
{
  "data": {
    "getAllPokemon": [
      { "key": "pokestarsmeargle", "color": "White" },
      { "key": "pokestarufo", "color": "White" },
      { "key": "pokestarufo2", "color": "White" },
      ...
      { "key": "terapagosstellar", "color": "Blue" },
      { "key": "pecharunt", "color": "Purple" }
    ]
  }
}
```

### 转换带变量的查询

以下示例演示如何转换带有变量的 GraphQL 查询：

```graphql
query ($pokemon: PokemonEnum!) {
  getPokemon(
    pokemon: $pokemon
  ) {
    color
    species
  }
}

variables:
{
  "pokemon": "pikachu"
}
```

按如下方式创建一个带有 `degraphql` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "degraphql-route",
    "uri": "/v8",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "graphqlpokemon.favware.tech": 1
      },
      "scheme": "https",
      "pass_host": "node"
    },
    "plugins": {
      "degraphql": {
        "query": "query ($pokemon: PokemonEnum!) {\n  getPokemon(\n    pokemon: $pokemon\n  ) {\n    color\n    species\n  }\n}\n",
        "variables": ["pokemon"]
      }
    }
  }'
```

向路由发送 POST 请求，将变量放在请求体中：

```shell
curl "http://127.0.0.1:9080/v8" -X POST \
  -d '{
    "pokemon": "pikachu"
  }'
```

您应该会看到类似以下内容的响应：

```json
{
  "data": {
    "getPokemon": {
      "color": "Yellow",
      "species": "pikachu"
    }
  }
}
```

您也可以通过 GET 请求的 URL 查询字符串传递变量：

```shell
curl "http://127.0.0.1:9080/v8?pokemon=pikachu"
```

您应该会看到与上述相同的响应。
