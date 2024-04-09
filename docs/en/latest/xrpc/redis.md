---
title: redis
keywords:
  - Apache APISIX
  - API Gateway
  - xRPC
  - redis
description: This document contains information about the Apache APISIX xRPC implementation for Redis.
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

The Redis protocol support allows APISIX to proxy Redis commands, and provide various features according to the content of the commands, including:

* [Redis protocol](https://redis.io/docs/reference/protocol-spec/) codec
* Fault injection according to the commands and key

:::note

This feature requires APISIX to be run on [APISIX-Runtime](../FAQ.md#how-do-i-build-the-apisix-runtime-environment).

It also requires the data sent from clients are well-formed and sane. Therefore, it should only be used in deployments where both the downstream and upstream are trusted.

:::

## Granularity of the request

Like other protocols based on the xRPC framework, the Redis implementation here also has the concept of `request`.

Each Redis command is considered a request. However, the message subscribed from the server won't be considered a request.

For example, when a Redis client subscribes to channel `foo` and receives the message `bar`, then it unsubscribes the `foo` channel, there are two requests: `subscribe foo` and `unsubscribe foo`.

## Attributes

| Name | Type          | Required | Default                                       | Valid values                                                       | Description                                                                                                                                                                                                                                           |
|----------------------------------------------|---------------|----------|-----------------------------------------------|--------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| faults | array[object]        | False    |                                               |  | Fault injections which can be applied based on the commands and keys |

Fields under an entry of `faults`:

| Name | Type          | Required | Default                                       | Valid values                                                       | Description                                                                                                                                                                                                                                           |
|----------------------------------------------|---------------|----------|-----------------------------------------------|--------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| commands | array[string]        | True    |                                               | ["get", "mget"]  | Commands fault is restricted to |
| key | string        | False    |                                               | "blahblah"  | Key fault is restricted to |
| delay | number        | True    |                                               | 0.1  | Duration of the delay in seconds |

## Metrics

* `apisix_redis_commands_total`: Total number of requests for a specific Redis command.

    | Labels        | Description             |
    | ------------- | --------------------    |
    | route         | matched stream route ID |
    | command       | the Redis command       |

* `apisix_redis_commands_latency_seconds`: Latency of requests for a specific Redis command.

    | Labels        | Description             |
    | ------------- | --------------------    |
    | route         | matched stream route ID |
    | command       | the Redis command       |

## Example usage

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

Assumed the APISIX is proxying TCP on port `9101`, and the Redis is listening on port `6379`.

Let's create a Stream Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
        "type": "none",
        "nodes": {
            "127.0.0.1:6379": 1
        }
    },
    "protocol": {
        "name": "redis",
        "conf": {
            "faults": [{
                "commands": ["get", "ping"],
                "delay": 5
            }]
        }
    }
}
'
```

Once you have configured the stream route, as shown above, you can make a request to it:

```shell
redis-cli -p 9101
```

```
127.0.0.1:9101> ping
PONG
(5.00s)
```

You can notice that there is a 5 seconds delay for the ping command.
