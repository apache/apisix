---
title: limit-req
keywords:
  - Apache APISIX
  - API Gateway
  - Limit Request
  - limit-req
description: The limit-req Plugin limits the number of requests to your service using the leaky bucket algorithm.
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

The `limit-req` Plugin limits the number of requests to your service using the [leaky bucket](https://en.wikipedia.org/wiki/Leaky_bucket) algorithm.

## Attributes

| Name                     | Type    | Required | Default     | Valid values                      | Description                                                                                                                                                                                                                                                                                                                                                                                           |
|--------------------------|---------| -------- |-------------|-----------------------------------| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| conn                     | integer | True     |             | conn > 0                          | Maximum number of concurrent requests allowed. Requests exceeding this ratio (and below `conn` + `burst`) will be delayed (configured by `default_conn_delay`).                                                                                                                                                                                                                                       |
| burst                    | integer | True     |             | burst >= 0                        | Number of additional concurrent requests allowed to be delayed per second. If the number exceeds this hard limit, they will get rejected immediately.                                                                                                                                                                                                                                                 |
| default_conn_delay       | number  | True     |             | default_conn_delay > 0            | Delay in seconds to process the concurrent requests exceeding `conn` (and `conn` + `burst`).                                                                                                                                                                                                                                                                                                          |
| only_use_default_delay   | boolean | False    | false       | [true,false]                      | When set to `true`, the Plugin will always set a delay of `default_conn_delay` and would not use any other calculations.                                                                                                                                                                                                                                                                              |
| key_type                 | string  | False    | "var"       | ["var", "var_combination"]        | Type of user specified key to use.                                                                                                                                                                                                                                                                                                                                                                    |
| key                      | string  | True     |             |                                   | User specified key to base the request limiting on. If the `key_type` attribute is set to `"var"`, the key will be treated as a name of variable, like `remote_addr` or `consumer_name`. If the `key_type` is set to `"var_combination"`, the key will be a combination of variables, like `$remote_addr $consumer_name`. If the value of the key is empty, `remote_addr` will be set as the default key. |
| rejected_code            | string  | False    | 503         | [200,...,599]                     | HTTP status code returned when the requests exceeding the threshold are rejected.                                                                                                                                                                                                                                                                                                                     |
| rejected_msg             | string  | False    |             | non-empty                         | Body of the response returned when the requests exceeding the threshold are rejected.                                                                                                                                                                                                                                                                                                                 |
| allow_degradation        | boolean | False    | false       |                                   | When set to `true` enables Plugin degradation when the Plugin is temporarily unavailable and allows requests to continue.                                                                                                                                                                                                                                                                             |
| policy                  | string  | False                                     | "local"       | ["local", "redis", "redis-cluster"]    | Rate-limiting policies to use for retrieving and increment the limit count. When set to `local` the counters will be locally stored in memory on the node. When set to `redis` counters are stored on a Redis server and will be shared across the nodes. It is done usually for global speed limiting, and setting to `redis-cluster` uses a Redis cluster instead of a single instance.                                                                                                            |
| redis_host               | string  | required when `policy` is `redis`         |             |                                   | Address of the Redis server. Used when the `policy` attribute is set to `redis`.                                                                                                                                                                                                                                                                                                                    |
| redis_port               | integer | False                                     | 6379        | [1,...]                           | Port of the Redis server. Used when the `policy` attribute is set to `redis`.                                                                                                                                                                                                                                                                                                                       |
| redis_username           | string  | False                                     |             |                                   | Username for Redis authentication if Redis ACL is used (for Redis version >= 6.0). If you use the legacy authentication method `requirepass` to configure Redis password, configure only the `redis_password`. Used when the `policy` is set to `redis`.                                                                                                                                                  |
| redis_password           | string  | False                                     |             |                                   | Password for Redis authentication. Used when the `policy` is set to `redis` or `redis-cluster`.                                                                                                                                                                                                                                                                                                     |
| redis_ssl                | boolean | False                                     | false       |                                   | If set to `true`, then uses SSL to connect to redis instance. Used when the `policy` attribute is set to `redis`.                                                                                                                                                                                                                                                                                   |
| redis_ssl_verify         | boolean | False                                     | false       |                                   | If set to `true`, then verifies the validity of the server SSL certificate. Used when the `policy` attribute is set to `redis`. See [tcpsock:sslhandshake](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake).                                                                                                                                                                      |
| redis_database           | integer | False                                     | 0           | redis_database >= 0               | Selected database of the Redis server (for single instance operation or when using Redis cloud with a single entrypoint). Used when the `policy` attribute is set to `redis`.                                                                                                                                                                                                                       |
| redis_timeout            | integer | False                                     | 1000        | [1,...]                           | Timeout in milliseconds for any command submitted to the Redis server. Used when the `policy` attribute is set to `redis` or `redis-cluster`.                                                                                                                                                                                                                                                       |
| redis_cluster_nodes      | array   | required when `policy` is `redis-cluster` |             |                                   | Addresses of Redis cluster nodes. Used when the `policy` attribute is set to `redis-cluster`.                                                                                                                                                                                                                                                                                                       |
| redis_cluster_name       | string  | required when `policy` is `redis-cluster` |             |                                   | Name of the Redis cluster service nodes. Used when the `policy` attribute is set to `redis-cluster`.                                                                                                                                                                                                                                                                                                |
| redis_cluster_ssl        | boolean |  False | false       |                                   | If set to `true`, then uses SSL to connect to redis-cluster. Used when the `policy` attribute is set to `redis-cluster`.                                                                                                                                                                                                                                                                            |
| redis_cluster_ssl_verify | boolean | False | false       |                                   | If set to `true`, then verifies the validity of the server SSL certificate. Used when the `policy` attribute is set to `redis-cluster`.                                                                                                                                                                                                                                                             |

## Enable Plugin

You can enable the Plugin on a Route as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "limit-req": {
            "rate": 1,
            "burst": 2,
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

```json
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "limit-req": {
            "rate": 1,
            "burst": 2,
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
}
```

You can also configure the Plugin on specific consumers to limit their requests.

First, you can create a Consumer and enable the `limit-req` Plugin on it:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "consumer_jack",
    "plugins": {
        "key-auth": {
            "key": "auth-jack"
        },
        "limit-req": {
            "rate": 1,
            "burst": 3,
            "rejected_code": 403,
            "key": "consumer_name"
        }
    }
}'
```

In this example, the [key-auth](./key-auth.md) Plugin is used to authenticate the Consumer.

Next, create a Route and enable the `key-auth` Plugin:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "key-auth": {
            "key": "auth-jack"
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

Once you have configured the Plugin as shown above, you can test it out. The above configuration limits to 1 request per second. If the number of requests is greater than 1 but less than 3, a delay will be added. And if the number of requests per second exceeds 3, it will be rejected.

Now if you send a request:

```shell
curl -i http://127.0.0.1:9080/index.html
```

For authenticated requests:

```shell
curl -i http://127.0.0.1:9080/index.html -H 'apikey: auth-jack'
```

If you exceed the limit, you will receive a response with a 503 code:

```html
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
Server: APISIX web server

<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

You can set a custom rejected message by configuring the `rejected_msg` attribute. You will then receive a response like:

```shell
HTTP/1.1 503 Service Temporarily Unavailable
Content-Type: text/html
Content-Length: 194
Connection: keep-alive
Server: APISIX web server

{"error_msg":"Requests are too frequent, please try again later."}
```

## Delete Plugin

To remove the `limit-req` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

Similarly for removing the Plugin from a Consumer:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "consumer_jack",
    "plugins": {
        "key-auth": {
            "key": "auth-jack"
        }
    }
}'
```
