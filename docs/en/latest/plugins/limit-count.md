---
title: limit-count
keywords:
  - Apache APISIX
  - API Gateway
  - Limit Count
description: This document contains information about the Apache APISIX limit-count Plugin, you can use it to limit the number of requests to your service by a given count per time.
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

The `limit-count` Plugin limits the number of requests to your service by a given count per time. The plugin is using Fixed Window algorithm.

## Attributes

| Name                    | Type    | Required                                  | Default       | Valid values                           | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ----------------------- | ------- | ----------------------------------------- | ------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| count                   | integer | True                                      |               | count > 0                              | Maximum number of requests to allow.                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| time_window             | integer | True                                      |               | time_window > 0                        | Time in seconds before `count` is reset.                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| key_type                | string  | False                                     | "var"         | ["var", "var_combination", "constant"] | Type of user specified key to use.                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| key                     | string  | False                                     | "remote_addr" |                                        | User specified key to base the request limiting on. If the `key_type` attribute is set to `constant`, the key will be treated as a constant value. If the `key_type` attribute is set to `var`, the key will be treated as a name of variable, like `remote_addr` or `consumer_name`. If the `key_type` is set to `var_combination`, the key will be a combination of variables, like `$remote_addr $consumer_name`. If the value of the key is empty, `remote_addr` will be set as the default key. |
| rejected_code           | integer | False                                     | 503           | [200,...,599]                          | HTTP status code returned when the requests exceeding the threshold are rejected.                                                                                                                                                                                                                                                                                                                                                                                                                    |
| rejected_msg            | string  | False                                     |               | non-empty                              | Body of the response returned when the requests exceeding the threshold are rejected.                                                                                                                                                                                                                                                                                                                                                                                                                |
| policy                  | string  | False                                     | "local"       | ["local", "redis", "redis-cluster"]    | Rate-limiting policies to use for retrieving and increment the limit count. When set to `local` the counters will be locally stored in memory on the node. When set to `redis` counters are stored on a Redis server and will be shared across the nodes. It is done usually for global speed limiting, and setting to `redis-cluster` uses a Redis cluster instead of a single instance.                                                                                                            |
| allow_degradation       | boolean | False                                     | false         |                                        | When set to `true` enables Plugin degradation when the Plugin is temporarily unavailable (for example, a Redis timeout) and allows requests to continue.                                                                                                                                                                                                                                                                                                                                             |
| show_limit_quota_header | boolean | False                                     | true          |                                        | When set to `true`, adds `X-RateLimit-Limit` (total number of requests) and `X-RateLimit-Remaining` (remaining number of requests) to the response header.                                                                                                                                                                                                                                                                                                                                           |
| group                   | string  | False                                     |               | non-empty                              | Group to share the counter with. Routes configured with the same group will share the same counter. Do not configure with a value that was previously used in this attribute before as the plugin would not allow.                                                                                                                                                                                                                                                                                                                                                                                                      |
| redis_host              | string  | required when `policy` is `redis`         |               |                                        | Address of the Redis server. Used when the `policy` attribute is set to `redis`.                                                                                                                                                                                                                                                                                                                                                                                                                     |
| redis_port              | integer | False                                     | 6379          | [1,...]                                | Port of the Redis server. Used when the `policy` attribute is set to `redis`.                                                                                                                                                                                                                                                                                                                                                                                                                        |
| redis_username          | string  | False                                     |               |                                        | Username for Redis authentication if Redis ACL is used (for Redis version >= 6.0). If you use the legacy authentication method `requirepass` to configure Redis password, configure only the `redis_password`. Used when the `policy` is set to `redis`.                                                                                                                                                                                                                                                                                                                                                                                                           |
| redis_password          | string  | False                                     |               |                                        | Password for Redis authentication. Used when the `policy` is set to `redis` or `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                                                                           |
| redis_ssl               | boolean | False                                     | false         |                                        | If set to `true`, then uses SSL to connect to redis instance. Used when the `policy` attribute is set to `redis`.                                                                                                                                                                                                                                                                                                                                                                                                           |
| redis_ssl_verify        | boolean | False                                     | false         |                                        | If set to `true`, then verifies the validity of the server SSL certificate. Used when the `policy` attribute is set to `redis`. See [tcpsock:sslhandshake](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake).                                                                                                                                                                                                                                                                                                                                                                                                          |
| redis_database          | integer | False                                     | 0             | redis_database >= 0                    | Selected database of the Redis server (for single instance operation or when using Redis cloud with a single entrypoint). Used when the `policy` attribute is set to `redis`.                                                                                                                                                                                                                                                                                                                        |
| redis_timeout           | integer | False                                     | 1000          | [1,...]                                | Timeout in milliseconds for any command submitted to the Redis server. Used when the `policy` attribute is set to `redis` or `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                        |
| redis_cluster_nodes     | array   | required when `policy` is `redis-cluster` |               |                                        | Addresses of Redis cluster nodes. Used when the `policy` attribute is set to `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                                                                        |
| redis_cluster_name      | string  | required when `policy` is `redis-cluster` |               |                                        | Name of the Redis cluster service nodes. Used when the `policy` attribute is set to `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                                                                 |
| redis_cluster_ssl      | boolean  |  False |     false         |                                        | If set to `true`, then uses SSL to connect to redis-cluster. Used when the `policy` attribute is set to `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                                                                 |
| redis_cluster_ssl_verify      | boolean  | False |    false      |                                        | If set to `true`, then verifies the validity of the server SSL certificate. Used when the `policy` attribute is set to `redis-cluster`.                                                                                                                                                                                                                                                                                                                                                                                                 |

## Enable Plugin

You can enable the Plugin on a Route as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
 admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:9001": 1
        }
    }
}'
```

You can also configure the `key_type` to `var_combination` as shown:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key_type": "var_combination",
            "key": "$consumer_name $remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:9001": 1
        }
    }
}'
```

You can also create a group to share the same counter across multiple Routes:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/services/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "limit-count": {
            "count": 1,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "group": "services_1#1640140620"
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

Now every Route which belongs to group `services_1#1640140620` (or the service with ID `1`) will share the same counter.

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "service_id": "1",
    "uri": "/hello"
}'
```

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/2 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "service_id": "1",
    "uri": "/hello2"
}'
```

```shell
curl -i http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 200 ...
```

You can also share the same limit counter for all your requests by setting the `key_type` to `constant`:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/services/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "limit-count": {
            "count": 1,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "key_type": "constant",
            "group": "services_1#1640140621"
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

The above configuration means that when the `group` attribute of the `limit-count` plugin is configured to `services_1#1640140620` for multiple routes, requests to those routes will share the same counter, even if the requests come from different IP addresses.

:::note

The configuration of `limit-count` in the same `group` must be consistent. If you want to change the configuration, you need to update the value of the corresponding `group` at the same time.

:::

For cluster-level traffic limiting, you can use a Redis server. The counter will be shared between different APISIX nodes to achieve traffic limiting.

The example below shows how you can use the `redis` policy:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "policy": "redis",
            "redis_host": "127.0.0.1",
            "redis_port": 6379,
            "redis_password": "password",
            "redis_database": 1,
            "redis_timeout": 1001
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

Similarly you can also configure the `redis-cluster` policy:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "policy": "redis-cluster",
            "redis_cluster_nodes": [
              "127.0.0.1:5000",
              "127.0.0.1:5001"
            ],
            "redis_password": "password",
            "redis_cluster_name": "redis-cluster-1"
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

In addition, you can use APISIX secret to store and reference plugin attributes. APISIX currently supports storing secrets in two ways - [Environment Variables and HashiCorp Vault](../terminology/secret.md). For example, in
case you have environment variables `REDIS_HOST` and `REDIS_PASSWORD` set, you can use them in the plugin configuration as shown below:

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr",
            "policy": "redis",
            "redis_host": "$ENV://REDIS_HOST",
            "redis_port": 6379,
            "redis_password": "$ENV://REDIS_PASSWORD",
            "redis_database": 1,
            "redis_timeout": 1001
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

## Example usage

The above configuration limits to 2 requests in 60 seconds. The first two requests will work and the response headers will contain the headers `X-RateLimit-Limit` and `X-RateLimit-Remaining` and `X-RateLimit-Reset`, represents the total number of requests that are limited, the number of requests that can still be sent, and the number of seconds left for the counter to reset:

```shell
curl -i http://127.0.0.1:9080/index.html
```

```shell
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 58
Server: APISIX web server
```

When you visit for a third time in the 60 seconds, you will receive a response with 503 code. Currently, in the case of rejection, the limit count headers is also returned:

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 58
Server: APISIX web server
```

You can also set a custom response by configuring the `rejected_msg` attribute:

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 58
Server: APISIX web server

{"error_msg":"Requests are too frequent, please try again later."}
```

## Delete Plugin

To remove the `limit-count` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
