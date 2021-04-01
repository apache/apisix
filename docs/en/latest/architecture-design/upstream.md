---
title: Upstream
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

Upstream is a virtual host abstraction that performs load balancing on a given set of service nodes according to configuration rules. Upstream address information can be directly configured to `Route` (or `Service`). When Upstream has duplicates, you need to use "reference" to avoid duplication.

![upstream-example](../../../assets/images/upstream-example.png)

As shown in the image above, by creating an Upstream object and referencing it by ID in `Route`, you can ensure that only the value of an object is maintained.

Upstream configuration can be directly bound to the specified `Route` or it can be bound to `Service`, but the configuration in `Route` has a higher priority. The priority behavior here is very similar to `Plugin`.

### Configuration

In addition to the basic complex equalization algorithm selection, APISIX's Upstream also supports logic for upstream passive health check and retry, see [this link](../admin-api.md#upstream).

Create an upstream object use case:

```json
curl http://127.0.0.1:9080/apisix/admin/upstreams/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "type": "chash",
    "key": "remote_addr",
    "nodes": {
        "127.0.0.1:80": 1,
        "foo.com:80": 2
    }
}'
```

After the upstream object is created, it can be referenced by specific `Route` or `Service`, for example:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream_id": 1
}'
```

For convenience, you can also directly bind the upstream address to a `Route` or `Service`, for example:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Here's an example of configuring a health check:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
         "nodes": {
            "39.97.63.215:80": 1
        }
        "type": "roundrobin",
        "retries": 2,
        "checks": {
            "active": {
                "http_path": "/status",
                "host": "foo.com",
                "healthy": {
                    "interval": 2,
                    "successes": 1
                },
                "unhealthy": {
                    "interval": 1,
                    "http_failures": 2
                }
            }
        }
    }
}'
```

More details can be found in [Health Checking Documents](../health-check.md).

Here are some examples of configurations using different `hash_on` types:

#### Consumer

Create a consumer object:

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
       "key-auth": {
            "key": "auth-jack"
        }
    }
}'
```

Create route object and enable `key-auth` plugin authentication:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "key-auth": {}
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1,
            "127.0.0.1:1981": 1
        },
        "type": "chash",
        "hash_on": "consumer"
    },
    "uri": "/server_port"
}'
```

Test request, the `consumer_name` after authentication is passed will be used as the hash value of the load balancing hash algorithm:

```shell
curl http://127.0.0.1:9080/server_port -H "apikey: auth-jack"
```

#### Cookie

Create route and upstream object, `hash_on` is `cookie`:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hash_on_cookie",
    "upstream": {
        "key": "sid",
        "type ": "chash",
        "hash_on ": "cookie",
        "nodes ": {
            "127.0.0.1:1980": 1,
            "127.0.0.1:1981": 1
        }
    }
}'
```

The client requests with `Cookie`:

```shell
 curl http://127.0.0.1:9080/hash_on_cookie -H "Cookie: sid=3c183a30cffcda1408daf1c61d47b274"
```

#### Header

Create route and upstream object, `hash_on` is `header`, `key` is `Content-Type`:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hash_on_header",
    "upstream": {
        "key": "content-type",
        "type ": "chash",
        "hash_on ": "header",
        "nodes ": {
            "127.0.0.1:1980": 1,
            "127.0.0.1:1981": 1
        }
    }
}'
```

The client requests with header `Content-Type`:

```shell
 curl http://127.0.0.1:9080/hash_on_header -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -H "Content-Type: application/json"
```
