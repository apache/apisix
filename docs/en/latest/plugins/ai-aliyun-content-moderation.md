---
title: ai-aliyun-content-moderation
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-aliyun-content-moderation
description: This document contains information about the Apache APISIX ai-aliyun-content-moderation Plugin.
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

The `ai-aliyun-content-moderation` plugin integrates with Aliyun's content moderation service to check both request and response content for inappropriate material when working with LLMs. It supports both real-time streaming checks and final packet moderation.

This plugin must be used in routes that utilize the ai-proxy or ai-proxy-multi plugins.

## Plugin Attributes

| **Field**                   | **Required** | **Type**  | **Description**                                                                                                                                                             |
| ---------------------------- | ------------ | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| endpoint                     | Yes          | String    | Aliyun service endpoint URL                                                                                                                                                 |
| region_id                    | Yes          | String    | Aliyun region identifier                                                                                                                                                    |
| access_key_id                | Yes          | String    | Aliyun access key ID                                                                                                                                                        |
| access_key_secret            | Yes          | String    | Aliyun access key secret                                                                                                                                                    |
| check_request                | No           | Boolean   | Enable request content moderation. Default: `true`                                                                                                                          |
| check_response               | No           | Boolean   | Enable response content moderation. Default: `false`                                                                                                                        |
| stream_check_mode            | No           | String    | Streaming moderation mode. Default: `"final_packet"`. Valid values: `["realtime", "final_packet"]`                                                                           |
| stream_check_cache_size      | No           | Integer   | Max characters per moderation batch in realtime mode. Default: `128`. Must be `>= 1`.                                                                                        |
| stream_check_interval        | No           | Number    | Seconds between batch checks in realtime mode. Default: `3`. Must be `>= 0.1`.                                                                                              |
| request_check_service        | No           | String    | Aliyun service for request moderation. Default: `"llm_query_moderation"`                                                                                                    |
| request_check_length_limit   | No           | Number    | Max characters per request moderation chunk. Default: `2000`.                                                                                                               |
| response_check_service       | No           | String    | Aliyun service for response moderation. Default: `"llm_response_moderation"`                                                                                               |
| response_check_length_limit  | No           | Number    | Max characters per response moderation chunk. Default: `5000`.                                                                                                              |
| risk_level_bar               | No           | String    | Threshold for content rejection. Default: `"high"`. Valid values: `["none", "low", "medium", "high", "max"]`                                                                |
| deny_code                    | No           | Number    | HTTP status code for rejected content. Default: `200`.                                                                                                                      |
| deny_message                 | No           | String    | Custom message for rejected content. Default: `-`.                                                                                                                           |
| timeout                      | No           | Integer   | Request timeout in milliseconds. Default: `10000`. Must be `>= 1`.                                                                                                          |
| ssl_verify                   | No           | Boolean   | Enable SSL certificate verification. Default: `true`.                                                                                                                       |

## Example usage

First initialise these shell variables:

```shell
ADMIN_API_KEY=edd1c9f034335f136f87ad84b625c8f1
ALIYUN_ACCESS_KEY_ID=your-aliyun-access-key-id
ALIYUN_ACCESS_KEY_SECRET=your-aliyun-access-key-secret
ALIYUN_REGION=cn-hangzhou
ALIYUN_ENDPOINT=https://green.cn-hangzhou.aliyuncs.com
OPENAI_KEY=your-openai-api-key
```

Create a route with the `ai-aliyun-content-moderation` and `ai-proxy` plugin like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/v1/chat/completions",
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_KEY"'"
          }
        },
        "override": {
          "endpoint": "http://localhost:6724/v1/chat/completions"
        }
      },
      "ai-aliyun-content-moderation": {
        "endpoint": "'"$ALIYUN_ENDPOINT"'",
        "region_id": "'"$ALIYUN_REGION"'",
        "access_key_id": "'"$ALIYUN_ACCESS_KEY_ID"'",
        "access_key_secret": "'"$ALIYUN_ACCESS_KEY_SECRET"'",
        "risk_level_bar": "high",
        "check_request": true,
        "check_response": true,
        "deny_code": 400,
        "deny_message": "Your request violates content policy"
      }
    }
  }'
```

The `ai-proxy` plugin is used here as it simplifies access to LLMs. However, you may configure the LLM in the upstream configuration as well.

Now send a request:

```shell
curl http://127.0.0.1:9080/v1/chat/completions -i \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "user", "content": "I want to kill you"}
    ],
    "stream": false
  }'
```

Then the request will be blocked with error like this:

```text
HTTP/1.1 400 Bad Request
Content-Type: application/json

{"id":"chatcmpl-123","object":"chat.completion","model":"gpt-3.5-turbo","choices":[{"index":0,"message":{"role":"assistant","content":"Your request violates content policy"},"finish_reason":"stop"}],"usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0}}
```
