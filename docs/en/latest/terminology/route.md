---
title: Route
keywords:
  - API Gateway
  - Apache APISIX
  - Route
description: This article describes the concept of Route and how to use it.
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

Routes match the client's request based on defined rules, load and execute the corresponding [plugins](./plugin.md), and forwards the request to the specified [Upstream](./upstream.md).

A Route mainly consists of three parts:

1. Matching rules
2. Plugin configuration (current-limit, rate-limit)
3. Upstream information

The image below shows some example Route rules. Note that the values are of the same color if they are identical.

![routes-example](../../../assets/images/routes-example.png)

All the parameters are configured directly in the Route. It is easy to set up, and each Route has a high degree of freedom.

When Routes have repetitive configurations (say, enabling the same plugin configuration or Upstream information), to update it, we need to traverse all the Routes and modify them. This adds a lot of complexity, making it difficult to maintain.

These shortcomings are independently abstracted in APISIX by two concepts: [Service](service.md) and [Upstream](upstream.md).

## Example

The Route example shown below proxies the request with the URL `/get` to the Upstream service with the address `httpbin.org:80`.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/get",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

## Route Matching Conditions

APISIX uses `lua-resty-radixtree` as a route dispatching library. [lua-resty-radixtree](https://github.com/api7/lua-resty-radixtree) is an adaptive radix tree that is implemented in Lua for OpenResty and it is based on FFI for [rax](https://github.com/antirez/rax).

There are several ways APISIX matches routes against incoming requests, let's take a look at a few examples and have an intuitive understanding.

### Prefix matching

```
/blog/bar*
```

It will match the path with the prefix `/blog/bar`. For example, `/blog/bar/a`,
`/blog/bar/b`, `/blog/bar/c/d/e`, `/blog/bar` etc.

### Full match

```
/blog/foo
```

It will only match the full path `/blog/foo`.

Full match has a higher priority than deep prefix matching.

If a route is configured to match following URIs:

```
/blog/foo/*
/blog/foo/a/*
/blog/foo/c/*
/blog/foo/bar
```

The following table shows URIs being matched to their corresponding rules:

| Path            | Match result    |
|-----------------|-----------------|
| /blog/foo/bar   | `/blog/foo/bar` |
| /blog/foo/a/b/c | `/blog/foo/a/*` |
| /blog/foo/c/d   | `/blog/foo/c/*` |
| /blog/foo/gloo  | `/blog/foo/*`   |
| /blog/bar       | no match        |

### Different Routes Have the Same `uri`

When different routes have the same `uri`, you can set the priority field of the route to determine which route to match first, or add other matching rules to distinguish different routes.

Note: In the matching rules, the `priority` field takes precedence over other rules except `uri`.

1. Different routes have the same `uri` but different `priority` field

Create two routes with different `priority` values ​​(the larger the value, the higher the priority).

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    },
    "priority": 3,
    "uri": "/get"
  }'
```

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/2 -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "upstream": {
        "nodes": {
            "mock.api7.ai:443": 1
        },
        "scheme": "https",
        "pass_host": "node",
      "type": "roundrobin"
    },
    "priority": 2,
    "uri": "/get"
  }'
```

Send a request to with `/get` as the URI:

```shell
curl http://127.0.0.1:9080/get -i
```

All requests will only `httpbin.org` because it has a priority of 3 while the other route has a priority of 2.

2. Different routes have the same `uri` but different matching conditions

To understand this, look at the example of setting host matching rules:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    },
    "hosts": ["localhost.com"],
    "uri": "/get"
  }'
```

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/2 -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "upstream": {
      "nodes": {
        "mock.api7.ai:443": 1
      },
      "scheme": "https",
      "pass_host": "node",
      "type": "roundrobin"
    },
    "hosts": ["test.com"],
    "uri": "/get"
  }'
```

Send a request with `/get` as the URI and `'host: localhost.com'`:

```shell
curl http://127.0.0.1:9080/get -H 'host: localhost.com'
```

This should match the first route  and the request should hit httpbin.org. You should see a response similar to the following:

```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "localhost.com",
    "User-Agent": "curl/8.1.2",
    "X-Amzn-Trace-Id": "Root=1-6551bdd6-5dc45fd57769cd6b296062b7",
    "X-Forwarded-Host": "localhost.com"
  },
  "origin": "127.0.0.1, 163.47.148.91",
  "url": "http://localhost.com/get"
}
```

Send a request with `/get` as the URI and `'host: test.com'`:

```shell
curl http://127.0.0.1:9080/get -H 'host: test.com'
```

This should match the second route and the request should hit mock.api7.ai. You should see a response similar to the following:

```text
API7.ai, the creator of Apache APISIX, delivers a cloud-native API Gateway solution for the Enterprise, to help you maximize the value of APIs.
```

### Parameter match

When `radixtree_uri_with_parameter` is used, we can match routes with parameters.

For example, with configuration:

```yaml
apisix:
    router:
        http: 'radixtree_uri_with_parameter'
```

Routes having URIs set like `/blog/:name` will match `/blog/dog`, `/blog/cat`, etc.

For more details, see https://github.com/api7/lua-resty-radixtree/#parameters-in-path.

### Route Filtering based on built-in variables

APISIX provides a variety of [built-in variables](https://docs.api7.ai/apisix/reference/built-in-variables) that can be used to filter routes based on certain criteria. Here is an example on filtering routes by built-in variables:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/get",
    "vars": [
      ["http_host", "==", "iresty.com"],
      ["arg_name", "==", "json"]
    ],
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

This route will require the request header `host` equal `iresty.com`, and the `name` query parameter equal to `json`. Like so:

```shell
curl "http://127.0.0.1:9080/get?name=json" -H 'host: iresty.com'
```

You should see a response similar to the following:

```json
{
  "args": {
    "name": "json"
  },
  "headers": {
    "Accept": "*/*",
    "Host": "iresty.com",
    "User-Agent": "curl/8.1.2",
    "X-Amzn-Trace-Id": "Root=1-6551c21e-7d4f336f69dad7e94f70f5c0",
    "X-Forwarded-Host": "iresty.com"
  },
  "origin": "127.0.0.1, 163.47.148.91",
  "url": "http://iresty.com/get?name=json"
}
```

### Filter route by GraphQL attributes

APISIX supports filtering routes by some attributes of GraphQL. Currently, the following are supported:

* graphql_operation
* graphql_name
* graphql_root_fields

For instance, with GraphQL like this:

```graphql
query getRepo {
    owner {
        name
    }
    repo {
        created
    }
}
```

Where

* The `graphql_operation` is `query`
* The `graphql_name` is `getRepo`,
* The `graphql_root_fields` is `["owner", "repo"]`

We can filter such route with:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "methods": ["POST", "GET"],
    "uri": "/graphql",
    "vars": [
      ["graphql_operation", "==", "query"],
      ["graphql_name", "==", "getRepo"],
      ["graphql_root_fields", "has", "owner"]
    ],
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

We can verify GraphQL matches in the following three ways:

1. GraphQL query strings

```shell
curl -H 'content-type: application/graphql' -X POST http://127.0.0.1:9080/graphql -d '
query getRepo {
    owner {
        name
    }
    repo {
        created
    }
}'
```

2. JSON format

```shell
curl -H 'content-type: application/json' -X POST \
http://127.0.0.1:9080/graphql --data '{"query": "query getRepo { owner {name } repo {created}}"}'
```

3. Try `GET` request match

```shell
curl -H 'content-type: application/graphql' -X GET \
"http://127.0.0.1:9080/graphql?query=query getRepo { owner {name } repo {created}}" -g
```

To prevent spending too much time reading invalid GraphQL request body, we only read the first 1 MiB
data from the request body. This limitation is configured via:

```yaml
graphql:
  max_size: 1048576

```

If you need to pass a GraphQL body which is larger than the limitation, you can increase the value in `conf/config.yaml`.

## Configuration

For specific options of Route, please refer to the [Admin API](../admin-api.md#route).
