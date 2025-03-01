---
title: ai-proxy
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy
description: This document contains information about the Apache APISIX ai-proxy Plugin.
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

The `ai-proxy` plugin simplifies access to LLM providers and models by defining a standard request format
that allows key fields in plugin configuration to be embedded into the request.

Proxying requests to OpenAI is supported now. Other LLM services will be supported soon.

## Request Format

### OpenAI

- Chat API

| Name               | Type   | Required | Description                                         |
| ------------------ | ------ | -------- | --------------------------------------------------- |
| `messages`         | Array  | Yes      | An array of message objects                         |
| `messages.role`    | String | Yes      | Role of the message (`system`, `user`, `assistant`) |
| `messages.content` | String | Yes      | Content of the message                              |

## Plugin Attributes

| **Field**                 | **Required** | **Type** | **Description**                                                                      |
| ------------------------- | ------------ | -------- | ------------------------------------------------------------------------------------ |
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
| model.options.stream      | No           | Boolean  | Stream response by SSE. Default: false                                               |
| override.endpoint         | No           | String   | Override the endpoint of the AI provider                                             |
| passthrough               | No           | Boolean  | If enabled, the response from LLM will be sent to the upstream. Default: false       |
| timeout                   | No           | Integer  | Timeout in milliseconds for requests to LLM. Range: 1 - 60000. Default: 3000         |
| keepalive                 | No           | Boolean  | Enable keepalive for requests to LLM. Default: true                                  |
| keepalive_timeout         | No           | Integer  | Keepalive timeout in milliseconds for requests to LLM. Minimum: 1000. Default: 60000 |
| keepalive_pool            | No           | Integer  | Keepalive pool size for requests to LLM. Minimum: 1. Default: 30                     |
| ssl_verify                | No           | Boolean  | SSL verification for requests to LLM. Default: true                                  |

## Example usage

Create a route with the `ai-proxy` plugin like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-proxy": {
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

Since `passthrough` is not enabled upstream node can be any arbitrary value because it won't be contacted.

Now send a request:

```shell
curl http://127.0.0.1:9080/anything -i -XPOST  -H 'Content-Type: application/json' -d '{
        "messages": [
            { "role": "system", "content": "You are a mathematician" },
            { "role": "user", "a": 1, "content": "What is 1+1?" }
        ]
    }'
```

You will receive a response like this:

```json
{
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "message": {
        "content": "The sum of \\(1 + 1\\) is \\(2\\).",
        "role": "assistant"
      }
    }
  ],
  "created": 1723777034,
  "id": "chatcmpl-9whRKFodKl5sGhOgHIjWltdeB8sr7",
  "model": "gpt-4o-2024-05-13",
  "object": "chat.completion",
  "system_fingerprint": "fp_abc28019ad",
  "usage": { "completion_tokens": 15, "prompt_tokens": 23, "total_tokens": 38 }
}
```

### Send request to an OpenAI compatible LLM

Create a route with the `ai-proxy` plugin with `provider` set to `openai-compatible` and the endpoint of the model set to `override.endpoint` like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-proxy": {
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
