---
title: limit-conn
keywords:
  - Apache APISIX
  - API Gateway
  - Limit Connection
description: The limit-conn plugin restricts the rate of requests by managing concurrent connections. Requests exceeding the threshold may be delayed or rejected, ensuring controlled API usage and preventing overload.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/limit-conn" />
</head>

## Description

The `limit-conn` Plugin limits the rate of requests by the number of concurrent connections. Requests exceeding the threshold will be delayed or rejected based on the configuration, ensuring controlled resource usage and preventing overload.

## Attributes

| Name       | Type    | Required | Default     | Valid values      | Description     |
|------------|---------|----------|-------------|-------------------|-----------------|
| conn       | integer | False     |     | > 0   | The maximum number of concurrent requests allowed. Requests exceeding the configured limit and below `conn + burst` will be delayed. Required if `rules` is not configured.      |
| burst      | integer | False     |     | >= 0        | The number of excessive concurrent requests allowed to be delayed per second. Requests exceeding the limit will be rejected immediately. Required if `rules` is not configured.       |
| default_conn_delay       | number  | True     |     | > 0    | Processing latency allowed in seconds for concurrent requests exceeding `conn + burst`, which can be dynamically adjusted based on `only_use_default_delay` setting.           |
| only_use_default_delay   | boolean | False    | false       |      | If false, delay requests proportionally based on how much they exceed the `conn` limit. The delay grows larger as congestion increases. For instance, with `conn` being `5`, `burst` being `3`, and `default_conn_delay` being `1`, 6 concurrent requests would result in a 1-second delay, 7 requests a 2-second delay, 8 requests a 3-second delay, and so on, until the total limit of `conn + burst` is reached, beyond which requests are rejected. If true, use `default_conn_delay` to delay all excessive requests within the `burst` range. Requests beyond `conn + burst` are rejected immediately. For instance, with `conn` being `5`, `burst` being `3`, and `default_conn_delay` being `1`, 6, 7, or 8 concurrent requests are all delayed by exactly 1 second each. |
| rules                    | array[object] | False    |       |                   | A list of connection limiting rules. Each rule is an object containing `conn`, `burst`, and `key`. If configured, this takes precedence over `conn`, `burst`, and `key`. |
| rules.conn               | integer or string | True |       | > 0 or variable expression | The maximum number of concurrent requests allowed. Can be a static integer or a variable expression like `$http_custom_conn`. |
| rules.burst              | integer or string | True |       | >= 0 or variable expression | The number of excessive concurrent requests allowed to be delayed. Can be a static integer or a variable expression. |
| rules.key                | string  | True     |       |                   | The key to count requests by. If the configured key does not exist, the rule will not be executed. The `key` is interpreted as a combination of variables, for example: `$http_custom_a $http_custom_b`. |
| key_type        | string  | False      | var   | ["var","var_combination"] | The type of key. If the `key_type` is `var`, the `key` is interpreted a variable. If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables.    |
| key       | string  | False      | remote_addr |   | The key to count requests by. If the `key_type` is `var`, the `key` is interpreted a variable. The variable does not need to be prefixed by a dollar sign (`$`). If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. All variables should be prefixed by dollar signs (`$`). For example, to configure the `key` to use a combination of two request headers `custom-a` and `custom-b`, the `key` should be configured as `$http_custom_a $http_custom_b`. Required if `rules` is not configured. |
| key_ttl   | integer | False      | 3600          |   | The TTL of the Redis key in seconds. Used when `policy` is `redis` or `redis-cluster`. |
| rejected_code   | integer | False      | 503   | [200,...,599]   | The HTTP status code returned when a request is rejected for exceeding the threshold.     |
| rejected_msg    | string  | False        |       | non-empty   | The response body returned when a request is rejected for exceeding the threshold.     |
| allow_degradation       | boolean | False      | false   |   | If true, allow APISIX to continue handling requests without the Plugin when the Plugin or its dependencies become unavailable.        |
| policy    | string  | False      | local       | ["local","redis","redis-cluster"]    | The policy for rate limiting counter. If it is `local`, the counter is stored in memory locally. If it is `redis`, the counter is stored on a Redis instance. If it is `redis-cluster`, the counter is stored in a Redis cluster.    |
| redis_host      | string  | False   |       |   | The address of the Redis node. Required when `policy` is `redis`.    |
| redis_port      | integer | False      | 6379    | [1,...]   | The port of the Redis node when `policy` is `redis`.       |
| redis_username    | string  | False      |       |   | The username for Redis if Redis ACL is used. If you use the legacy authentication method `requirepass`, configure only the `redis_password`. Used when `policy` is `redis`.        |
| redis_password    | string  | False      |       |   | The password of the Redis node when `policy` is `redis` or `redis-cluster`.        |
| redis_ssl       | boolean | False      | false   |   | If true, use SSL to connect to Redis cluster when `policy` is `redis`.       |
| redis_ssl_verify        | boolean | False      | false   |   | If true, verify the server SSL certificate when `policy` is `redis`.    |
| redis_database    | integer | False      | 0     | >= 0      | The database number in Redis when `policy` is `redis`.    |
| redis_timeout   | integer | False      | 1000    | [1,...]   | The Redis timeout value in milliseconds when `policy` is `redis` or `redis-cluster`.      |
| redis_keepalive_timeout | integer | False | 10000 | ≥ 1000 | Keepalive timeout in milliseconds for redis when `policy` is `redis` or `redis-cluster`. |
| redis_keepalive_pool | integer | False | 100 | ≥ 1 | Keepalive pool size for redis when `policy` is `redis` or `redis-cluster`.|
| redis_cluster_nodes     | array[string]   | False |       |   | The list of the Redis cluster nodes with at least two addresses. Required when policy is redis-cluster.     |
| redis_cluster_name      | string  | False |       |   | The name of the Redis cluster. Required when `policy` is `redis-cluster`.      |
| redis_cluster_ssl      | boolean  |  False |     false   |   | If true, use SSL to connect to Redis cluster when `policy` is      |
| redis_cluster_ssl_verify      | boolean  | False |    false      |   | If true, verify the server SSL certificate when `policy` is `redis-cluster`.     |

## Examples

The examples below demonstrate how you can configure `limit-conn` in different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Apply Rate Limiting by Remote Address

The following example demonstrates how to use `limit-conn` to rate limit requests by `remote_addr`, with example connection and burst thresholds.

Create a Route with `limit-conn` Plugin to allow 2 concurrent requests and 1 excessive concurrent request. Additionally:

* Configure the Plugin to allow 0.1 second of processing latency for concurrent requests exceeding `conn + burst`.
* Set the key type to `vars` to interpret `key` as a variable.
* Calculate rate limiting count by request's `remote_address`.
* Set `policy` to `local` to use the local counter in memory.
* Customize the `rejected_code` to `429`.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "conn": 2,
        "burst": 1,
        "default_conn_delay": 0.1,
        "key_type": "var",
        "key": "remote_addr",
        "policy": "local",
        "rejected_code": 429
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

Send five concurrent requests to the route:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

You should see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

### Apply Rate Limiting by Remote Address and Consumer Name

The following example demonstrates how to use `limit-conn` to rate limit requests by a combination of variables, `remote_addr` and `consumer_name`.

Create a Consumer `john`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "john"
  }'
```

Create `key-auth` Credential for the Consumer:

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

Create a Route with `key-auth` and `limit-conn` Plugins, and specify in the `limit-conn` Plugin to use a combination of variables as the rate limiting key:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "limit-conn": {
        "conn": 2,
        "burst": 1,
        "default_conn_delay": 0.1,
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

Send five concurrent requests as the Consumer `john`:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "apikey: john-key"'
```

You should see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

Immediately send five concurrent requests as the Consumer `jane`:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get" -H "apikey: jane-key"'
```

You should also see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 200
Response: 429
Response: 429
```

### Rate Limit WebSocket Connections

The following example demonstrates how you can use the `limit-conn` Plugin to limit the number of concurrent WebSocket connections.

Start a [sample upstream WebSocket server](https://hub.docker.com/r/jmalloc/echo-server):

```shell
docker run -d \
  -p 8080:8080 \
  --name websocket-server \
  --network=apisix-quickstart-net \
  jmalloc/echo-server
```

Create a Route to the server WebSocket endpoint and enable WebSocket for the route. Adjust the WebSocket server address accordingly.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "ws-route",
  "uri": "/.ws",
  "plugins": {
    "limit-conn": {
      "conn": 2,
      "burst": 1,
      "default_conn_delay": 0.1,
      "key_type": "var",
      "key": "remote_addr",
      "rejected_code": 429
    }
  },
  "enable_websocket": true,
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "websocket-server:8080": 1
    }
  }
}'
```

Install a WebSocket client, such as [websocat](https://github.com/vi/websocat), if you have not already. Establish connection with the WebSocket server through the route:

```shell
websocat "ws://127.0.0.1:9080/.ws"
```

Send a "hello" message in the terminal, you should see the WebSocket server echoes back the same message:

```text
Request served by 1cd244052136
hello
hello
```

Open three more terminal sessions and run:

```shell
websocat "ws://127.0.0.1:9080/.ws"
```

You should see the last terminal session prints `429 Too Many Requests` when you try to establish a WebSocket connection with the server, due to the rate limiting effect.

### Share Quota Among APISIX Nodes with a Redis Server

The following example demonstrates the rate limiting of requests across multiple APISIX nodes with a Redis server, such that different APISIX nodes share the same rate limiting quota.

On each APISIX instance, create a Route  with the following configurations. Adjust the address of the Admin API, Redis host, port, password, and database accordingly.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "conn": 1,
        "burst": 1,
        "default_conn_delay": 0.1,
        "rejected_code": 429,
        "key_type": "var",
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

Send five concurrent requests to the route:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

You should see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 429
Response: 429
Response: 429
```

This shows the two routes configured in different APISIX instances share the same quota.

### Share Quota Among APISIX Nodes with a Redis Cluster

You can also use a Redis cluster to apply the same quota across multiple APISIX nodes, such that different APISIX nodes share the same rate limiting quota.

Ensure that your Redis instances are running in [cluster mode](https://redis.io/docs/management/scaling/#create-and-use-a-redis-cluster). A minimum of two nodes are required for the `limit-conn` Plugin configurations.

On each APISIX instance, create a Route with the following configurations. Adjust the address of the Admin API, Redis cluster nodes, password, cluster name, and SSL varification accordingly.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-conn-route",
    "uri": "/get",
    "plugins": {
      "limit-conn": {
        "conn": 1,
        "burst": 1,
        "default_conn_delay": 0.1,
        "rejected_code": 429,
        "key_type": "var",
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

Send five concurrent requests to the route:

```shell
seq 1 5 | xargs -n1 -P5 bash -c 'curl -s -o /dev/null -w "Response: %{http_code}\n" "http://127.0.0.1:9080/get"'
```

You should see responses similar to the following, where excessive requests are rejected:

```text
Response: 200
Response: 200
Response: 429
Response: 429
Response: 429
```

This shows the two routes configured in different APISIX instances share the same quota.
