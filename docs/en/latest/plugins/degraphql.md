---
title: degraphql
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Degraphql
description: This document contains information about the Apache APISIX degraphql Plugin.
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

The `degraphql` Plugin is used to support decoding RESTful API to GraphQL.

## Attributes

| Name           | Type   | Required | Description                                                                                  |
| -------------- | ------ | -------- | -------------------------------------------------------------------------------------------- |
| query          | string | True     | The GraphQL query sent to the upstream                                                       |
| operation_name | string | False    | The name of the operation, is only required if multiple operations are present in the query. |
| variables      | array  | False    | The variables used in the GraphQL query                                                      |

## Example usage

### Start GraphQL server

We use docker to deploy a [GraphQL server demo](https://github.com/npalm/graphql-java-demo) as the backend.

```bash
docker run -d --name grapql-demo -p 8080:8080 npalm/graphql-java-demo
```

After starting the server, the following endpoints are now available:

- http://localhost:8080/graphiql - GraphQL IDE - GrahphiQL
- http://localhost:8080/playground - GraphQL IDE - Prisma GraphQL Client
- http://localhost:8080/altair - GraphQL IDE - Altair GraphQL Client
- http://localhost:8080/ - A simple reacter
- ws://localhost:8080/subscriptions

### Enable Plugin

#### Query list

If we have a GraphQL query like this:

```graphql
query {
  persons {
    id
    name
  }
}
```

We can execute it on `http://localhost:8080/playground`, and get the data as below:

```json
{
  "data": {
    "persons": [
      {
        "id": "7",
        "name": "Niek"
      },
      {
        "id": "8",
        "name": "Josh"
      },
      ......
    ]
  }
}
```

Now we can use RESTful API to query the same data that is proxy by APISIX.

First, we need to create a route in APISIX, and enable the degreaph plugin on the route, we need to define the GraphQL query in the plugin's config.

```bash
curl --location --request PUT 'http://localhost:9180/apisix/admin/routes/1' \
--header 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
--header 'Content-Type: application/json' \
--data-raw '{
    "uri": "/graphql",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    },
    "plugins": {
        "degraphql": {
            "query": "{\n  persons {\n    id\n    name\n  }\n}\n"
        }
    }
}'
```

We convert the GraphQL query

```graphql
{
  persons {
    id
    name
  }
}
```

to JSON string `"{\n  persons {\n    id\n    name\n  }\n}\n"`, and put it in the plugin's configuration.

Then we can query the data by RESTful API:

```bash
curl --location --request POST 'http://localhost:9080/graphql'
```

and get the result:

```json
{
  "data": {
    "persons": [
      {
        "id": "7",
        "name": "Niek"
      },
      {
        "id": "8",
        "name": "Josh"
      },
      ......
    ]
  }
}
```

#### Query with variables

If we have a GraphQL query like this:

```graphql
query($name: String!, $githubAccount: String!) {
  persons(filter: { name: $name, githubAccount: $githubAccount }) {
    id
    name
    blog
    githubAccount
    talks {
      id
      title
    }
  }
}

variables:
{
  "name": "Niek",
  "githubAccount": "npalm"
}
```

we can execute it on `http://localhost:8080/playground`, and get the data as below:

```json
{
  "data": {
    "persons": [
      {
        "id": "7",
        "name": "Niek",
        "blog": "https://040code.github.io",
        "githubAccount": "npalm",
        "talks": [
          {
            "id": "19",
            "title": "GraphQL - The Next API Language"
          },
          {
            "id": "20",
            "title": "Immutable Infrastructure"
          }
        ]
      }
    ]
  }
}
```

We convert the GraphQL query to JSON string like `"query($name: String!, $githubAccount: String!) {\n  persons(filter: { name: $name, githubAccount: $githubAccount }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}"`, so we create a route like this:

```bash
curl --location --request PUT 'http://localhost:9180/apisix/admin/routes/1' \
--header 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
--header 'Content-Type: application/json' \
--data-raw '{
    "uri": "/graphql",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    },
    "plugins": {
        "degraphql": {
            "query": "query($name: String!, $githubAccount: String!) {\n  persons(filter: { name: $name, githubAccount: $githubAccount }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}",
            "variables": [
                "name",
                "githubAccount"
            ]
        }
    }
}'
```

We define the `variables` in the plugin's config, and the `variables` is an array, which contains the variables' name in the GraphQL query, so that we can pass the query variables by RESTful API.

Query the data by RESTful API that proxy by APISIX:

```bash
curl --location --request POST 'http://localhost:9080/graphql' \
--header 'Content-Type: application/json' \
--data-raw '{
    "name": "Niek",
    "githubAccount": "npalm"
}'
```

and get the result:

```json
{
  "data": {
    "persons": [
      {
        "id": "7",
        "name": "Niek",
        "blog": "https://040code.github.io",
        "githubAccount": "npalm",
        "talks": [
          {
            "id": "19",
            "title": "GraphQL - The Next API Language"
          },
          {
            "id": "20",
            "title": "Immutable Infrastructure"
          }
        ]
      }
    ]
  }
}
```

which is the same as the result of the GraphQL query.

It's also possible to get the same result via GET request:

```bash
curl 'http://localhost:9080/graphql?name=Niek&githubAccount=npalm'
```

```json
{
  "data": {
    "persons": [
      {
        "id": "7",
        "name": "Niek",
        "blog": "https://040code.github.io",
        "githubAccount": "npalm",
        "talks": [
          {
            "id": "19",
            "title": "GraphQL - The Next API Language"
          },
          {
            "id": "20",
            "title": "Immutable Infrastructure"
          }
        ]
      }
    ]
  }
}
```

In the GET request, the variables are passed in the query string.

## Delete Plugin

To remove the `degraphql` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "methods": ["GET"],
  "uri": "/graphql",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:8080": 1
    }
  }
}'
```
