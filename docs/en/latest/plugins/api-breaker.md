---
title: api-breaker
keywords:
  - Apache APISIX
  - API Gateway
  - API Breaker
description: This document describes the information about the Apache APISIX api-breaker Plugin, you can use it to protect Upstream services.
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

This plugin supports two circuit breaker policies:

- **Failure count-based circuit breaking (`unhealthy-count`)**: Triggers circuit breaker when consecutive failure count reaches the threshold
- **Error ratio-based circuit breaking (`unhealthy-ratio`)**: Triggers circuit breaker when error rate within a sliding time window reaches the threshold

:::note

**Failure count-based circuit breaking (`unhealthy-count`)**:

Whenever the Upstream service responds with a status code from the configured `unhealthy.http_statuses` list for the configured `unhealthy.failures` number of times, the Upstream service will be considered unhealthy.

The request is then retried in 2, 4, 8, 16 ... seconds until the `max_breaker_sec`.

In an unhealthy state, if the Upstream service responds with a status code from the configured list `healthy.http_statuses` for `healthy.successes` times, the service is considered healthy again.

**Error ratio-based circuit breaking (`unhealthy-ratio`)**:

This policy is based on sliding time window statistics for error rate. When the total number of requests reaches `min_request_threshold` and the error rate exceeds `error_ratio` within the `sliding_window_size` time window, the circuit breaker enters the open state for `max_breaker_sec` seconds.

The circuit breaker has three states:

- **CLOSED**: Normal request forwarding
- **OPEN**: Directly returns circuit breaker response without forwarding requests
- **HALF_OPEN**: Allows a limited number of requests to test if the service has recovered

:::

## Attributes

| Name                    | Type           | Required | Default | Valid values    | Description                                                                                                                                                                                                                                  |
|-------------------------|----------------|----------|---------|-----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| break_response_code     | integer        | True     |         | [200, ..., 599] | HTTP error code to return when Upstream is unhealthy.                                                                                                                                                                                        |
| break_response_body     | string         | False    |         |                 | Body of the response message to return when Upstream is unhealthy.                                                                                                                                                                           |
| break_response_headers  | array[object]  | False    |         | [{"key":"header_name","value":"can contain Nginx $var"}] | Headers of the response message to return when Upstream is unhealthy. Can only be configured when the `break_response_body` attribute is configured. The values can contain APISIX variables. For example, we can use `{"key":"X-Client-Addr","value":"$remote_addr:$remote_port"}`. |
| max_breaker_sec         | integer        | False    | 300     | >=3             | Maximum time in seconds for circuit breaking. Applies to both circuit breaker policies.                                                                                                                                                                                                |
| policy                  | string         | False    | "unhealthy-count" | ["unhealthy-count", "unhealthy-ratio"] | Circuit breaker policy. `unhealthy-count` for failure count-based circuit breaking, `unhealthy-ratio` for error ratio-based circuit breaking. |

### Failure count-based circuit breaking (policy = "unhealthy-count")

| Name                    | Type           | Required | Default | Valid values    | Description                                                                                                                                                                                                                                  |
|-------------------------|----------------|----------|---------|-----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| unhealthy.http_statuses | array[integer] | False    | [500]   | [500, ..., 599] | Status codes of Upstream to be considered unhealthy.                                                                                                                                                                                         |
| unhealthy.failures      | integer        | False    | 3       | >=1             | Number of failures within a certain period of time for the Upstream service to be considered unhealthy.                                                                                                                                                          |
| healthy.http_statuses   | array[integer] | False    | [200]   | [200, ..., 499] | Status codes of Upstream to be considered healthy.                                                                                                                                                                                           |
| healthy.successes       | integer        | False    | 3       | >=1             | Number of consecutive healthy requests for the Upstream service to be considered healthy.                                                                                                                                                    |

### Error ratio-based circuit breaking (policy = "unhealthy-ratio")

| Name                    | Type           | Required | Default | Valid values    | Description                                                                                                                                                                                                                                  |
|-------------------------|----------------|----------|---------|-----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| unhealthy.http_statuses | array[integer] | False    | [500]   | [500, ..., 599] | Status codes of Upstream to be considered unhealthy.                                                                                                                                                                                         |
| unhealthy.error_ratio   | number         | False    | 0.5     | [0, 1]          | Error rate threshold to trigger circuit breaker. For example, 0.5 means circuit breaker triggers when error rate reaches 50%.                                                                                                                                                    |
| unhealthy.min_request_threshold | integer | False    | 10      | >=1             | Minimum number of requests required within the sliding window to trigger circuit breaker. Circuit breaker will only evaluate error rate when request count reaches this threshold.                                                                                                                                                          |
| unhealthy.sliding_window_size | integer   | False    | 300     | [10, 3600]      | Size of the sliding window in seconds. The time range used to calculate error rate.                                                                                                                                                                                |
| unhealthy.half_open_max_calls | integer | False | 3 | [1, 20] | Number of permitted calls when circuit breaker is in half-open state. Used to test if the service has recovered.                                                                                    |
| healthy.http_statuses   | array[integer] | False    | [200]   | [200, ..., 499] | Status codes of Upstream to be considered healthy.                                                                                                                                                           |
| healthy.success_ratio   | number         | False    | 0.6     | [0, 1]          | Success rate threshold to close circuit breaker from half-open state. For example, 0.6 means circuit breaker closes when success rate reaches 60%.                                                                                    |

## Enable Plugin

### Failure count-based circuit breaking example

The example below shows how you can configure the Plugin with failure count-based circuit breaking policy on a specific Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "api-breaker": {
            "break_response_code": 502,
            "policy": "unhealthy-count",
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
    "uri": "/hello"
}'
```

In this configuration, a response code of `500` or `503` three times within a certain period of time triggers the unhealthy status of the Upstream service. A response code of `200` restores its healthy status.

### Error ratio-based circuit breaking example

The example below shows how to enable error ratio-based circuit breaking policy. This configuration triggers circuit breaker when the request count reaches 10 and error rate exceeds 50% within a 5-minute sliding window:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/2" \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "api-breaker": {
            "break_response_code": 503,
            "break_response_body": "Service temporarily unavailable due to high error rate",
            "break_response_headers": [
                {"key": "X-Circuit-Breaker", "value": "open"},
                {"key": "Retry-After", "value": "60"}
            ],
            "policy": "unhealthy-ratio",
            "max_breaker_sec": 60,
            "unhealthy": {
                "http_statuses": [500, 502, 503, 504],
                "error_ratio": 0.5,
                "min_request_threshold": 10,
                "sliding_window_size": 300,
                "half_open_max_calls": 3
            },
            "healthy": {
                "http_statuses": [200, 201, 202],
                "success_ratio": 0.6
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "uri": "/api"
}'
```

## Example usage

Once you have configured the Plugin as shown above, you can test it out by sending a request.

```shell
curl -i -X POST "http://127.0.0.1:9080/hello"
```

If the Upstream service responds with an unhealthy response code, you will receive the configured response code (`break_response_code`).

```shell
HTTP/1.1 502 Bad Gateway
...
<html>
<head><title>502 Bad Gateway</title></head>
<body>
<center><h1>502 Bad Gateway</h1></center>
<hr><center>openresty</center>
</body>
</html>
```

## Delete Plugin

To remove the `api-breaker` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
