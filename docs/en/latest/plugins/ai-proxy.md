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

The `ai-proxy` plugin simplifies access to AI providers and models by defining a standard request format
that allows configuring key fields in plugin configuration to embed into the request.

Proxying requests to OpenAI is supported for now, other AI models will be supported soon.

## Request Format

### OpenAI

- Chat API

| Name               | Type   | Required | Description                                         |
| ------------------ | ------ | -------- | --------------------------------------------------- |
| `messages`         | Array  | Yes      | An array of message objects                         |
| `messages.role`    | String | Yes      | Role of the message (`system`, `user`, `assistant`) |
| `messages.content` | String | Yes      | Content of the message                              |

- Completion API

| Name     | Type   | Required | Description                       |
| -------- | ------ | -------- | --------------------------------- |
| `prompt` | String | Yes      | Prompt to be sent to the upstream |

## Plugin Attributes

| Field                              | Type    | Description                                                                                   | Required |
| ---------------------------------- | ------- | --------------------------------------------------------------------------------------------- | -------- |
| `route_type`                       | String  | Specifies the type of route (`llm/chat`, `llm/completions`, `passthrough`)                    | Yes      |
| `auth`                             | Object  | Authentication configuration                                                                  | Yes      |
| `auth.source`                      | String  | Source of the authentication (`header`, `param`)                                              | Yes      |
| `auth.name`                        | String  | Name of the param/header carrying Authorization or API key. Minimum length: 1                 | Yes      |
| `auth.value`                       | String  | Full auth-header/param value. Minimum length: 1. Encrypted.                                   | Yes      |
| `model`                            | Object  | Model configuration                                                                           | Yes      |
| `model.provider`                   | String  | AI provider request format. Translates requests to/from specified backend compatible formats. | Yes      |
| `model.name`                       | String  | Model name to execute.                                                                        | Yes      |
| `model.options`                    | Object  | Key/value settings for the model                                                              | No       |
| `model.options.max_tokens`         | Integer | Defines the max_tokens, if using chat or completion models. Default: 256                      | No       |
| `model.options.temperature`        | Number  | Defines the matching temperature, if using chat or completion models. Range: 0.0 - 5.0        | No       |
| `model.options.top_p`              | Number  | Defines the top-p probability mass, if supported. Range: 0.0 - 1.0                            | No       |
| `model.options.upstream_host`      | String  | To be specified to override the host of the AI provider                                       | No       |
| `model.options.upstream_port`      | Integer | To be specified to override the AI provider port                                              | No       |
| `model.options.upstream_path`      | String  | To be specified to override the URL to the AI provider endpoints                              | No       |
| `model.options.response_streaming` | Boolean | Stream response by SSE. Default: false                                                        | No       |

## Example usage

Create a route with the `ai-proxy` plugin like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-proxy": {
        "route_type": "llm/chat",
        "auth": {
          "header_name": "Authorization",
          "header_value": "Bearer <some-token>"
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
      }
    }
  }'
```

The upstream node can be any arbitrary value because it won't be contacted.

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
