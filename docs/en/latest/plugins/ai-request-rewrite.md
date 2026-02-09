---
title: ai-request-rewrite
keywords:
  - Apache APISIX
  - AI Gateway
  - Plugin
  - ai-request-rewrite
description: The ai-request-rewrite plugin intercepts client requests before they are forwarded to the upstream service. It sends a predefined prompt, along with the original request body, to a specified LLM service. The LLM processes the input and returns a modified request body, which is then used for the upstream request. This allows dynamic transformation of API requests based on AI-generated content.
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

The `ai-request-rewrite` plugin intercepts client requests before they are forwarded to the upstream service. It sends a predefined prompt, along with the original request body, to a specified LLM service. The LLM processes the input and returns a modified request body, which is then used for the upstream request. This allows dynamic transformation of API requests based on AI-generated content.

## Plugin Attributes

| **Field**                 | **Required** | **Type** | **Description**                                                                      |
| ------------------------- | ------------ | -------- | ------------------------------------------------------------------------------------ |
| prompt                    | Yes          | String   | The prompt send to LLM service.                                                      |
| provider                  | Yes          | String   | Name of the LLM service. Available options: openai, deekseek, azure-openai, aimlapi, anthropic, openrouter, gemini, vertex-ai, and openai-compatible. When `aimlapi` is selected, the plugin uses the OpenAI-compatible driver with a default endpoint of `https://api.aimlapi.com/v1/chat/completions`.   |
| provider_conf             | No           | Object   | Configuration for the specific provider. Required when `provider` is set to `vertex-ai` and `override` is not configured. |
| provider_conf.project_id  | Yes          | String   | Google Cloud Project ID. |
| provider_conf.region      | Yes          | String   | Google Cloud Region. |
| auth                      | Yes          | Object   | Authentication configuration                                                         |
| auth.header               | No           | Object   | Authentication headers. Key must match pattern `^[a-zA-Z0-9._-]+$`.                  |
| auth.query                | No           | Object   | Authentication query parameters. Key must match pattern `^[a-zA-Z0-9._-]+$`.         |
| auth.gcp                  | No           | Object   | Configuration for Google Cloud Platform (GCP) authentication. |
| auth.gcp.service_account_json | No       | String   | Content of the GCP service account JSON file. This can also be configured by setting the `GCP_SERVICE_ACCOUNT` environment variable. |
| auth.gcp.max_ttl          | No           | Integer  | Maximum TTL (in seconds) for caching the GCP access token. Minimum: 1. |
| auth.gcp.expire_early_secs| No           | Integer  | Seconds to expire the access token before its actual expiration time to avoid edge cases. Minimum: 0. Default: 60. |
| options                   | No           | Object   | Key/value settings for the model                                                     |
| options.model             | No           | String   | Model to execute. Examples: "gpt-3.5-turbo" for openai, "deepseek-chat" for deekseek, or "qwen-turbo" for openai-compatible or aimlapi services |
| override.endpoint         | No           | String   | Override the default endpoint when using OpenAI-compatible services (e.g., self-hosted models or third-party LLM services). When the provider is 'openai-compatible', the endpoint field is required. |
| timeout                   | No           | Integer  | Total timeout in milliseconds for requests to LLM service, including connect, send, and read timeouts. Range: 1 - 60000. Default: 30000|
| keepalive                 | No           | Boolean  | Enable keepalive for requests to LLM service. Default: true                                  |
| keepalive_timeout         | No           | Integer  | Keepalive timeout in milliseconds for requests to LLM service. Minimum: 1000. Default: 60000 |
| keepalive_pool            | No           | Integer  | Keepalive pool size for requests to LLM service. Minimum: 1. Default: 30                     |
| ssl_verify                | No           | Boolean  | SSL verification for requests to LLM service. Default: true                                  |

## How it works

![image](https://github.com/user-attachments/assets/c7288e4f-00fc-46ca-b69e-d3d74d7085ca)

## Examples

The examples below demonstrate how you can configure `ai-request-rewrite` for different scenarios.

:::note

You can fetch the admin_key from config.yaml and save to an environment variable with the following command:

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')

:::

### Redact sensitive information

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-request-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver'\''s license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged.",
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer <some-token>"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
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

The request body send to the LLM Service is as follows:

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

The LLM processes the input and returns a modified request body, which replace detected sensitive values with a masked format then used for the upstream request:

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
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-request-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver'\''s license numbers). Replace detected sensitive values with a masked format (e.g., '*** **** **** 1234') for credit card numbers). Ensure the JSON structure remains unchanged.",
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
        "httpbin.org:80": 1
      }
    }
  }'
```
