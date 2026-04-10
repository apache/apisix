---
title: limit-req
keywords:
  - Apache APISIX
  - API Gateway
  - Limit Request
  - limit-req
description: The limit-req Plugin uses the leaky bucket algorithm to rate limit the number of the requests and allow for throttling.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/limit-req" />
</head>

## Description

The `limit-req` Plugin uses the [leaky bucket](https://en.wikipedia.org/wiki/Leaky_bucket) algorithm to rate limit the number of the requests and allow for throttling.

## Attributes

| Name              | Type    | Required | Default | Valid values               | Description                                                                                                           |
|-------------------|---------|----------|---------|----------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| rate              | integer | True     |         | > 0                   | The maximum number of requests allowed per second. Requests exceeding the rate and below burst will be delayed.                                                                                                                                                                                                                                                                    |
| burst             | integer | True     |         | >= 0                 | The number of requests allowed to be delayed per second for throttling. Requests exceeding the rate and burst will get rejected.                                                                                                                                                                                                                                               |
| key_type          | string  | False    | var   | ["var", "var_combination"] | The type of key. If the `key_type` is `var`, the `key` is interpreted a variable. If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables.                                                                                                                                                                                                                                                  |
| key               | string  | True     |  remote_addr  |   | The key to count requests by. If the `key_type` is `var`, the `key` is interpreted a variable. The variable does not need to be prefixed by a dollar sign (`$`). If the `key_type` is `var_combination`, the `key` is interpreted as a combination of variables. All variables should be prefixed by dollar signs (`$`). For example, to configure the `key` to use a combination of two request headers `custom-a` and `custom-b`, the `key` should be configured as `$http_custom_a $http_custom_b`. |
| rejected_code     | integer | False    | 503     | [200,...,599]              | The HTTP status code returned when a request is rejected for exceeding the threshold.                                                                   |
| rejected_msg      | string  | False    |         | non-empty                  | The response body returned when a request is rejected for exceeding the threshold.                                                              |
| nodelay           | boolean | False    | false   |                            | If true, do not delay requests within the burst threshold.                                                                        |
| allow_degradation | boolean | False    | false   |                            | If true, allow APISIX to continue handling requests without the Plugin when the Plugin or its dependencies become unavailable.                                                                                                                                                                                                                                                                             |
| policy            | string  | False                                     | local   | ["local", "redis", "redis-cluster"] | The policy for rate limiting counter. If it is `local`, the counter is stored in memory locally. If it is `redis`, the counter is stored on a Redis instance. If it is `redis-cluster`, the counter is stored in a Redis cluster.                                                                                                            |
| redis_host        | string  | False         |         |                            | The address of the Redis node. Required when `policy` is `redis`.                                                                  |
| redis_port        | integer | False                                     | 6379    | [1,...]                    | The port of the Redis node when `policy` is `redis`.                                                                     |
| redis_username    | string  | False                                     |         |                            | The username for Redis if Redis ACL is used. If you use the legacy authentication method `requirepass`, configure only the `redis_password`. Used when `policy` is `redis`.                                                                                                                                                  |
| redis_password    | string  | False                                     |         |                            | The password of the Redis node when `policy` is `redis` or `redis-cluster`.                                                   |
| redis_ssl               | boolean | False                                     | false         |                                        | If true, use SSL to connect to Redis cluster when `policy` is `redis`.                                                                                                                         |
| redis_ssl_verify        | boolean | False                                     | false         |                                        | If true, verify the server SSL certificate when `policy` is `redis`.                                                                                                         |
| redis_database          | integer | False                                     | 0             | >= 0                    | The database number in Redis when `policy` is `redis`.                                                                     |
| redis_timeout           | integer | False                                     | 1000          | [1,...]                                | The Redis timeout value in milliseconds when `policy` is `redis` or `redis-cluster`.                                                                        |
| redis_keepalive_timeout       | integer | False                                     | 10000         | ≥ 1000                                 | Keepalive timeout in milliseconds for redis when `policy` is `redis` or `redis-cluster`.                                      |
| redis_keepalive_pool          | integer | False                                     | 100           | ≥ 1                                    | Keepalive pool size for redis when `policy` is `redis` or `redis-cluster`.                                                    |
| redis_cluster_nodes     | array[string]   | False |               |                                        | The list of the Redis cluster nodes with at least two addresses. Required when policy is redis-cluster.                                                                                                                       |
| redis_cluster_name      | string  | False |               |                                        | The name of the Redis cluster. Required when `policy` is `redis-cluster`.                                                                                                                |
| redis_cluster_ssl      | boolean  |  False |     false         |                                        | If true, use SSL to connect to Redis cluster when `policy` is                                                                                                                |
| redis_cluster_ssl_verify      | boolean  | False |    false      |                                        | If true, verify the server SSL certificate when `policy` is `redis-cluster`.                                                                                                               |

## Examples

The examples below demonstrate how you can configure `limit-req` in different scenarios.

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

### Apply Rate Limiting by Remote Address

The following example demonstrates the rate limiting of HTTP requests by a single variable, `remote_addr`.

Create a Route with `limit-req` Plugin that allows for 1 QPS per remote address:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '
  {
    "id": "limit-req-route",
    "uri": "/get",
    "plugins": {
      "limit-req": {
        "rate": 1,
        "burst": 0,
        "key": "remote_addr",
        "key_type": "var",
        "rejected_code": 429,
        "nodelay": true
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

The request has consumed all the quota allowed for the time window. If you send the request again within the same second, you should receive an `HTTP/1.1 429 Too Many Requests` response, indicating the request surpasses the quota threshold.

### Implement API Throttling

The following example demonstrates how to configure `burst` to allow overrun of the rate limiting threshold by the configured value and achieve request throttling. You will also see a comparison against when throttling is not implemented.

Create a Route with `limit-req` Plugin that allows for 1 QPS per remote address, with a `burst` of 1 to allow for 1 request exceeding the `rate` to be delayed for processing:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-req-route",
    "uri": "/get",
    "plugins": {
      "limit-req": {
        "rate": 1,
        "burst": 1,
        "key": "remote_addr",
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

Generate three requests to the Route:

```shell
resp=$(seq 3 | xargs -I{} curl -i "http://127.0.0.1:9080/get" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200 responses: $count_200 ; 429 responses: $count_429"
```

You are likely to see that all three requests are successful:

```text
200 responses: 3 ; 429 responses: 0
```

To see the effect without `burst`, update `burst` to 0 or set `nodelay` to `true` as follows:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/limit-req-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "limit-req": {
        "nodelay": true
      }
    }
  }'
```

Generate three requests to the Route again:

```shell
resp=$(seq 3 | xargs -I{} curl -i "http://127.0.0.1:9080/get" -o /dev/null -s -w "%{http_code}\n") && \
  count_200=$(echo "$resp" | grep "200" | wc -l) && \
  count_429=$(echo "$resp" | grep "429" | wc -l) && \
  echo "200 responses: $count_200 ; 429 responses: $count_429"
```

You should see a response similar to the following, showing requests surpassing the rate have been rejected:

```text
200 responses: 1 ; 429 responses: 2
```

### Apply Rate Limiting by Remote Address and Consumer Name

The following example demonstrates the rate limiting of requests by a combination of variables, `remote_addr` and `consumer_name`.

Create a Route with `limit-req` Plugin that allows for 1 QPS per remote address and for each Consumer.

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

Create a Route with `key-auth` and `limit-req` Plugins, and specify in the `limit-req` Plugin to use a combination of variables as the rate-limiting key:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "limit-req-route",
    "uri": "/get",
    "plugins": {
      "key-auth": {},
      "limit-req": {
        "rate": 1,
        "burst": 0,
        "key": "$remote_addr $consumer_name",
        "key_type": "var_combination",
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

Send two requests simultaneously, each for one Consumer:

```shell
curl -i "http://127.0.0.1:9080/get" -H 'apikey: jane-key' & \
curl -i "http://127.0.0.1:9080/get" -H 'apikey: john-key' &
```

You should receive `HTTP/1.1 200 OK` for both requests, indicating the request has not exceeded the threshold for each Consumer.

If you send more requests as either Consumer within the same second, you should receive an `HTTP/1.1 429 Too Many Requests` response.

This verifies the Plugin rate limits by the combination of variables, `remote_addr` and `consumer_name`.
