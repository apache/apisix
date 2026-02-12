---
title: limit-count
keywords:
  - Apache APISIX
  - API Gateway
  - Limit Count
description: The limit-count plugin uses a fixed window algorithm to limit the rate of requests by the number of requests within a given time interval. Requests exceeding the configured quota will be rejected.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/limit-count" />
</head>

## Description

The `limit-count` plugin uses a fixed window algorithm to limit the rate of requests by the number of requests within a given time interval. Requests exceeding the configured quota will be rejected.

You may see the following rate limiting headers in the response:

* `X-RateLimit-Limit`: the total quota
* `X-RateLimit-Remaining`: the remaining quota
* `X-RateLimit-Reset`: number of seconds left for the counter to reset

## Attributes

| Name                    | Type    | Required                                  | Default       | Valid values                           | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ----------------------- | ------- | ----------------------------------------- | ------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| count                   | integer | False                                     |               | > 0                              | The maximum number of requests allowed within a given time interval. Required if `rules` is not configured.                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| time_window             | integer | False                                     |               | > 0                        | The time interval corresponding to the rate limiting `count` in seconds. Required if `rules` is not configured.                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| rules                   | array[object] | False                               |               |                            | A list of rate limiting rules. Each rule is an object containing `count`, `time_window`, and `key`.                                                                                                                                                                                                                |
| rules.count             | integer | True                                      |               | > 0                        | The maximum number of requests allowed within a given time interval.                                                                                                                                                                                                                                             |
| rules.time_window       | integer | True                                      |               | > 0                        | The time interval corresponding to the rate limiting `count` in seconds.                                                                                                                                                                                                                                         |
| rules.key               | string  | True                                      |               |                            | The key to count requests by. If the configured key does not exist, the rule will not be executed. The `key` is interpreted as a combination of variables, for example: `$http_custom_a $http_custom_b`.                                                                                                                                                                                                                                                                   |
| rules.header_prefix     | string  | False                                     |               |                            | Prefix for rate limit headers. If configured, the response will include `X-{header_prefix}-RateLimit-Limit`, `X-{header_prefix}-RateLimit-Remaining`, and `X-{header_prefix}-RateLimit-Reset` headers. If not configured, the index of the rule in the rules array is used as the prefix. For example, headers for the first rule will be `X-1-RateLimit-Limit`, `X-1-RateLimit-Remaining`, and `X-1-RateLimit-Reset`.                                                                                                                                                                                                                                                                  |
| key_type                | string  | False                                     | var         | ["var","var_combination","constant"] | The type of key. If the `key_type` is `var`, the `key` is interpreted a variable. If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. If the `key_type` is `constant`, the `key` is interpreted as a constant.                  |
| key                     | string  | False                                     | remote_addr |                                        | The key to count requests by. If the `key_type` is `var`, the `key` is interpreted a variable. The variable does not need to be prefixed by a dollar sign (`$`). If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. All variables should be prefixed by dollar signs (`$`). For example, to configure the `key` to use a combination of two request headers `custom-a` and `custom-b`, the `key` should be configured as `$http_custom_a $http_custom_b`. If the `key_type` is `constant`, the `key` is interpreted as a constant value. |
| rejected_code           | integer | False                                     | 503           | [200,...,599]                          | The HTTP status code returned when a request is rejected for exceeding the threshold.                                                                                                                                                                                                                                                                                                                                                                                                                    |
| rejected_msg            | string  | False                                     |               | non-empty                              | The response body returned when a request is rejected for exceeding the threshold.                                                                                                                                                                                                                                                                                                                                                                                                                |
| policy                  | string  | False                                     | local       | ["local","redis","redis-cluster"]    | The policy for rate limiting counter. If it is `local`, the counter is stored in memory locally. If it is `redis`, the counter is stored on a Redis instance. If it is `redis-cluster`, the counter is stored in a Redis cluster.                                                                                                            |
| allow_degradation       | boolean | False                                     | false         |                                        | If true, allow APISIX to continue handling requests without the plugin when the plugin or its dependencies become unavailable.                                                                                                                                                                                                                                                                                             |
| show_limit_quota_header | boolean | False                                     | true          |                                        | If true, include `X-RateLimit-Limit` to show the total quota and `X-RateLimit-Remaining` to show the remaining quota in the response header.                                                                                                                                                                                                                                                                                                                                   |
| group                   | string  | False                                     |               | non-empty                              | The `group` ID for the plugin, such that routes of the same `group` can share the same rate limiting counter.                                                                                                                                                                                                                                                                                                                                                                   |
| redis_host              | string  | False         |               |                                        | The address of the Redis node. Required when `policy` is `redis`.                                                                                                                                                                                                                                                                                                                                                                                                                     |
| redis_port              | integer | False                                     | 6379          | [1,...]                                | The port of the Redis node when `policy` is `redis`.                                                                                                                                                                                                                                                                                                                                                                                                                        |
| redis_username          | string  | False                                     |               |                                        | The username for Redis if Redis ACL is used. If you use the legacy authentication method `requirepass`, configure only the `redis_password`. Used when `policy` is `redis`.                                                                                                                                                                                                                                                                                                                                                                                                          |
| redis_password          | string  | False                                     |               |                                        | The password of the Redis node when `policy` is `redis` or `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                                                                           |
| redis_ssl               | boolean | False                                     | false         |                                        | If true, use SSL to connect to Redis cluster when `policy` is `redis`.                                                                                                                                                                                                                                                                                                                                                                                                         |
| redis_ssl_verify        | boolean | False                                     | false         |                                        | If true, verify the server SSL certificate when `policy` is `redis`.                                                                                                                                                                                                                                                                                                                                                                                         |
| redis_database          | integer | False                                     | 0             | >= 0                    | The database number in Redis when `policy` is `redis`.                                                                                                                                                                                                                                                                                                                       |
| redis_timeout           | integer | False                                     | 1000          | [1,...]                                | The Redis timeout value in milliseconds when `policy` is `redis` or `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                        |
| redis_keepalive_timeout       | integer | False                                     | 10000         | ≥ 1000                                 | Keepalive timeout in milliseconds for redis when `policy` is `redis` or `redis-cluster`.                                      |
| redis_keepalive_pool          | integer | False                                     | 100           | ≥ 1                                    | Keepalive pool size for redis when `policy` is `redis` or `redis-cluster`.                                                    |
| redis_cluster_nodes     | array[string]   | False |               |                                        | The list of the Redis cluster nodes with at least two addresses. Required when policy is redis-cluster.                                                                                                                                                                                                                                                                                                                                                                                                       |
| redis_cluster_name      | string  | False |               |                                        | The name of the Redis cluster. Required when `policy` is `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                                                                |
| redis_cluster_ssl      | boolean  |  False |     false         |                                        | If true, use SSL to connect to Redis cluster when `policy` is `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                                               |
| redis_cluster_ssl_verify      | boolean  | False |    false      |                                        | If true, verify the server SSL certificate when `policy` is `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                                                               |

## Examples

The examples below demonstrate how you can configure `limit-count` in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Apply Rate Limiting by Remote Address

The following example demonstrates the rate limiting of requests by a single variable, `remote_addr`.

Create a Route with `limit-count` plugin that allows for a quota of 1 within a 30-second window per remote address:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Send a request to verify:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response.

The request has consumed all the quota allowed for the time window. If you send the request again within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response, indicating the request surpasses the quota threshold.

### Apply Rate Limiting by Remote Address and Consumer Name

The following example demonstrates the rate limiting of requests by a combination of variables, `remote_addr` and `consumer_name`. It allows for a quota of 1 within a 30-second window per remote address and for each consumer.

Create a Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

Create `key-auth` Credential for the consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

Create a second Consumer `jane`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "jane"
  }'
```

Create `key-auth` Credential for the Consumer:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/jane/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jane-key"
      }
    }
  }'
```

Create a Route with `key-auth` and `limit-count` plugins, and specify in the `limit-count` plugin to use a combination of variables as the rate limiting key:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "key_type": "var_combination",
        "key": "$remote_addr $consumer_name"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Send a request as the Consumer `jane`:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jane-key'
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body.

This request has consumed all the quota set for the time window. If you send the same request as the Consumer `jane` within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response, indicating the request surpasses the quota threshold.

Send the same request as the Consumer `john` within the same 30-second time interval:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key'
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body, indicating the request is not rate limited.

Send the same request as the Consumer `john` again within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response.

This verifies the plugin rate limits by the combination of variables, `remote_addr` and `consumer_name`.

### Share Quota among Routes

The following example demonstrates the sharing of rate limiting quota among multiple routes by configuring the `group` of the `limit-count` plugin.

Note that the configurations of the `limit-count` plugin of the same `group` should be identical. To avoid update anomalies and repetitive configurations, you can create a Service with `limit-count` plugin and Upstream for routes to connect to.

Create a service:

```shell
curl "http://127.0.0.1:9180/apisix/admin/services" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-service",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "group": "srv1"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Create two Routes and configure their `service_id` to be `limit-count-service`, so that they share the same configurations for the Plugin and Upstream:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route-1",
    "service_id": "limit-count-service",
    "uri": "/get1",
    "plugins": {
      "proxy-rewrite": {
        "uri": "/get"
      }
    }
  }'
```

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route-2",
    "service_id": "limit-count-service",
    "uri": "/get2",
    "plugins": {
      "proxy-rewrite": {
        "uri": "/get"
      }
    }
  }'
```

:::note

The [`proxy-rewrite`](./proxy-rewrite.md) plugin is used to rewrite the URI to `/get` so that requests are forwarded to the correct endpoint.

:::

Send a request to Route `/get1`:

```shell
curl -i "http://127.0.0.1:9080/get1"
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body.

Send the same request to Route `/get2` within the same 30-second time interval:

```shell
curl -i "http://127.0.0.1:9080/get2"
```

You should receive an `HTTP/1.1 429 Too Many Requests` response, which verifies the two routes share the same rate limiting quota.

### Share Quota Among APISIX Nodes with a Redis Server

The following example demonstrates the rate limiting of requests across multiple APISIX nodes with a Redis server, such that different APISIX nodes share the same rate limiting quota.

On each APISIX instance, create a Route with the following configurations. Adjust the address of the Admin API, Redis host, port, password, and database accordingly.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "key": "remote_addr",
        "policy": "redis",
        "redis_host": "192.168.xxx.xxx",
        "redis_port": 6379,
        "redis_password": "p@ssw0rd",
        "redis_database": 1
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Send a request to an APISIX instance:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body.

Send the same request to a different APISIX instance within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response, verifying routes configured in different APISIX nodes share the same quota.

### Share Quota Among APISIX Nodes with a Redis Cluster

You can also use a Redis cluster to apply the same quota across multiple APISIX nodes, such that different APISIX nodes share the same rate limiting quota.

Ensure that your Redis instances are running in [cluster mode](https://redis.io/docs/management/scaling/#create-and-use-a-redis-cluster). A minimum of two nodes are required for the `limit-count` plugin configurations.

On each APISIX instance, create a Route with the following configurations. Adjust the address of the Admin API, Redis cluster nodes, password, cluster name, and SSL varification accordingly.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-count-route",
    "uri": "/get",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429,
        "key": "remote_addr",
        "policy": "redis-cluster",
        "redis_cluster_nodes": [
          "192.168.xxx.xxx:6379",
          "192.168.xxx.xxx:16379"
        ],
        "redis_password": "p@ssw0rd",
        "redis_cluster_name": "redis-cluster-1",
        "redis_cluster_ssl": true
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

Send a request to an APISIX instance:

```shell
curl -i "http://127.0.0.1:9080/get"
```

You should see an `HTTP/1.1 200 OK` response with the corresponding response body.

Send the same request to a different APISIX instance within the same 30-second time interval, you should receive an `HTTP/1.1 429 Too Many Requests` response, verifying routes configured in different APISIX nodes share the same quota.

### Rate Limit with Anonymous Consumer

does not need to authenticate and has less quotas. While this example uses [`key-auth`](./key-auth.md) for authentication, the anonymous Consumer can also be configured with [`basic-auth`](./basic-auth.md), [`jwt-auth`](./jwt-auth.md), and [`hmac-auth`](./hmac-auth.md).

Create a regular Consumer `john` and configure the `limit-count` plugin to allow for a quota of 3 within a 30-second window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john",
    "plugins": {
      "limit-count": {
        "count": 3,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

Create the `key-auth` Credential for the Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/john/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

Create an anonymous user `anonymous` and configure the `limit-count` Plugin to allow for a quota of 1 within a 30-second window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "anonymous",
    "plugins": {
      "limit-count": {
        "count": 1,
        "time_window": 30,
        "rejected_code": 429
      }
    }
  }'
```

Create a Route and configure the `key-auth` Plugin to accept anonymous Consumer `anonymous` from bypassing the authentication:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "key-auth-route",
    "uri": "/anything",
    "plugins": {
      "key-auth": {
        "anonymous_consumer": "anonymous"
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

To verify, send five consecutive requests with `john`'s key:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -H 'apikey: john-key' -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that out of the 5 requests, 3 requests were successful (status code 200) while the others were rejected (status code 429).

```text
200:    3, 429:    2
```

Send five anonymous requests:

```shell
resp=$(seq 5 | xargs -I{} curl "http://127.0.0.1:9080/anything" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200": $count_200, "429": $count_429
```

You should see the following response, showing that only one request was successful:

```text
200:    1, 429:    4
```
