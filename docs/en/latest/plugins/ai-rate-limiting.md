---
title: AI Rate Limiting
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-rate-limiting
description: The ai-rate-limiting plugin enforces token-based rate limiting for LLM service requests, preventing overuse, optimizing API consumption, and ensuring efficient resource allocation.
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

The `ai-rate-limiting` plugin enforces token-based rate limiting for requests sent to LLM services. It helps manage API usage by controlling the number of tokens consumed within a specified time frame, ensuring fair resource allocation and preventing excessive load on the service. It is often used with `ai-proxy` or `ai-proxy-multi` plugin.

## Plugin Attributes

| Name                      | Type          | Required | Description                                                                                                                                                                                                                                                                                   |
| ------------------------- | ------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `limit`                   | integer       | conditionally    | The maximum number of tokens allowed to consume within a given time interval. At least one of `limit` and `instances.limit` should be configured.                                                                                                                                             |
| `time_window`             | integer       | conditionally    | The time interval corresponding to the rate limiting `limit` in seconds. At least one of `time_window` and `instances.time_window` should be configured.                                                                                                                                      |
| `show_limit_quota_header` | boolean       | false    | If true, include `X-AI-RateLimit-Limit-*` to show the total quota, `X-AI-RateLimit-Remaining-*` to show the remaining quota in the response header, and `X-AI-RateLimit-Reset-*` to show the number of seconds left for the counter to reset, where `*` is the instance name. Default: `true` |
| `limit_strategy`          | string        | false    | Type of token to apply rate limiting. `total_tokens`, `prompt_tokens`, and `completion_tokens` values are returned in each model response, where `total_tokens` is the sum of `prompt_tokens` and `completion_tokens`. Default: `total_tokens`                                                |
| `instances`               | array[object] | conditionally    | LLM instance rate limiting configurations.                                                                                                                                                                                                                                                    |
| `instances.name`          | string        | true     | Name of the LLM service instance.                                                                                                                                                                                                                                                             |
| `instances.limit`         | integer       | true     | The maximum number of tokens allowed to consume within a given time interval.                                                                                                                                                                                                                 |
| `instances.time_window`   | integer       | true     | The time interval corresponding to the rate limiting `limit` in seconds.                                                                                                                                                                                                                      |
| `rejected_code`           | integer       | false    | The HTTP status code returned when a request exceeding the quota is rejected. Default: `503`                                                                                                                                                                                                  |
| `rejected_msg`            | string        | false    | The response body returned when a request exceeding the quota is rejected.                                                                                                                                                                                                                    |

If `limit` is configured, `time_window` also needs to be configured. Else, just specifying `instances` will also suffice.
## Example

Create a route as such and update with your LLM providers, models, API keys, and endpoints:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "ai-rate-limiting-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-35-turbo-instruct",
          "max_tokens": 512,
          "temperature": 1.0
        }
      },
      "ai-rate-limiting": {
        "limit": 300,
        "time_window": 30,
        "limit_strategy": "prompt_tokens"
      }
    }
  }'
```

Send a POST request to the route with a system prompt and a sample user question in the request body:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

You should receive a response similar to the following:

```json
{
  ...
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "1 + 1 equals 2. This is a fundamental arithmetic operation where adding one unit to another results in a total of two units."
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

If rate limiting quota of 300 tokens has been consumed in a 30-second window, the additional requests will all be rejected.
