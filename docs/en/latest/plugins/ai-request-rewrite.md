---
title: ai-request-rewrite
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-request-rewrite
description: This document contains information about the Apache APISIX ai-request-rewrite Plugin.
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

The `ai-request-rewrite` plugin leverages predefined prompts and AI services to intelligently modify client requests, enabling AI-powered content transformation before forwarding to upstream services.


## Plugin Attributes

| **Field**                 | **Required** | **Type** | **Description**                                                                      |
| ------------------------- | ------------ | -------- | ------------------------------------------------------------------------------------ |
| prompt                    | Yes          | String   | The prompt send to AI service.                                                              |
| provider                  | Yes          | String   | Type of the AI service.                                                     |
| auth                      | Yes          | Object   | Authentication configuration                                                         |
| auth.header               | No           | Object   | Authentication headers. Key must match pattern `^[a-zA-Z0-9._-]+$`.                  |
| auth.query                | No           | Object   | Authentication query parameters. Key must match pattern `^[a-zA-Z0-9._-]+$`.         |
| options                   | No           | Object   | Key/value settings for the model                                                     |
| options.model             | No           | String   | Model to execute.                                                                    |
| override.endpoint         | No           | String   | To be specified to override the endpoint of the AI service                          |
| timeout                   | No           | Integer  | Timeout in milliseconds for requests to AI service. Range: 1 - 60000. Default: 3000         |
| keepalive                 | No           | Boolean  | Enable keepalive for requests to AI service. Default: true                                  |
| keepalive_timeout         | No           | Integer  | Keepalive timeout in milliseconds for requests to AI service. Minimum: 1000. Default: 60000 |
| keepalive_pool            | No           | Integer  | Keepalive pool size for requests to AI service. Minimum: 1. Default: 30                     |
| ssl_verify                | No           | Boolean  | SSL verification for requests to AI service. Default: true                                  |


## How it works

![image](https://github.com/user-attachments/assets/c7288e4f-00fc-46ca-b69e-d3d74d7085ca)



## Example usage

Create a route with the `ai-request-rewrite` plugin like:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-request-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver\'s license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged.",
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer <some-token>"
          }
        },
        "options": {
          "model": "gpt-4",
          "max_tokens": 1024,
          "temperature": 1
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

The request body for AI Service is as follows:
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
The upstream service will receive a request like this:

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

Create a route with the `ai-request-rewrite` plugin with `provider` set to `openai-compatible` and the endpoint of the model set to `override.endpoint` like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-request-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., '*** **** **** 1234') for credit card numbers). Ensure the JSON structure remains unchanged.",
        "provider": "openai-compatible",
        "auth": {
          "header": {
            "Authorization": "Bearer <some-token>"
          }
        },
        "options": {
          "model": "qwen-plus",
          "max_tokens": 1024,
          "temperature": 1
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