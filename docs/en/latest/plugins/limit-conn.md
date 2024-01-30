---
title: limit-conn
keywords:
  - Apache APISIX
  - API Gateway
  - Limit Connection
description: This document contains information about the Apache APISIX limit-con Plugin, you can use it to limits the number of concurrent requests to your services.
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

The `limit-conn` Plugin limits the number of concurrent requests to your services.

## Attributes

| Name                     | Type    | Required | Default     | Valid values                      | Description                                                                                                                                                                                                                                                                                                                                                                                               |
|--------------------------|---------| -------- |-------------|-----------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| conn                     | integer | True     |             | conn > 0                          | Maximum number of concurrent requests allowed. Requests exceeding this ratio (and below `conn` + `burst`) will be delayed (configured by `default_conn_delay`).                                                                                                                                                                                                                                           |
| burst                    | integer | True     |             | burst >= 0                        | Number of additional concurrent requests allowed to be delayed per second. If the number exceeds this hard limit, they will get rejected immediately.                                                                                                                                                                                                                                                     |
| default_conn_delay       | number  | True     |             | default_conn_delay > 0            | Delay in seconds to process the concurrent requests exceeding `conn` (and `conn` + `burst`).                                                                                                                                                                                                                                                                                                              |
| only_use_default_delay   | boolean | False    | false       | [true,false]                      | When set to `true`, the Plugin will always set a delay of `default_conn_delay` and would not use any other calculations.                                                                                                                                                                                                                                                                                  |
| key_type                 | string  | False    | "var"       | ["var", "var_combination"]        | Type of user specified key to use.                                                                                                                                                                                                                                                                                                                                                                        |
| key                      | string  | True     |             |                                   | User specified key to base the request limiting on. If the `key_type` attribute is set to `"var"`, the key will be treated as a name of variable, like `remote_addr` or `consumer_name`. If the `key_type` is set to `"var_combination"`, the key will be a combination of variables, like `$remote_addr $consumer_name`. If the value of the key is empty, `remote_addr` will be set as the default key. |
| rejected_code            | string  | False    | 503         | [200,...,599]                     | HTTP status code returned when the requests exceeding the threshold are rejected.                                                                                                                                                                                                                                                                                                                         |
| rejected_msg             | string  | False    |             | non-empty                         | Body of the response returned when the requests exceeding the threshold are rejected.                                                                                                                                                                                                                                                                                                                     |
| allow_degradation        | boolean | False    | false       |                                   | When set to `true` enables Plugin degradation when the Plugin is temporarily unavailable and allows requests to continue.                                                                                                                                                                                                                                                                                 |
| policy             | string  | False    | local | local, redis, redis-cluster | counter type to choose local, redis or redis-cluster                                                                                                                                                                                                                                                                                                                                                |
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
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "rejected_code": 503,
            "key_type": "var",
            "key": "http_a"
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

You can also configure the `key_type` to `var_combination` as shown:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "rejected_code": 503,
            "key_type": "var_combination",
            "key": "$consumer_name $remote_addr"
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

The example above configures the Plugin to only allow one connection on this route. When more than one request is received, the Plugin will respond with a `503` HTTP status code and reject the connection:

```shell
curl -i http://127.0.0.1:9080/index.html?sleep=20 &

curl -i http://127.0.0.1:9080/index.html?sleep=20
```

```shell
<html>
<head><title>503 Service Temporarily Unavailable</title></head>
<body>
<center><h1>503 Service Temporarily Unavailable</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

## Delete Plugin

To remove the `limit-conn` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Example of application scenarios

### Limit the number of concurrent WebSocket connections

Apache APISIX supports WebSocket proxy, we can use `limit-conn` plugin to limit the number of concurrent WebSocket connections.

1. Create a Route, enable the WebSocket proxy and the `limit-conn` plugin.

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
    {
        "uri": "/ws",
        "enable_websocket": true,
        "plugins": {
            "limit-conn": {
                "conn": 1,
                "burst": 0,
                "default_conn_delay": 0.1,
                "rejected_code": 503,
                "key_type": "var",
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

    The above route enables the WebSocket proxy on `/ws`, and limits the number of concurrent WebSocket connections to 1. More than 1 concurrent WebSocket connection will return `503` to reject the request.

2. Initiate a WebSocket request, and the connection is established successfully.

    ```shell
    curl --include \
        --no-buffer \
        --header "Connection: Upgrade" \
        --header "Upgrade: websocket" \
        --header "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" \
        --header "Sec-WebSocket-Version: 13" \
        --http1.1 \
        http://127.0.0.1:9080/ws
    ```

    ```shell
    HTTP/1.1 101 Switching Protocols
    ```

3. Initiate the WebSocket request again in another terminal, the request will be rejected.

    ```shell
    HTTP/1.1 503 Service Temporarily Unavailable
    ···
    <html>
    <head><title>503 Service Temporarily Unavailable</title></head>
    <body>
    <center><h1>503 Service Temporarily Unavailable</h1></center>
    <hr><center>openresty</center>
    </body>
    </html>
    ```
