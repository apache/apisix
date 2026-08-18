---
title: graphql-limit-count
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - graphql-limit-count
  - Rate Limiting
  - GraphQL
description: The graphql-limit-count Plugin limits the rate of GraphQL requests based on the query AST depth within a given time window, using the same counting mechanism as the limit-count Plugin.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/graphql-limit-count" />
</head>

## Description

The `graphql-limit-count` Plugin limits the rate of GraphQL requests using a fixed window algorithm. Unlike [limit-count](./limit-count.md), which counts each request as a cost of 1, this Plugin charges the quota by how expensive the query is.

`cost_strategy` selects how that cost is computed:

- `depth` (default) uses the **depth of the GraphQL query AST**, so deeply nested queries are charged more.
- `complexity` and `node_quantifier` charge by **how much data the query asks for**, which depth cannot see: `users(first: 10000)` and `users(first: 1)` have the same depth. Both read per field weights from the Service's [GraphQL cost decorations](#graphql-cost-decorations) and need the upstream schema, which the Plugin fetches by introspection.

Only `POST` requests are supported. The Plugin accepts two content types:

- `application/json`: request body must contain a `query` field with the GraphQL query string.
- `application/graphql`: request body is the raw GraphQL query starting with `query`.

You may see the following rate limiting headers in the response:

- `X-RateLimit-Limit`: the total quota
- `X-RateLimit-Remaining`: the remaining quota
- `X-RateLimit-Reset`: number of seconds left for the counter to reset

## Attributes

This Plugin shares the same schema as the [limit-count](./limit-count.md) Plugin. Refer to that page for the full attribute reference. Key attributes are listed below.

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| count | integer or string | False | | > 0 | The maximum allowed accumulated query AST depth within the time window. Required if `rules` is not configured. |
| time_window | integer or string | False | | > 0 | The time interval in seconds for the rate limiting window. Required if `rules` is not configured. |
| key_type | string | False | var | ["var", "var_combination", "constant"] | The type of key. `var` treats `key` as an NGINX variable. `var_combination` combines multiple variables. `constant` uses `key` as a fixed value. |
| key | string | False | remote_addr | | The key to count requests by. |
| rejected_code | integer | False | 503 | [200,...,599] | HTTP status code returned when a request is rejected for exceeding the quota. |
| rejected_msg | string | False | | non-empty | Response body returned when a request is rejected. |
| policy | string | False | local | ["local", "redis", "redis-cluster"] | Counter storage policy. `local` stores the counter in memory on the current APISIX node. `redis` and `redis-cluster` share counters across instances. |
| allow_degradation | boolean | False | false | | When true, APISIX continues handling requests if the Plugin or its dependencies become unavailable. |
| show_limit_quota_header | boolean | False | true | | When true, include `X-RateLimit-Limit` and `X-RateLimit-Remaining` headers in the response. |
| group | string | False | | non-empty | Group ID to share a single rate limiting counter across multiple routes. |
| redis_host | string | False | | | Address of the Redis node. Required when `policy` is `redis`. |
| redis_port | integer | False | 6379 | [1,...] | Port of the Redis node. Used when `policy` is `redis`. |
| redis_username | string | False | | | Username for Redis ACL authentication. Used when `policy` is `redis`. |
| redis_password | string | False | | | Password of the Redis node. Used when `policy` is `redis` or `redis-cluster`. |
| redis_ssl | boolean | False | false | | When true, use SSL to connect to Redis. Used when `policy` is `redis`. |
| redis_ssl_verify | boolean | False | false | | When true, verify the Redis server SSL certificate. Used when `policy` is `redis`. |
| redis_database | integer | False | 0 | >= 0 | The Redis database number. Used when `policy` is `redis`. |
| redis_timeout | integer | False | 1000 | [1,...] | Redis timeout in milliseconds. Used when `policy` is `redis` or `redis-cluster`. |
| redis_cluster_nodes | array[string] | False | | | List of Redis cluster node addresses. Required when `policy` is `redis-cluster`. |
| redis_cluster_name | string | False | | | Name of the Redis cluster. Required when `policy` is `redis-cluster`. |
| redis_cluster_ssl | boolean | False | false | | When true, use SSL to connect to the Redis cluster. Used when `policy` is `redis-cluster`. |
| redis_cluster_ssl_verify | boolean | False | false | | When true, verify the Redis cluster server SSL certificate. Used when `policy` is `redis-cluster`. |

### Query cost attributes

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| cost_strategy | string | False | depth | ["depth", "complexity", "node_quantifier"] | How the cost of a query is computed. See [Cost strategies](#cost-strategies). |
| max_cost | number | False | 0 | >= 0 | Reject a query costing more than this with a 403, regardless of the remaining quota. `0` disables the check. |
| score_factor | number | False | 1 | > 0 | Scales the computed cost before it is charged, so a cost model with large numbers still fits a sane quota. |
| resolve_variables | boolean | False | true | | When true, a quantifier passed as a GraphQL variable, or defaulted by the schema, is read. Turning it off makes a variable contribute nothing, which lets a client move a fan-out value into a variable and pay less for it. |
| introspection_endpoint | string | False | | `^https?://` | Where to fetch the upstream schema from. Derived from the Service's upstream when unset. |
| pass_all_downstream_headers | boolean | False | false | | When true, forward the downstream request headers on the introspection request. Only the `Authorization` header is forwarded when false. |

## GraphQL cost decorations

The per field weights are a sub resource of the Service, the same shape Consumer credentials have:

```text
GET|POST                /apisix/admin/services/{service_id}/graphql_cost_decorations
GET|PUT|PATCH|DELETE    /apisix/admin/services/{service_id}/graphql_cost_decorations/{id}
```

They belong to the Service rather than to a Plugin instance because they describe the backend's schema: one Service can carry several `graphql-limit-count` instances with different quotas, and they all share one cost model. Deleting the Service reclaims them.

| Name | Type | Required | Default | Valid values | Description |
|------|------|----------|---------|--------------|-------------|
| field_path | string | True | | | The weighted field, as `<GraphQL type>.<field>`. Further field segments pin the weight to one chain of selections, as in `Query.products.nodes.reviews`. |
| add_value | number | False | 1 | >= 0 | The field's own cost. |
| add_arguments | array[string] | False | | | Query arguments whose values are added to `add_value`. |
| mul_value | number | False | 1 | >= 0 | Multiplies the cost of everything selected under the field. |
| mul_arguments | array[string] | False | | | Query arguments whose values are multiplied into `mul_value`. |
| name | string | False | | | Name of the decoration. |
| desc | string | False | | | Description of the decoration. |
| labels | object | False | | | Attributes of the decoration, as key/value pairs. |

`service_id` is taken from the path, so sending a different one in the body is rejected. A `field_path` may be decorated at most once per Service.

## Cost strategies

With `complexity` or `node_quantifier`, the cost of one field is:

```text
cost(field) = ( sum of the fields selected under it ) * mul_value + add_value
```

`add_arguments` and `mul_arguments` name query arguments whose values fold into `add_value` and `mul_value`, which is how a paginating argument turns into fan-out. Given a decoration of `Query.products` with `mul_arguments: ["first"]`, `products(first: 50)` multiplies everything selected under it by 50.

The two strategies differ in what they charge for:

- `complexity` charges every node in the query, so the weights compound down the tree.
- `node_quantifier` charges only the fields that actually carry one of their `mul_arguments` in the query, multiplied by how many times the field is resolved. This tracks the number of upstream records a query touches rather than the size of the document.

A field with no decoration weighs 1 and multiplies by 1, so a query against a Service with no decorations is charged its node count. A Route that is not bound to a Service has nowhere to hang decorations, so the cost degenerates to the node count there as well.

The response carries the computed cost in `X-Graphql-Query-Cost` when `show_limit_quota_header` is true.

### Schema introspection

A decoration addresses a field by its GraphQL type, while the query itself only carries field names — `Person.name` cannot be told from `Vehicle.name` without the schema. The Plugin therefore issues an introspection query to the upstream on the first request that needs it, caches the result for the lifetime of the worker, and reuses it afterwards. A schema change on a live upstream takes effect after a reload.

No introspection request is made when the Service has no decorations, or when `cost_strategy` is `depth`.

### Bounds on the walk

A fragment spread twice legitimately costs twice, so a document whose fragments spread each other repeatedly can expand exponentially while staying small on the wire. The walk carries an expansion budget and a query that exhausts it is rejected with a 400 rather than costed, so the work stays bounded before any limit is applied.

A fragment's `typeCondition` narrows the selection to a concrete type, and the weights inside it are looked up on that type — `... on Product { expensive }` under an interface matches a `Product.expensive` weight. A condition naming a type the schema does not have leaves the cursor where it was.

### Multiple operations

A document containing several operations is charged for the operation `operationName` selects, since that is the one the upstream executes. When `operationName` is absent, every operation is costed and the most expensive one is charged.

## Examples

The examples below demonstrate how you can configure `graphql-limit-count` in different scenarios.

:::note

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Limit Requests by Query Depth per Client

The following example demonstrates how to rate limit GraphQL requests based on the accumulated query AST depth per client IP address. A shallow query like `{ foo { bar } }` (depth 2) consumes 2 out of the quota, while a deeply nested query like `{ foo { bar { baz { id } } } }` (depth 4) consumes 4.

Create a Route with `graphql-limit-count` that allows a cumulative query depth of 10 per minute per client IP:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "graphql-limit-count-route",
    "uri": "/graphql",
    "plugins": {
      "graphql-limit-count": {
        "count": 10,
        "time_window": 60,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "local"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1980": 1
      }
    }
  }'
```

Send a depth-4 GraphQL query:

```shell
curl -i "http://127.0.0.1:9080/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { foo { bar { baz { id } } } }"}'
```

You should receive an `HTTP/1.1 200 OK` response with the following headers:

```text
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 6
```

The depth-4 query consumed 4 out of the 10 quota. After the quota is exhausted within the time window, you will receive `HTTP/1.1 429 Too Many Requests`.

### Limit Requests by How Much Data They Ask For

Depth cannot tell `products(first: 1)` from `products(first: 1000)`. The following example charges by the number of records a query asks the upstream for.

Create a Service carrying the Plugin, and weight the paginating fields on it:

```shell
curl "http://127.0.0.1:9180/apisix/admin/services/gql" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "graphql-limit-count": {
        "count": 10000,
        "time_window": 60,
        "rejected_code": 429,
        "key": "remote_addr",
        "cost_strategy": "node_quantifier",
        "max_cost": 5000
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1980": 1
      }
    }
  }'

curl "http://127.0.0.1:9180/apisix/admin/services/gql/graphql_cost_decorations/products" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{"field_path": "Query.products", "mul_arguments": ["first"], "add_value": 1}'

curl "http://127.0.0.1:9180/apisix/admin/services/gql/graphql_cost_decorations/reviews" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{"field_path": "Product.reviews", "mul_arguments": ["first"], "add_value": 1}'

curl "http://127.0.0.1:9180/apisix/admin/routes/gql" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{"uri": "/graphql", "service_id": "gql"}'
```

Ask for 50 products and 20 reviews for each of them:

```shell
curl -i "http://127.0.0.1:9080/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { products(first: 50) { nodes { reviews(first: 20) { nodes { body } } } } }"}'
```

You should receive an `HTTP/1.1 200 OK` response with the following headers:

```text
X-Graphql-Query-Cost: 52
X-RateLimit-Limit: 10000
X-RateLimit-Remaining: 9948
```

`products` is resolved once and `reviews` once for each of the 50 products, so the query costs 51 before the floor that keeps an undecorated query at 1.

Raising `first` pushes the cost past `max_cost` and the request is rejected with `HTTP/1.1 403 Forbidden`, whatever quota is left.

### Share Quota Among APISIX Nodes with a Redis Server

The following example demonstrates how to use a Redis-backed counter so that the rate limiting quota is shared across multiple APISIX instances.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "graphql-limit-count-route",
    "uri": "/graphql",
    "plugins": {
      "graphql-limit-count": {
        "count": 100,
        "time_window": 60,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "redis",
        "redis_host": "127.0.0.1",
        "redis_port": 6379
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:1980": 1
      }
    }
  }'
```

Send a request to verify:

```shell
curl -i "http://127.0.0.1:9080/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { foo { bar } }"}'
```

You should receive an `HTTP/1.1 200 OK` response. The counter is now shared across all APISIX nodes connected to the same Redis instance.
