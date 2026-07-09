---
title: degraphql
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - degraphql
description: The degraphql Plugin enables communication with upstream GraphQL services through standard HTTP requests by mapping GraphQL queries to HTTP endpoints, simplifying API integration.
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

## Description

The `degraphql` Plugin supports communicating with upstream GraphQL services over regular HTTP requests by mapping GraphQL queries to HTTP endpoints.

## Attributes

| Name             | Type         | Required | Description                                                                                        |
| ---------------- | ------------ | -------- | -------------------------------------------------------------------------------------------------- |
| `query`          | string       | True     | The GraphQL query sent to the Upstream.                                                            |
| `operation_name` | string       | False    | The name of the operation, only required if multiple operations are present in the query.          |
| `variables`      | array[string]| False    | The names of variables used in the GraphQL query, extracted from the request body or query string. |

## Examples

The examples below demonstrate how you can configure `degraphql` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

The examples below use [Pokemon GraphQL API](https://graphql-pokemon.js.org/) as the upstream GraphQL server.

### Transform a Basic Query

The following example demonstrates how to transform a simple GraphQL query:

```graphql
query {
  getAllPokemon {
    key
    color
  }
}
```

Create a Route with the `degraphql` Plugin as follows:

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

Send a request to the Route to verify:

```shell
curl "http://127.0.0.1:9080/v8" -X POST
```

You should see a response similar to the following:

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

### Transform a Query with Variables

The following example demonstrates how to transform a GraphQL query that uses a variable:

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

Create a Route with the `degraphql` Plugin as follows:

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

Send a POST request to the Route with the variable in the request body:

```shell
curl "http://127.0.0.1:9080/v8" -X POST \
  -d '{
    "pokemon": "pikachu"
  }'
```

You should see a response similar to the following:

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

Alternatively, you can also pass the variable in the URL query string of a GET request:

```shell
curl "http://127.0.0.1:9080/v8?pokemon=pikachu"
```

You should see the same response as the previous.
