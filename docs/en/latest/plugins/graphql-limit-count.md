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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `graphql-limit-count` Plugin limits the rate of GraphQL requests using a fixed window algorithm. Unlike `limit-count`, which counts each request as a cost of 1, this plugin uses the **depth of the GraphQL query AST** as the cost per request. This allows you to enforce stricter limits on deeply nested queries that are more expensive to process, protecting your GraphQL services from resource exhaustion.

Only `POST` requests are supported. The plugin accepts two content types:

- `application/json`: request body must contain a `query` field with the GraphQL query string.
- `application/graphql`: request body is the raw GraphQL query starting with `query`.

You may see the following rate limiting headers in the response:

- `X-RateLimit-Limit`: the total quota
- `X-RateLimit-Remaining`: the remaining quota
- `X-RateLimit-Reset`: number of seconds left for the counter to reset

## Attributes

This plugin shares the same schema as the [limit-count](./limit-count.md) plugin. Refer to that page for the full attribute reference. Key attributes are summarized below.

| Name                    | Type              | Required | Default     | Valid values                           | Description                                                                                                                                              |
| ----------------------- | ----------------- | -------- | ----------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| count                   | integer or string | False    |             | > 0                                    | The maximum allowed accumulated query depth within the time window. Required if `rules` is not configured.                                               |
| time_window             | integer or string | False    |             | > 0                                    | The time interval in seconds. Required if `rules` is not configured.                                                                                     |
| key_type                | string            | False    | var         | ["var","var_combination","constant"]   | The type of key. `var` treats `key` as an NGINX variable. `var_combination` combines multiple variables. `constant` uses `key` as a fixed value.         |
| key                     | string            | False    | remote_addr |                                        | The key to count requests by.                                                                                                                            |
| rejected_code           | integer           | False    | 503         | [200,...,599]                          | HTTP status code returned when a request is rejected.                                                                                                    |
| rejected_msg            | string            | False    |             | non-empty                              | Response body returned when a request is rejected.                                                                                                       |
| policy                  | string            | False    | local       | ["local","redis","redis-cluster"]      | Counter storage policy. `local` uses an in-memory counter per APISIX instance. `redis` and `redis-cluster` share counters across instances.              |
| allow_degradation       | boolean           | False    | false       |                                        | When true, APISIX continues handling requests even if the plugin or its dependencies are unavailable.                                                    |
| show_limit_quota_header | boolean           | False    | true        |                                        | When true, include `X-RateLimit-Limit` and `X-RateLimit-Remaining` headers in the response.                                                              |
| group                   | string            | False    |             | non-empty                              | Group ID to share a single rate limiting counter across multiple routes.                                                                                  |
| redis_host              | string            | False    |             |                                        | Address of the Redis node. Required when `policy` is `redis`.                                                                                            |
| redis_port              | integer           | False    | 6379        | [1,...]                                | Port of the Redis node when `policy` is `redis`.                                                                                                         |
| redis_username          | string            | False    |             |                                        | Username for Redis ACL authentication when `policy` is `redis`.                                                                                          |
| redis_password          | string            | False    |             |                                        | Password of the Redis node when `policy` is `redis` or `redis-cluster`.                                                                                  |
| redis_ssl               | boolean           | False    | false       |                                        | When true, use SSL to connect to Redis when `policy` is `redis`.                                                                                         |
| redis_ssl_verify        | boolean           | False    | false       |                                        | When true, verify the Redis server SSL certificate when `policy` is `redis`.                                                                             |
| redis_database          | integer           | False    | 0           | >= 0                                   | The Redis database number when `policy` is `redis`.                                                                                                      |
| redis_timeout           | integer           | False    | 1000        | [1,...]                                | Redis timeout in milliseconds when `policy` is `redis` or `redis-cluster`.                                                                               |
| redis_cluster_nodes     | array[string]     | False    |             |                                        | List of Redis cluster node addresses. Required when `policy` is `redis-cluster`.                                                                         |
| redis_cluster_name      | string            | False    |             |                                        | Name of the Redis cluster. Required when `policy` is `redis-cluster`.                                                                                    |
| redis_cluster_ssl       | boolean           | False    | false       |                                        | When true, use SSL to connect to the Redis cluster when `policy` is `redis-cluster`.                                                                     |
| redis_cluster_ssl_verify| boolean           | False    | false       |                                        | When true, verify the Redis cluster server SSL certificate when `policy` is `redis-cluster`.                                                             |

## Examples

The examples below demonstrate how you can configure `graphql-limit-count` in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Limit Requests by Query Depth per Client

The following example demonstrates how to rate limit GraphQL requests based on the accumulated query AST depth per client IP address. A depth-2 query like `{ foo { bar } }` consumes 2 out of the configured quota, while a depth-4 query like `{ foo { bar { baz { id } } } }` consumes 4.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: graphql-service
    routes:
      - uris:
          - /graphql
        name: graphql-limit-count-route
        plugins:
          graphql-limit-count:
            count: 10
            time_window: 60
            rejected_code: 429
            key_type: var
            key: remote_addr
            policy: local
    upstream:
      type: roundrobin
      nodes:
        - host: 127.0.0.1
          port: 1980
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

</Tabs>

Send a GraphQL request with a depth-4 query:

```shell
curl -i "http://127.0.0.1:9080/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { foo { bar { baz { id } } } }"}'
```

You should receive an `HTTP/1.1 200 OK` response with headers showing the remaining quota:

```text
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 6
```

The depth-4 query consumed 4 out of the 10 quota. After the quota is exhausted, you will receive `HTTP/1.1 429 Too Many Requests`.

### Share Quota Among APISIX Nodes with a Redis Server

The following example demonstrates how to use a Redis-backed counter so that the rate limiting quota is shared across multiple APISIX instances.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: graphql-service
    routes:
      - uris:
          - /graphql
        name: graphql-limit-count-route
        plugins:
          graphql-limit-count:
            count: 100
            time_window: 60
            rejected_code: 429
            key_type: var
            key: remote_addr
            policy: redis
            redis_host: 127.0.0.1
            redis_port: 6379
    upstream:
      type: roundrobin
      nodes:
        - host: 127.0.0.1
          port: 1980
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

</Tabs>

Send a request to verify:

```shell
curl -i "http://127.0.0.1:9080/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { foo { bar } }"}'
```

You should receive an `HTTP/1.1 200 OK` response. The counter is now shared across all APISIX nodes connected to the same Redis instance.
