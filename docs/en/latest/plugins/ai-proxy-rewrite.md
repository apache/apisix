---
title: ai-proxy-rewrite
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy-rewrite
description: This document contains information about the Apache APISIX ai-proxy-rewrite Plugin.
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

The `ai-proxy-rewrite` plugin extends `ai-proxy` by adding a prompt field, combining predefined prompts with client request data to send to LLM (like OpenAI), enabling intelligent transformation and rewriting of request data.


## Plugin Attributes

| **Field**                 | **Required** | **Type** | **Description**                                                                      |
| ------------------------- | ------------ | -------- | ------------------------------------------------------------------------------------ |
| prompt                    | Yes          | String   | The prompt send to LLM.                                                                |
| auth                      | Yes          | Object   | Authentication configuration                                                         |
| auth.header               | No           | Object   | Authentication headers. Key must match pattern `^[a-zA-Z0-9._-]+$`.                  |
| auth.query                | No           | Object   | Authentication query parameters. Key must match pattern `^[a-zA-Z0-9._-]+$`.         |
| model.provider            | Yes          | String   | Name of the AI service provider (`openai`).                                          |
| model.name                | Yes          | String   | Model name to execute.                                                               |
| model.options             | No           | Object   | Key/value settings for the model                                                     |
| model.options.max_tokens  | No           | Integer  | Defines the max tokens if using chat or completion models. Default: 256              |
| model.options.input_cost  | No           | Number   | Cost per 1M tokens in your prompt. Minimum: 0                                        |
| model.options.output_cost | No           | Number   | Cost per 1M tokens in the output of the AI. Minimum: 0                               |
| model.options.temperature | No           | Number   | Matching temperature for models. Range: 0.0 - 5.0                                    |
| model.options.top_p       | No           | Number   | Top-p probability mass. Range: 0 - 1                                                 |
| model.options.stream      | No           | Boolean  | Stream response by SSE.                                                              |
| override.endpoint         | No           | String   | Override the endpoint of the AI provider                                             |
| timeout                   | No           | Integer  | Timeout in milliseconds for requests to LLM. Range: 1 - 60000. Default: 3000         |
| keepalive                 | No           | Boolean  | Enable keepalive for requests to LLM. Default: true                                  |
| keepalive_timeout         | No           | Integer  | Keepalive timeout in milliseconds for requests to LLM. Minimum: 1000. Default: 60000 |
| keepalive_pool            | No           | Integer  | Keepalive pool size for requests to LLM. Minimum: 1. Default: 30                     |
| ssl_verify                | No           | Boolean  | SSL verification for requests to LLM. Default: true                                  |


## Example usage

Create a route with the `ai-proxy-rewrite` plugin like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-proxy-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., '*** **** **** 1234') for credit card numbers). Ensure the JSON structure remains unchanged.",
        "auth": {
          "header": {
            "Authorization": "Bearer <some-token>"
          }
        },
        "model": {
          "provider": "openai",
          "name": "gpt-4",
          "options": {
            "max_tokens": 512,
            "temperature": 1.0
          }
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "somerandom.com:443": 1
      },
      "scheme": "https",
      "pass_host": "node"
    }
  }'
```
Upstream node can be any arbitrary value because it won't be contacted.

Now send a request:

```shell
curl "http://127.0.0.1:9080/anything" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john.doe@example.com",
    "credit_card": "4111 1111 1111 1111",
    "ssn": "123-45-6789",
    "address": "123 Main St"
  }'
```

The request body for LLM is as follows:
```json
{
  "messages": [
     {
       "role": "system",
       "content": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., '*** **** **** 1234') for credit card numbers). Ensure the JSON structure remains unchanged."
     },
     {
       "role": "user",
       "content": "{\n\"name\":\"John Doe\",\n\"email\":\"john.doe@example.com\",\n\"credit_card\":\"4111 1111 1111 1111\",\n\"ssn\":\"123-45-6789\",\n\"address\":\"123 Main St\"\n}"
     }
   ]
}

```
You will receive a response like this:

```json
{
  "name": "John Doe",
  "email": "john.doe@example.com",
  "credit_card": "**** **** **** 1111",
  "ssn": "***-**-6789",
  "address": "123 Main St"
}
```

### Send request to an OpenAI compatible LLM

Create a route with the `ai-proxy-rewrite` plugin with `provider` set to `openai-compatible` and the endpoint of the model set to `override.endpoint` like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-proxy-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., '*** **** **** 1234') for credit card numbers). Ensure the JSON structure remains unchanged.",
        "auth": {
          "header": {
            "Authorization": "Bearer <some-token>"
          }
        },
        "model": {
          "provider": "openai-compatible",
          "name": "qwen-plus"
        },
        "override": {
          "endpoint": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "somerandom.com:443": 1
      },
      "scheme": "https",
      "pass_host": "node"
    }
  }'
```