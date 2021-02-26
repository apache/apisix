---
title: api-breaker
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

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

The plugin implements API fuse functionality to help us protect our upstream business services.

> About the breaker timeout logic

the code logic automatically **triggers the unhealthy state** incrementation of the number of operations.

Whenever the upstream service returns a status code from the `unhealthy.http_statuses` configuration (e.g., 500), up to `unhealthy.failures` (e.g., three times) and considers the upstream service to be in an unhealthy state.

The first time unhealthy status is triggered, **breaken for 2 seconds**.

Then, the request is forwarded to the upstream service again after 2 seconds, and if the `unhealthy.http_statuses` status code is returned, and the count reaches `unhealthy.failures` again, **broken for 4 seconds**.

and so on, 2, 4, 8, 16, 32, 64, ..., 256, 300. `300` is the maximum value of `max_breaker_sec`, allow users to specify.

In an unhealthy state, when a request is forwarded to an upstream service and the status code in the `healthy.http_statuses` configuration is returned (e.g., 200) that `healthy.successes` is reached (e.g., three times), and the upstream service is considered healthy again.

## Attributes

| Name                    | Type          | Requirement | Default | Valid            | Description                                                                 |
| ----------------------- | ------------- | ----------- | -------- | --------------- | --------------------------------------------------------------------------- |
| break_response_code     | integer        | required |            | [200, ..., 599] | Return error code when unhealthy |
| max_breaker_sec         | integer        | optional | 300        | >=60            | Maximum breaker time(seconds) |
| unhealthy.http_statuses | array[integer] | optional | {500}      | [500, ..., 599] | Status codes when unhealthy |
| unhealthy.failures      | integer        | optional | 3          | >=1             | Number of consecutive error requests that triggered an unhealthy state |
| healthy.http_statuses   | array[integer] | optional | {200}      | [200, ..., 499] | Status codes when healthy |
| healthy.successes       | integer        | optional | 3          | >=1             | Number of consecutive normal requests that trigger health status |

## How To Enable

Here's an example, enable the `api-breaker` plugin on the specified route.

Response 500 or 503 three times in a row to trigger a unhealthy. Response 200 once in a row to restore healthy.

```shell
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "api-breaker": {
            "break_response_code": 502,
            "unhealthy": {
                "http_statuses": [500, 503],
                "failures": 3
            },
            "healthy": {
                "http_statuses": [200],
                "successes": 1
            }
        }
    },
    "uri": "/hello",
    "host": "127.0.0.1",
}'
```

## Test Plugin

Then. Like the configuration above, if your upstream service returns 500. 3 times in a row. The client will receive a 502 (break_response_code) response.

```shell
$ curl -i -X POST "http://127.0.0.1:9080/get"
HTTP/1.1 502 Bad Gateway
Content-Type: application/octet-stream
Connection: keep-alive
Server: APISIX/1.5

... ...
```

## Disable Plugin

When you want to disable the `api-breader` plugin, it is very simple, you can delete the corresponding json configuration in the plugin configuration, no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

The `api-breaker` plugin has been disabled now. It works for other plugins.
