---
title: ai-proxy-multi
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy-multi
description: This document contains information about the Apache APISIX ai-proxy-multi Plugin.
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

The `ai-proxy-multi` plugin simplifies access to LLM providers and models by defining a standard request format
that allows key fields in plugin configuration to be embedded into the request.

This plugin adds additional features like `load balancing` and `retries` to the existing `ai-proxy` plugin.

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

| **Name**                     | **Required** | **Type** | **Description**                                                                                               | **Default** |
| ---------------------------- | ------------ | -------- | ------------------------------------------------------------------------------------------------------------- | ----------- |
| providers                    | Yes          | array    | List of AI providers, each following the provider schema.                                                     |             |
| provider.name                | Yes          | string   | Name of the AI service provider. Allowed values: `openai`, `deepseek`.                                        |             |
| provider.model               | Yes          | string   | Name of the AI model to execute. Example: `gpt-4o`.                                                           |             |
| provider.priority            | No           | integer  | Priority of the provider for load balancing.                                                                  | 0           |
| provider.weight              | No           | integer  | Load balancing weight.                                                                                        |             |
| balancer.algorithm           | No           | string   | Load balancing algorithm. Allowed values: `chash`, `roundrobin`.                                              | roundrobin  |
| balancer.hash_on             | No           | string   | Defines what to hash on for consistent hashing (`vars`, `header`, `cookie`, `consumer`, `vars_combinations`). | vars        |
| balancer.key                 | No           | string   | Key for consistent hashing in dynamic load balancing.                                                         |             |
| provider.auth                | Yes          | object   | Authentication details, including headers and query parameters.                                               |             |
| provider.auth.header         | No           | object   | Authentication details sent via headers. Header name must match `^[a-zA-Z0-9._-]+$`.                          |             |
| provider.auth.query          | No           | object   | Authentication details sent via query parameters. Keys must match `^[a-zA-Z0-9._-]+$`.                        |             |
| provider.options.max_tokens  | No           | integer  | Defines the maximum tokens for chat or completion models.                                                     | 256         |
| provider.options.input_cost  | No           | number   | Cost per 1M tokens in the input prompt. Minimum is 0.                                                         |             |
| provider.options.output_cost | No           | number   | Cost per 1M tokens in the AI-generated output. Minimum is 0.                                                  |             |
| provider.options.temperature | No           | number   | Defines the model's temperature (0.0 - 5.0) for randomness in responses.                                      |             |
| provider.options.top_p       | No           | number   | Defines the top-p probability mass (0 - 1) for nucleus sampling.                                              |             |
| provider.options.stream      | No           | boolean  | Enables streaming responses via SSE.                                                                          |             |
| provider.override.endpoint   | No           | string   | Custom host override for the AI provider.                                                                     |             |
| timeout                      | No           | integer  | Request timeout in milliseconds (1-60000).                                                                    | 30000        |
| keepalive                    | No           | boolean  | Enables keepalive connections.                                                                                | true        |
| keepalive_timeout            | No           | integer  | Timeout for keepalive connections (minimum 1000ms).                                                           | 60000       |
| keepalive_pool               | No           | integer  | Maximum keepalive connections.                                                                                | 30          |
| ssl_verify                   | No           | boolean  | Enables SSL certificate verification.                                                                         | true        |

## Example usage

Create a route with the `ai-proxy-multi` plugin like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "ai-proxy-multi-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "providers": [
          {
            "name": "openai",
            "model": "gpt-4",
            "weight": 1,
            "priority": 1,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "options": {
                "max_tokens": 512,
                "temperature": 1.0
            }
          },
          {
            "name": "deepseek",
            "model": "deepseek-chat",
            "weight": 1,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
                "max_tokens": 512,
                "temperature": 1.0
            }
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

In the above configuration, requests will be equally balanced among the `openai` and `deepseek` providers.

### Retry and fallback:

The `priority` attribute can be adjusted to implement the fallback and retry feature.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "ai-proxy-multi-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "providers": [
          {
            "name": "openai",
            "model": "gpt-4",
            "weight": 1,
            "priority": 1,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "options": {
                "max_tokens": 512,
                "temperature": 1.0
            }
          },
          {
            "name": "deepseek",
            "model": "deepseek-chat",
            "weight": 1,
            "priority": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
                "max_tokens": 512,
                "temperature": 1.0
            }
          }
        ]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

In the above configuration `priority` for the deepseek provider is set to `0`. Which means if `openai` provider is unavailable then `ai-proxy-multi` plugin will retry sending request to `deepseek` in the second attempt.

### Send request to an OpenAI compatible LLM

Create a route with the `ai-proxy-multi` plugin with `provider.name` set to `openai-compatible` and the endpoint of the model set to `provider.override.endpoint` like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "ai-proxy-multi-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "providers": [
          {
            "name": "openai-compatible",
            "model": "qwen-plus",
            "weight": 1,
            "priority": 1,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "override": {
              "endpoint": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
            }
          },
          {
            "name": "deepseek",
            "model": "deepseek-chat",
            "weight": 1,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
                "max_tokens": 512,
                "temperature": 1.0
            }
          }
        ],
        "passthrough": false
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```
