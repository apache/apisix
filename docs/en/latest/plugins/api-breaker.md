---
title: api-breaker
keywords:
  - APISIX
  - Plugin
  - API Breaker
  - api-breaker
description: This document contains information about the Apache APISIX api-breaker Plugin.
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

The `api-breaker` Plugin implements circuit breaker functionality to protect Upstream services.

Whenever the Upstream service responds with a status code from the configured `unhealthy.http_statuses` list for the configured `unhealthy.failures` number of times, the Upstream service will be considered unhealthy.

The request is then retried in 2, 4, 8, 16 ... seconds until the `max_breaker_sec`.

In an unhealthy state, if the Upstream service responds with a status code from the configured list `healthy.http_statuses` for `healthy.successes` times, the service is considered healthy again.

## Attributes

| Name                    | Type           | Required | Default | Valid values    | Description                                                                                                                                                                                                                                  |
|-------------------------|----------------|----------|---------|-----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| break_response_code     | integer        | True     |         | [200, ..., 599] | HTTP error code to return when Upstream is unhealthy.                                                                                                                                                                                        |
| break_response_body     | string         | False    |         |                 | Body of the response message to return when Upstream is unhealthy.                                                                                                                                                                           |
| break_response_headers  | array[object]  | False    |         |                 | Headers of the response message to return when Upstream is unhealthy. Can only be configured when the `break_response_body` attribute is configured. The values can contain Nginx variables. For example, `$remote_addr` and `$balancer_ip`. |
| max_breaker_sec         | integer        | False    | 300     | >=3             | Maximum time in seconds for circuit breaking.                                                                                                                                                                                                |
| unhealthy.http_statuses | array[integer] | False    | [500]   | [500, ..., 599] | Status codes of Upstream to be considered unhealthy.                                                                                                                                                                                         |
| unhealthy.failures      | integer        | False    | 3       | >=1             | Number of consecutive failures for the Upstream service to be considered unhealthy.                                                                                                                                                          |
| healthy.http_statuses   | array[integer] | False    | [200]   | [200, ..., 499] | Status codes of Upstream to be considered healthy.                                                                                                                                                                                           |
| healthy.successes       | integer        | False    | 3       | >=1             | Number of consecutive healthy requests for the Upstream service to be considered healthy.                                                                                                                                                    |

## Enabling the Plugin

The example below shows how you can configure the Plugin on a specific Route:

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
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "uri": "/hello",
}'
```

In this configuration, a response code of 500 or 503 three times in a row triggers the unhealthy status of the Upstream service. A response code of 200 restores its healthy status.

## Example usage

Once you have configured the Plugin as shown above, you can test it out by sending a request. If the Upstream service responds with an unhealthy response code, you will receive the configured response code (`break_response_code`).

```shell
curl -i -X POST "http://127.0.0.1:9080/hello"
```

```shell
HTTP/1.1 502 Bad Gateway
Content-Type: application/octet-stream
Connection: keep-alive
Server: APISIX/1.5

... ...
```

## Disable Plugin

To disable the `api-breaker` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
