---
title: limit-count
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

## Summary

- [Name](#name)
- [Attributes](#attributes)
- [How To Enable](#how-to-enable)
- [Test Plugin](#test-plugin)
- [Disable Plugin](#disable-plugin)

## Name

Limit request rate by a fixed number of requests in a given time window.

## Attributes

| Name                | Type    | Requirement                             | Default       | Valid                                                                                                   | Description                                                                                                                                                                                                                                                                                                |
| ------------------- | ------- | --------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| count               | integer | required                                |               | count > 0                                                                                               | the specified number of requests threshold.                                                                                                                                                                                                                                                                |
| time_window         | integer | required                    |               | time_window > 0                                                                                         | the time window in seconds before the request count is reset.                                                                                                                                                                                                                                              |
| key                 | string  | optional                                | "remote_addr" | ["remote_addr", "server_addr", "http_x_real_ip", "http_x_forwarded_for", "consumer_name", "service_id"] | The user specified key to limit the count. <br /> Now accept those as key: "remote_addr"(client's IP), "server_addr"(server's IP), "X-Forwarded-For/X-Real-IP" in request header, "consumer_name"(consumer's username) and "service_id".                                                                   |
| rejected_code       | integer | optional                                | 503           | [200,...,599]                                                                                           | The HTTP status code returned when the request exceeds the threshold is rejected, default 503.                                                                                                                                                                                                             |
| policy              | string  | optional                                | "local"       | ["local", "redis", "redis-cluster"]                                                                     | The rate-limiting policies to use for retrieving and incrementing the limits. Available values are `local`(the counters will be stored locally in-memory on the node) and `redis`(counters are stored on a Redis server and will be shared across the nodes, usually use it to do the global speed limit). |
| redis_host          | string  | required for `redis`                    |               |                                                                                                         | When using the `redis` policy, this property specifies the address of the Redis server.                                                                                                                                                                                                                    |
| redis_port          | integer | optional                                | 6379          | [1,...]                                                                                                 | When using the `redis` policy, this property specifies the port of the Redis server.                                                                                                                                                                                                                       |
| redis_password      | string  | optional                                |               |                                                                                                         | When using the `redis` policy, this property specifies the password of the Redis server.                                                                                                                                                                                                                   |
| redis_database      | integer | optional                                | 0             | redis_database >= 0                                                                                     | When using the `redis` policy, this property specifies the database you selected of the Redis server, and only for non Redis cluster mode (single instance mode or Redis public cloud service that provides single entry).                                                                               |
| redis_timeout       | integer | optional                                | 1000          | [1,...]                                                                                                 | When using the `redis` policy, this property specifies the timeout in milliseconds of any command submitted to the Redis server.                                                                                                                                                                           |
| redis_cluster_nodes | array   | required when policy is `redis-cluster` |               |                                                                                                         | When using `redis-cluster` policy，This property is a list of addresses of Redis cluster service nodes (at least two).                                                                                                                                                                                                    |
| redis_cluster_name  | string  | required when policy is `redis-cluster` |               |                                                                                                         | When using `redis-cluster` policy, this property is the name of Redis cluster service nodes.                                                                                                                                                                                                                   |

**Key can be customized by the user, only need to modify a line of code of the plug-in to complete. It is a security consideration that is not open in the plugin.**

## How To Enable

Here's an example, enable the `limit count` plugin on the specified route:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

You can open dashboard with a browser: `http://127.0.0.1:9080/apisix/dashboard/`, to complete the above operation through the web interface, first add a route:
![Add a router.](../../../assets/images/plugin/limit-count-1.png)

Then add limit-count plugin:
![Add limit-count plugin.](../../../assets/images/plugin/limit-count-2.png)

If you need a cluster-level precision traffic limit, then we can do it with the redis server. The rate limit of the traffic will be shared between different APISIX nodes to limit the rate of cluster traffic.

Here is the example if we use single `redis` policy:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
            "39.97.63.215:80": 1
        }
    }
}'
```

If using `redis-cluster` policy:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
            "39.97.63.215:80": 1
        }
    }
}'
```

## Test Plugin

The above configuration limits access to only 2 times in 60 seconds. The first two visits will be normally:

```shell
curl -i http://127.0.0.1:9080/index.html
```

The response header contains `X-RateLimit-Limit` and `X-RateLimit-Remaining`,
which mean the total number of requests and the remaining number of requests that can be sent:

```shell
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 0
Server: APISIX web server
```

When you visit for the third time, you will receive a response with the 503 HTTP code:

```shell
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

This means that the `limit count` plugin is in effect.

## Disable Plugin

When you want to disable the `limit count` plugin, it is very simple,
you can delete the corresponding json configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

The `limit count` plugin has been disabled now. It works for other plugins.
