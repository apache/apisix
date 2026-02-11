---
title: ai-rate-limiting
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-rate-limiting
  - AI
  - LLM
description: ai-rate-limiting 插件对发送到 LLM 服务的请求实施基于令牌的速率限制，防止过度使用，优化 API 消费，并确保高效的资源分配。
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-rate-limiting" />
</head>

## 描述

`ai-rate-limiting` 插件对发送到 LLM 服务的请求实施基于令牌的速率限制。它通过控制在指定时间范围内消耗的令牌数量来帮助管理 API 使用，确保公平的资源分配并防止服务过载。它通常与 [`ai-proxy`](ai-proxy.md) 或 [`ai-proxy-multi`](ai-proxy-multi.md) 插件一起使用。

## 属性

| 名称                         | 类型            | 必选项 | 默认值  | 有效值                                             | 描述 |
|------------------------------|----------------|----------|----------|---------------------------------------------------------|-------------|
| limit                        | integer        | 否    |          | >0                             | 在给定时间间隔内允许的最大令牌数。`limit` 和 `instances.limit` 中至少应配置一个。如果未配置 `rules`,则为必填项。 |
| time_window                  | integer        | 否    |          | >0                             | 与速率限制 `limit` 对应的时间间隔（秒）。`time_window` 和 `instances.time_window` 中至少应配置一个。如果未配置 `rules`,则为必填项。 |
| rules                        | array[object]  | 否    |          |                                                         | 速率限制规则列表。每个规则是一个包含 `count`、`time_window` 和 `key` 的对象。如果配置了此项，则优先于 `limit` 和 `time_window`。 |
| rules.count                  | integer 或 string | 是  |          | >0 或变量表达式                              | 在给定时间间隔内允许的最大令牌数。可以是静态整数或变量表达式，如 `$http_custom_limit`。 |
| rules.time_window            | integer 或 string | 是  |          | >0 或变量表达式                              | 与速率限制 `count` 对应的时间间隔（秒）。可以是静态整数或变量表达式。 |
| rules.key                    | string         | 是     |          |                                                         | 用于计数请求的键。如果配置的键不存在，则不会执行该规则。`key` 被解释为变量组合，例如：`$http_custom_a $http_custom_b`。 |
| rules.header_prefix          | string         | 否    |          |                                                         | 速率限制头部的前缀。如果配置了此项，响应将包含 `X-AI-{header_prefix}-RateLimit-Limit`、`X-AI-{header_prefix}-RateLimit-Remaining` 和 `X-AI-{header_prefix}-RateLimit-Reset` 头部。如果未配置，将使用规则索引 (从 1 开始) 作为前缀。|
| show_limit_quota_header      | boolean        | 否    | true     |                                                         | 如果为 true，则在响应中包含 `X-AI-RateLimit-Limit-*`、`X-AI-RateLimit-Remaining-*` 和 `X-AI-RateLimit-Reset-*` 头部，其中 `*` 是实例名称。 |
| limit_strategy               | string         | 否    | total_tokens | [total_tokens, prompt_tokens, completion_tokens] | 应用速率限制的令牌类型。`total_tokens` 是 `prompt_tokens` 和 `completion_tokens` 的总和。 |
| instances                    | array[object]  | 否    |          |                                                         | LLM 实例速率限制配置。 |
| instances.name               | string         | 是     |          |                                                         | LLM 服务实例的名称。 |
| instances.limit              | integer        | 是     |          | >0                             | 实例在给定时间间隔内允许的最大令牌数。 |
| instances.time_window        | integer        | 是     |          | >0                             | 实例速率限制 `limit` 对应的时间间隔（秒）。 |
| rejected_code                | integer        | 否    | 503      |  [200, 599]                           | 当超出配额的请求被拒绝时返回的 HTTP 状态码。 |
| rejected_msg                 | string         | 否    |          |                                           | 当超出配额的请求被拒绝时返回的响应体。 |

## 示例

以下示例演示了如何为不同场景配置 `ai-rate-limiting`。

:::note

您可以使用以下命令从 `config.yaml` 获取 `admin_key` 并保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 与 `ai-proxy` 一起应用速率限制

以下示例演示了如何使用 `ai-proxy` 代理 LLM 流量，并使用 `ai-rate-limiting` 在实例上配置基于令牌的速率限制。

创建一个路由并更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-rate-limiting-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
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

向路由发送 POST 请求，在请求体中包含系统提示和示例用户问题：

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

您应该收到类似以下的响应：

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

如果在 30 秒窗口内消耗了 300 个提示令牌的速率限制配额，所有额外的请求将被拒绝。

### 对多个实例中的一个进行速率限制

以下示例演示了如何使用 `ai-proxy-multi` 配置两个模型进行负载均衡，将 80% 的流量转发到一个实例，20% 转发到另一个实例。此外，使用 `ai-rate-limiting` 对接收 80% 流量的实例配置基于令牌的速率限制，这样当配置的配额完全消耗时，额外的流量将被转发到另一个实例。

创建一个路由，对 `deepseek-instance-1` 实例应用 30 秒窗口内 100 个总令牌的速率限制配额，并更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-rate-limiting-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "instances": [
          {
            "name": "deepseek-instance-1",
            "provider": "deepseek",
            "weight": 8,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          },
          {
            "name": "deepseek-instance-2",
            "provider": "deepseek",
            "weight": 2,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          }
        ]
      },
      "ai-rate-limiting": {
        "instances": [
          {
            "name": "deepseek-instance-1",
            "limit_strategy": "total_tokens",
            "limit": 100,
            "time_window": 30
          }
        ]
      }
    }
  }'
```

向路由发送 POST 请求，在请求体中包含系统提示和示例用户问题：

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

您应该收到类似以下的响应：

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

如果 `deepseek-instance-1` 实例在 30 秒窗口内消耗了 100 个令牌的速率限制配额，额外的请求将全部转发到 `deepseek-instance-2`，该实例没有速率限制。

### 对所有实例应用相同配额

以下示例演示了如何对 `ai-rate-limiting` 中的所有 LLM 上游实例应用相同的速率限制配额。

为了演示和更容易区分，您将配置一个 OpenAI 实例和一个 DeepSeek 实例作为上游 LLM 服务。

创建一个路由，对所有实例在 60 秒窗口内应用 100 个总令牌的速率限制配额，并更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-rate-limiting-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "instances": [
          {
            "name": "openai-instance",
            "provider": "openai",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "options": {
              "model": "gpt-4"
            }
          },
          {
            "name": "deepseek-instance",
            "provider": "deepseek",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          }
        ]
      },
      "ai-rate-limiting": {
        "limit": 100,
        "time_window": 60,
        "rejected_code": 429,
        "limit_strategy": "total_tokens"
      }
    }
  }'
```

向路由发送 POST 请求，在请求体中包含系统提示和示例用户问题：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws" }
    ]
  }'
```

您应该收到来自任一 LLM 实例的响应，类似以下内容：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Sure! Sir Isaac Newton formulated three laws of motion that describe the motion of objects. These laws are widely used in physics and engineering for studying and understanding how things move. Here they are:\n\n1. Newton's First Law - Law of Inertia: An object at rest tends to stay at rest and an object in motion tends to stay in motion with the same speed and in the same direction unless acted upon by an unbalanced force. This is also known as the principle of inertia.\n\n2. Newton's Second Law of Motion - Force and Acceleration: The acceleration of an object is directly proportional to the net force acting on it and inversely proportional to its mass. This is usually formulated as F=ma where F is the force applied, m is the mass of the object and a is the acceleration produced.\n\n3. Newton's Third Law - Action and Reaction: For every action, there is an equal and opposite reaction. This means that any force exerted on a body will create a force of equal magnitude but in the opposite direction on the object that exerted the first force.\n\nIn simple terms: \n1. If you slide a book on a table and let go, it will stop because of the friction (or force) between it and the table.\n2.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 23,
    "completion_tokens": 256,
    "total_tokens": 279,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default",
  "system_fingerprint": null
}
```

由于 `total_tokens` 值超过了配置的 `100` 配额，预期在 60 秒窗口内的下一个请求将被转发到另一个实例。

在同一个 60 秒窗口内，向路由发送另一个 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws" }
    ]
  }'
```

您应该收到来自另一个 LLM 实例的响应，类似以下内容：

```json
{
  ...
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Sure! Newton's laws of motion are three fundamental principles that describe the relationship between the motion of an object and the forces acting on it. They were formulated by Sir Isaac Newton in the late 17th century and are foundational to classical mechanics. Here's an explanation of each law:\n\n---\n\n### **1. Newton's First Law (Law of Inertia)**\n- **Statement**: An object will remain at rest or in uniform motion in a straight line unless acted upon by an external force.\n- **What it means**: This law introduces the concept of **inertia**, which is the tendency of an object to resist changes in its state of motion. If no net force acts on an object, its velocity (speed and direction) will not change.\n- **Example**: A book lying on a table will stay at rest unless you push it. Similarly, a hockey puck sliding on ice will keep moving at a constant speed unless friction or another force slows it down.\n\n---\n\n### **2. Newton's Second Law (Law of Acceleration)**\n- **Statement**: The acceleration of an object is directly proportional to the net force acting on it and inversely proportional to its mass. Mathematically, this is expressed as:\n  \\[\n  F = ma\n  \\]\n"
      },
      "logprobs": null,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 13,
    "completion_tokens": 256,
    "total_tokens": 269,
    "prompt_tokens_details": {
      "cached_tokens": 0
    },
    "prompt_cache_hit_tokens": 0,
    "prompt_cache_miss_tokens": 13
  },
  "system_fingerprint": "fp_3a5770e1b4_prod0225"
}
```

由于 `total_tokens` 值超过了配置的 `100` 配额，预期在 60 秒窗口内的下一个请求将被拒绝。

在同一个 60 秒窗口内，向路由发送第三个 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws" }
    ]
  }'
```

您应该收到 `HTTP 429 Too Many Requests` 响应并观察到以下头部：

```text
X-AI-RateLimit-Limit-openai-instance: 100
X-AI-RateLimit-Remaining-openai-instance: 0
X-AI-RateLimit-Reset-openai-instance: 0
X-AI-RateLimit-Limit-deepseek-instance: 100
X-AI-RateLimit-Remaining-deepseek-instance: 0
X-AI-RateLimit-Reset-deepseek-instance: 0
```

### 配置实例优先级和速率限制

以下示例演示了如何配置两个具有不同优先级的模型，并对具有较高优先级的实例应用速率限制。在 `fallback_strategy` 设置为 `["rate_limiting"]` 的情况下，一旦高优先级实例的速率限制配额完全消耗，插件应继续将请求转发到低优先级实例。

创建一个路由，对 `openai-instance` 实例设置速率限制和更高的优先级，并将 `fallback_strategy` 设置为 `["rate_limiting"]`。更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-rate-limiting-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "fallback_strategy": ["rate_limiting"],
        "instances": [
          {
            "name": "openai-instance",
            "provider": "openai",
            "priority": 1,
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "options": {
              "model": "gpt-4"
            }
          },
          {
            "name": "deepseek-instance",
            "provider": "deepseek",
            "priority": 0,
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          }
        ]
      },
      "ai-rate-limiting": {
        "instances": [
          {
            "name": "openai-instance",
            "limit": 10,
            "time_window": 60
          }
        ],
        "limit_strategy": "total_tokens"
      }
    }
  }'
```

向路由发送 POST 请求，在请求体中包含系统提示和示例用户问题：

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

您应该收到类似以下的响应：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "1+1 equals 2.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 23,
    "completion_tokens": 8,
    "total_tokens": 31,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default",
  "system_fingerprint": null
}
```

由于 `total_tokens` 值超过了配置的 `10` 配额，预期在 60 秒窗口内的下一个请求将被转发到另一个实例。

在同一个 60 秒窗口内，向路由发送另一个 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newton law" }
    ]
  }'
```

您应该看到类似以下的响应：

```json
{
  ...,
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Certainly! Newton's laws of motion are three fundamental principles that describe the relationship between the motion of an object and the forces acting on it. They were formulated by Sir Isaac Newton in the late 17th century and are foundational to classical mechanics.\n\n---\n\n### **1. Newton's First Law (Law of Inertia):**\n- **Statement:** An object at rest will remain at rest, and an object in motion will continue moving at a constant velocity (in a straight line at a constant speed), unless acted upon by an external force.\n- **Key Idea:** This law introduces the concept of **inertia**, which is the tendency of an object to resist changes in its state of motion.\n- **Example:** If you slide a book across a table, it eventually stops because of the force of friction acting on it. Without friction, the book would keep moving indefinitely.\n\n---\n\n### **2. Newton's Second Law (Law of Acceleration):**\n- **Statement:** The acceleration of an object is directly proportional to the net force acting on it and inversely proportional to its mass. Mathematically, this is expressed as:\n  \\[\n  F = ma\n  \\]\n  where:\n  - \\( F \\) = net force applied (in Newtons),\n  -"
      },
      ...
    }
  ],
  ...
}
```

### 按消费者进行负载均衡和速率限制

以下示例演示了如何配置两个模型进行负载均衡，并按消费者应用速率限制。

创建消费者 `johndoe` 并对 `openai-instance` 实例设置 60 秒窗口内 10 个令牌的速率限制配额：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
    "plugins": {
      "ai-rate-limiting": {
        "instances": [
          {
            "name": "openai-instance",
            "limit": 10,
            "time_window": 60
          }
        ],
        "rejected_code": 429,
        "limit_strategy": "total_tokens"
      }
    }
  }'
```

为 `johndoe` 配置 `key-auth` 凭据：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/johndoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-john-key-auth",
    "plugins": {
      "key-auth": {
        "key": "john-key"
      }
    }
  }'
```

创建另一个消费者 `janedoe` 并对 `deepseek-instance` 实例设置 60 秒窗口内 10 个令牌的速率限制配额：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "janedoe",
    "plugins": {
      "ai-rate-limiting": {
        "instances": [
          {
            "name": "deepseek-instance",
            "limit": 10,
            "time_window": 60
          }
        ],
        "rejected_code": 429,
        "limit_strategy": "total_tokens"
      }
    }
  }'
```

为 `janedoe` 配置 `key-auth` 凭据：

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers/janedoe/credentials" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "cred-jane-key-auth",
    "plugins": {
      "key-auth": {
        "key": "jane-key"
      }
    }
  }'
```

创建一个路由并更新您的 LLM 提供商、模型、API 密钥和端点（如适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-rate-limiting-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "key-auth": {},
      "ai-proxy-multi": {
        "fallback_strategy": ["rate_limiting"],
        "instances": [
          {
            "name": "openai-instance",
            "provider": "openai",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$OPENAI_API_KEY"'"
              }
            },
            "options": {
              "model": "gpt-4"
            }
          },
          {
            "name": "deepseek-instance",
            "provider": "deepseek",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
              }
            },
            "options": {
              "model": "deepseek-chat"
            }
          }
        ]
      }
    }
  }'
```

向路由发送不带任何消费者密钥的 POST 请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到 `HTTP/1.1 401 Unauthorized` 响应。

使用 `johndoe` 的密钥向路由发送 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H 'apikey: john-key' \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到类似以下的响应：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "1+1 equals 2.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 23,
    "completion_tokens": 8,
    "total_tokens": 31,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default",
  "system_fingerprint": null
}
```

由于 `total_tokens` 值超过了 `johndoe` 的 `openai` 实例配置配额，预期在 60 秒窗口内来自 `johndoe` 的下一个请求将被转发到 `deepseek` 实例。

在同一个 60 秒窗口内，使用 `johndoe` 的密钥向路由发送另一个 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H 'apikey: john-key' \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws to me" }
    ]
  }'
```

您应该看到类似以下的响应：

```json
{
  ...,
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Certainly! Newton's laws of motion are three fundamental principles that describe the relationship between the motion of an object and the forces acting on it. They were formulated by Sir Isaac Newton in the late 17th century and are foundational to classical mechanics.\n\n---\n\n### **1. Newton's First Law (Law of Inertia):**\n- **Statement:** An object at rest will remain at rest, and an object in motion will continue moving at a constant velocity (in a straight line at a constant speed), unless acted upon by an external force.\n- **Key Idea:** This law introduces the concept of **inertia**, which is the tendency of an object to resist changes in its state of motion.\n- **Example:** If you slide a book across a table, it eventually stops because of the force of friction acting on it. Without friction, the book would keep moving indefinitely.\n\n---\n\n### **2. Newton's Second Law (Law of Acceleration):**\n- **Statement:** The acceleration of an object is directly proportional to the net force acting on it and inversely proportional to its mass. Mathematically, this is expressed as:\n  \\[\n  F = ma\n  \\]\n  where:\n  - \\( F \\) = net force applied (in Newtons),\n  -"
      },
      ...
    }
  ],
  ...
}
```

使用 `janedoe` 的密钥向路由发送 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H 'apikey: jane-key' \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

您应该收到类似以下的响应：

```json
{
  ...,
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The sum of 1 and 1 is 2. This is a basic arithmetic operation where you combine two units to get a total of two units."
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 14,
    "completion_tokens": 31,
    "total_tokens": 45,
    "prompt_tokens_details": {
      "cached_tokens": 0
    },
    "prompt_cache_hit_tokens": 0,
    "prompt_cache_miss_tokens": 14
  },
  "system_fingerprint": "fp_3a5770e1b4_prod0225"
}
```

由于 `total_tokens` 值超过了 `janedoe` 的 `deepseek` 实例配置配额，预期在 60 秒窗口内来自 `janedoe` 的下一个请求将被转发到 `openai` 实例。

在同一个 60 秒窗口内，使用 `janedoe` 的密钥向路由发送另一个 POST 请求：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H 'apikey: jane-key' \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Explain Newtons laws to me" }
    ]
  }'
```

您应该看到类似以下的响应：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Sure, here are Newton's three laws of motion:\n\n1) Newton's First Law, also known as the Law of Inertia, states that an object at rest will stay at rest, and an object in motion will stay in motion, unless acted on by an external force. In simple words, this law suggests th",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

这显示了 `ai-proxy-multi` 根据消费者在 `ai-rate-limiting` 中的速率限制规则对流量进行负载均衡。
