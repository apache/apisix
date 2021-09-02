---
title: proxy-mirror
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

The proxy-mirror plugin, which provides the ability to mirror client requests.

*Note*: The response returned by the mirror request is ignored.

## Attributes

| Name | Type   | Requirement | Default | Valid | Description                                                                                                                 |
| ---- | ------ | ----------- | ------- | ----- | --------------------------------------------------------------------------------------------------------------------------- |
| host | string | required    |         |       | Specify a mirror service address, e.g. http://127.0.0.1:9797 (address needs to contain schema: http or https, not URI part) |
| enable_limit_count               | boolean | optional                                | false              |                                                                                                | Whether to enable the limit count of mirror requests.                                                                                                                                                                                                                                                                |
| count               | integer | optional                                | 1              | count > 0                                                                                               | the specified number of mirror requests threshold.                                                                                                                                                                                                                                                                |
| time_window         | integer | optional                    | 60              | time_window > 0                                                                                         | the time window in seconds before the mirror request count is reset.                                                                                                                                                                                                                                              |
| policy              | string  | optional                                | "local"       | ["local", "redis", "redis-cluster"]                                                                     | The mirror request limit count policies to use for retrieving and incrementing the limits. Available values are `local`(the counters will be stored locally in-memory on the node), `redis`(counters are stored on a Redis server and will be shared across the nodes, usually use it to do the global speed limit), and `redis-cluster` which works the same as `redis` but with redis cluster. |
| redis_host          | string  | required for `redis`                    |               |                                                                                                         | When using the `redis` policy, this property specifies the address of the Redis server.                                                                                                                                                                                                                    |
| redis_port          | integer | optional                                | 6379          | [1,...]                                                                                                 | When using the `redis` policy, this property specifies the port of the Redis server.                                                                                                                                                                                                                       |
| redis_password      | string  | optional                                |               |                                                                                                         | When using the `redis`  or `redis-cluster` policy, this property specifies the password of the Redis server.                                                                                                                                                                                                                   |
| redis_database      | integer | optional                                | 0             | redis_database >= 0                                                                                     | When using the `redis` policy, this property specifies the database you selected of the Redis server, and only for non Redis cluster mode (single instance mode or Redis public cloud service that provides single entry).                                                                               |
| redis_timeout       | integer | optional                                | 1000          | [1,...]                                                                                                 | When using the `redis`  or `redis-cluster` policy, this property specifies the timeout in milliseconds of any command submitted to the Redis server.                                                                                                                                                                           |
| redis_cluster_nodes | array   | required when policy is `redis-cluster` |               |                                                                                                         | When using `redis-cluster` policy，This property is a list of addresses of Redis cluster service nodes (at least two).                                                                                                                                                                                                    |
| redis_cluster_name  | string  | required when policy is `redis-cluster` |               |                                                                                                         | When using `redis-cluster` policy, this property is the name of Redis cluster service nodes.                                                                                                                                                                                                                   |

### Examples

#### Enable the plugin

example 1:  enable the proxy-mirror plugin for a specific route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-mirror": {
           "host": "http://127.0.0.1:9797"
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1999": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

Test plugin：

```shell
$ curl http://127.0.0.1:9080/hello -i
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 12
Connection: keep-alive
Server: APISIX web server
Date: Wed, 18 Mar 2020 13:01:11 GMT
Last-Modified: Thu, 20 Feb 2020 14:21:41 GMT

hello world
```

> Since the specified mirror address is 127.0.0.1:9797, so to verify whether this plugin is in effect, we need to confirm on the service with port 9797.
> For example, we can start a simple server:  python -m SimpleHTTPServer 9797

example 2:  enable the proxy-mirror plugin for a specific route and enable limit count for mirror requests:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "proxy-mirror": {
           "host": "http://127.0.0.1:9797",
            "enable_limit_count": true,
            "count": 2,
            "time_window": 60
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1999": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

In this case, only allow two mirror requests in 60 seconds.

## Disable Plugin

Remove the corresponding JSON in the plugin configuration to disable the plugin immediately without restarting the service:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1999": 1
        }
    }
}'
```

The plugin has been disabled now.
