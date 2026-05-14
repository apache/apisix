---
title: graphql-limit-count
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - graphql-limit-count
  - Rate Limiting
  - GraphQL
description: The graphql-limit-count Plugin limits the rate of GraphQL requests by the depth of the query AST within a given time window, using the same counting mechanism as the limit-count Plugin.
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

The `graphql-limit-count` Plugin limits the rate of GraphQL requests using a fixed window algorithm. Unlike `limit-count`, which counts each request as a cost of 1, this plugin uses the **depth of the GraphQL query AST** as the cost. This lets you enforce stricter limits on deeply nested queries that are more expensive to process.

Only `POST` requests are supported. The request body must use either `application/json` (with a `query` field) or `application/graphql` content type.

You may see the following rate limiting headers in the response:

- `X-RateLimit-Limit`: the total quota
- `X-RateLimit-Remaining`: the remaining quota
- `X-RateLimit-Reset`: number of seconds left for the counter to reset

## Attributes

This plugin shares the same schema as the [limit-count](./limit-count.md) plugin. All attributes from `limit-count` apply here.

| Name                    | Type              | Required | Default       | Valid values                           | Description                                                                                              |
| ----------------------- | ----------------- | -------- | ------------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| count                   | integer or string | False    |               | > 0                                    | The maximum allowed accumulated GraphQL query depth within the time window. Required if `rules` is not configured. |
| time_window             | integer or string | False    |               | > 0                                    | The time interval in seconds. Required if `rules` is not configured.                                    |
| key_type                | string            | False    | var           | ["var","var_combination","constant"]   | The type of key.                                                                                         |
| key                     | string            | False    | remote_addr   |                                        | The key to count requests by.                                                                            |
| rejected_code           | integer           | False    | 503           | [200,...,599]                          | The HTTP status code returned when a request is rejected.                                                |
| rejected_msg            | string            | False    |               | non-empty                              | The response body returned when a request is rejected.                                                   |
| policy                  | string            | False    | local         | ["local","redis","redis-cluster"]      | The policy for the rate limiting counter.                                                                |
| allow_degradation       | boolean           | False    | false         |                                        | If true, APISIX continues handling requests when the plugin or its dependencies are unavailable.         |
| show_limit_quota_header | boolean           | False    | true          |                                        | If true, include rate limiting headers in the response.                                                  |
| group                   | string            | False    |               | non-empty                              | Group ID for sharing the rate limiting counter across routes.                                            |
| redis_host              | string            | False    |               |                                        | Address of the Redis node. Required when `policy` is `redis`.                                            |
| redis_port              | integer           | False    | 6379          | [1,...]                                | Port of the Redis node when `policy` is `redis`.                                                         |
| redis_username          | string            | False    |               |                                        | Username for Redis ACL authentication when `policy` is `redis`.                                          |
| redis_password          | string            | False    |               |                                        | Password of the Redis node when `policy` is `redis` or `redis-cluster`.                                  |
| redis_ssl               | boolean           | False    | false         |                                        | If true, use SSL to connect to Redis when `policy` is `redis`.                                           |
| redis_ssl_verify        | boolean           | False    | false         |                                        | If true, verify the server SSL certificate when `policy` is `redis`.                                     |
| redis_database          | integer           | False    | 0             | >= 0                                   | The database number in Redis when `policy` is `redis`.                                                   |
| redis_timeout           | integer           | False    | 1000          | [1,...]                                | The Redis timeout in milliseconds when `policy` is `redis` or `redis-cluster`.                           |
| redis_cluster_nodes     | array[string]     | False    |               |                                        | List of Redis cluster nodes. Required when `policy` is `redis-cluster`.                                  |
| redis_cluster_name      | string            | False    |               |                                        | Name of the Redis cluster. Required when `policy` is `redis-cluster`.                                    |
| redis_cluster_ssl       | boolean           | False    | false         |                                        | If true, use SSL to connect to the Redis cluster when `policy` is `redis-cluster`.                       |
| redis_cluster_ssl_verify| boolean           | False    | false         |                                        | If true, verify the server SSL certificate when `policy` is `redis-cluster`.                             |

## Examples

The examples below demonstrate how you can configure `graphql-limit-count` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Limit by GraphQL query depth (local policy)

The following example demonstrates how to rate limit GraphQL requests based on query depth using an in-memory counter.

Create a route with `graphql-limit-count`:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/graphql",
  "plugins": {
    "graphql-limit-count": {
      "count": 10,
      "time_window": 60,
      "rejected_code": 429,
      "key": "remote_addr"
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

Send a GraphQL `POST` request:

```shell
curl -i http://127.0.0.1:9080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "query { foo { bar { baz } } }"}'
```

The response should include `X-RateLimit-Remaining` showing the remaining quota. The cost is the depth of the query AST (3 in this case), so this request consumes 3 out of 10.

### Limit by GraphQL query depth (Redis policy)

The following example demonstrates using a Redis-backed counter to share state across multiple APISIX nodes.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/graphql",
  "plugins": {
    "graphql-limit-count": {
      "count": 100,
      "time_window": 60,
      "rejected_code": 429,
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
