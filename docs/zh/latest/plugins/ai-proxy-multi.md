---
title: ai-proxy-multi
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-proxy-multi
  - AI
  - LLM
description: ai-proxy-multi 插件通过负载均衡、重试、故障转移和健康检查扩展了 ai-proxy 的功能，简化了与 OpenAI、DeepSeek、Azure、AIMLAPI、Anthropic、OpenRouter、Gemini、Vertex AI 和其他 OpenAI 兼容 API 的集成。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-proxy-multi" />
</head>

## 描述

`ai-proxy-multi` 插件通过将插件配置转换为 OpenAI、DeepSeek、Azure、AIMLAPI、Anthropic、OpenRouter、Gemini、Vertex AI 和其他 OpenAI 兼容 API 的指定请求格式，简化了对 LLM 和嵌入模型的访问。它通过负载均衡、重试、故障转移和健康检查扩展了 [`ai-proxy`](./ai-proxy.md) 的功能。

此外，该插件还支持在访问日志中记录 LLM 请求信息，如令牌使用量、模型、首次响应时间等。

## 请求格式

| 名称               | 类型   | 必选项 | 描述                                         |
| ------------------ | ------ | -------- | --------------------------------------------------- |
| `messages`         | Array  | 是      | 消息对象数组。                        |
| `messages.role`    | String | 是      | 消息的角色（`system`、`user`、`assistant`）。|
| `messages.content` | String | 是      | 消息的内容。                             |

## 属性

| 名称                               | 类型            | 必选项 | 默认值                           | 有效值 | 描述 |
|------------------------------------|----------------|----------|-----------------------------------|--------------|-------------|
| fallback_strategy                  | string 或 array         | 否    |  | string: "instance_health_and_rate_limiting", "http_429", "http_5xx"<br />array: ["rate_limiting", "http_429", "http_5xx"] | 故障转移策略。设置后，插件将在转发请求时检查指定实例的令牌是否已耗尽。如果是，则无论实例优先级如何，都将请求转发到下一个实例。未设置时，当高优先级实例的令牌耗尽时，插件不会将请求转发到低优先级实例。 |
| balancer                           | object         | 否    |                                   |              | 负载均衡配置。 |
| balancer.algorithm                 | string         | 否    | roundrobin                     | [roundrobin, chash] | 负载均衡算法。设置为 `roundrobin` 时，使用加权轮询算法。设置为 `chash` 时，使用一致性哈希算法。 |
| balancer.hash_on                   | string         | 否    |                                   | [vars, headers, cookie, consumer, vars_combinations] | 当 `type` 为 `chash` 时使用。支持基于 [NGINX 变量](https://nginx.org/en/docs/varindex.html)、标头、cookie、消费者或 [NGINX 变量](https://nginx.org/en/docs/varindex.html)组合进行哈希。 |
| balancer.key                       | string         | 否    |                                   |              | 当 `type` 为 `chash` 时使用。当 `hash_on` 设置为 `header` 或 `cookie` 时，需要 `key`。当 `hash_on` 设置为 `consumer` 时，不需要 `key`，因为消费者名称将自动用作键。 |
| instances                          | array[object]  | 是     |                                   |              | LLM 实例配置。 |
| instances.name                     | string         | 是     |                                   |              | LLM 服务实例的名称。 |
| instances.provider                 | string         | 是     |                                   | [openai, deepseek, azure-openai, aimlapi, anthropic, openrouter, gemini, vertex-ai, openai-compatible] | LLM 服务提供商。设置为 `openai` 时，插件将代理请求到 `api.openai.com`。设置为 `deepseek` 时，插件将代理请求到 `api.deepseek.com`。设置为 `aimlapi` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `api.aimlapi.com`。设置为 `anthropic` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `api.anthropic.com`。设置为 `openrouter` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `openrouter.ai`。设置为 `gemini` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `generativelanguage.googleapis.com`。设置为 `vertex-ai` 时，插件默认将请求代理到 `aiplatform.googleapis.com`，且需要配置 `provider_conf` 或 `override`。设置为 `openai-compatible` 时，插件将代理请求到在 `override` 中配置的自定义端点。 |
| instances.provider_conf            | object         | 否     |                                   |              | 特定提供商的配置。当 `provider` 设置为 `vertex-ai` 且未配置 `override` 时必填。 |
| instances.provider_conf.project_id | string         | 是     |                                   |              | Google Cloud 项目 ID。 |
| instances.provider_conf.region     | string         | 是     |                                   |              | Google Cloud 区域。 |
| instances.priority                  | integer        | 否    | 0                               |              | LLM 实例在负载均衡中的优先级。`priority` 优先于 `weight`。 |
| instances.weight                    | string         | 是     | 0                               | 大于或等于 0 | LLM 实例在负载均衡中的权重。 |
| instances.auth                      | object         | 是     |                                   |              | 身份验证配置。 |
| instances.auth.header               | object         | 否    |                                   |              | 身份验证标头。应配置 `header` 和 `query` 中的至少一个。 |
| instances.auth.query                | object         | 否    |                                   |              | 身份验证查询参数。应配置 `header` 和 `query` 中的至少一个。 |
| instances.auth.gcp                  | object         | 否    |                                   |              | Google Cloud Platform (GCP) 身份验证配置。 |
| instances.auth.gcp.service_account_json | string     | 否    |                                   |              | GCP 服务账号 JSON 文件的内容。 |
| instances.auth.gcp.max_ttl          | integer        | 否    |                                   | minimum = 1  | GCP 服务帐户 JSON 文件的内容。也可以通过设置“GCP_SERVICE_ACCOUNT”环境变量来配置 |
| instances.auth.gcp.expire_early_secs| integer        | 否    | 60                                | minimum = 0  | 在访问令牌实际过期时间之前使其过期的秒数，以避免边缘情况。 |
| instances.options                   | object         | 否    |                                   |              | 模型配置。除了 `model` 之外，您还可以配置其他参数，它们将在请求体中转发到上游 LLM 服务。例如，如果您使用 OpenAI、DeepSeek 或 AIMLAPI，可以配置其他参数，如 `max_tokens`、`temperature`、`top_p` 和 `stream`。有关更多可用选项，请参阅您的 LLM 提供商的 API 文档。 |
| instances.options.model             | string         | 否    |                                   |              | LLM 模型的名称，如 `gpt-4` 或 `gpt-3.5`。有关更多可用模型，请参阅您的 LLM 提供商的 API 文档。 |
| logging                             | object         | 否    |                                   |              | 日志配置。 |
| logging.summaries                   | boolean        | 否    | false                           |              | 如果为 true，记录请求 LLM 模型、持续时间、请求和响应令牌。 |
| logging.payloads                    | boolean        | 否    | false                           |              | 如果为 true，记录请求和响应负载。 |
| logging.override                    | object         | 否    |                                   |              | 覆盖设置。 |
| logging.override.endpoint           | string         | 否    |                                   |              | 用于替换默认端点的 LLM 提供商端点。如果未配置，插件使用默认的 OpenAI 端点 `https://api.openai.com/v1/chat/completions`。 |
| checks                              | object         | 否    |                                   |              | 健康检查配置。请注意，目前 OpenAI、DeepSeek 和 AIMLAPI 不提供官方健康检查端点。您可以在 `openai-compatible` 提供商下配置的其他 LLM 服务可能有可用的健康检查端点。 |
| checks.active                       | object         | 是     |                                   |              | 主动健康检查配置。 |
| checks.active.type                  | string         | 否    | http                            | [http, https, tcp] | 健康检查连接类型。 |
| checks.active.timeout               | number         | 否    | 1                               |              | 健康检查超时时间（秒）。 |
| checks.active.concurrency           | integer        | 否    | 10                              |              | 同时检查的上游节点数量。 |
| checks.active.host                  | string         | 否    |                                   |              | HTTP 主机。 |
| checks.active.port                  | integer        | 否    |                                   | 1 到 65535（包含） | HTTP 端口。 |
| checks.active.http_path             | string         | 否    | /                               |              | HTTP 探测请求的路径。 |
| checks.active.https_verify_certificate | boolean   | 否    | true                            |              | 如果为 true，验证节点的 TLS 证书。 |
| timeout                             | integer        | 否    | 30000                           | 大于或等于 1 | 请求 LLM 服务时的请求超时时间（毫秒）。 |
| keepalive                           | boolean        | 否    | true                            |              | 如果为 true，在请求 LLM 服务时保持连接活跃。 |
| keepalive_timeout                   | integer        | 否    | 60000                           | 大于或等于 1000 | 请求 LLM 服务时的请求超时时间（毫秒）。 |
| keepalive_pool                      | integer        | 否    | 30                              |              | 连接 LLM 服务时的保活池大小。 |
| ssl_verify                          | boolean        | 否    | true                            |              | 如果为 true，验证 LLM 服务的证书。 |

## 示例

以下示例演示了如何为不同场景配置 `ai-proxy-multi`。

:::note

您可以使用以下命令从 `config.yaml` 获取 `admin_key` 并保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 实例间负载均衡

以下示例演示了如何配置两个模型进行负载均衡，将 80% 的流量转发到一个实例，20% 转发到另一个实例。

为了演示和更容易区分，您将配置一个 OpenAI 实例和一个 DeepSeek 实例作为上游 LLM 服务。

创建路由并更新您的 LLM 提供商、模型、API 密钥和端点（如果适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-multi-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "instances": [
          {
            "name": "openai-instance",
            "provider": "openai",
            "weight": 8,
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
      }
    }
  }'
```

向路由发送 10 个 POST 请求，在请求体中包含系统提示和示例用户问题，以查看转发到 OpenAI 和 DeepSeek 的请求数量：

```shell
openai_count=0
deepseek_count=0

for i in {1..10}; do
  model=$(curl -s "http://127.0.0.1:9080/anything" -X POST \
    -H "Content-Type: application/json" \
    -d '{
      "messages": [
        { "role": "system", "content": "You are a mathematician" },
        { "role": "user", "content": "What is 1+1?" }
      ]
    }' | jq -r '.model')

  if [[ "$model" == *"gpt-4"* ]]; then
    ((openai_count++))
  elif [[ "$model" == "deepseek-chat" ]]; then
    ((deepseek_count++))
  fi
done

echo "OpenAI responses: $openai_count"
echo "DeepSeek responses: $deepseek_count"
```

您应该看到类似以下的响应：

```text
OpenAI responses: 8
DeepSeek responses: 2
```

### 配置实例优先级和速率限制

以下示例演示了如何配置两个具有不同优先级的模型，并在优先级较高的实例上应用速率限制。在 `fallback_strategy` 设置为 `["rate_limiting"]` 的情况下，一旦高优先级实例的速率限制配额完全消耗，插件应继续将请求转发到低优先级实例。

创建路由并更新您的 LLM 提供商、模型、API 密钥和端点（如果适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-multi-route",
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

由于 `total_tokens` 值超过了配置的 `10` 配额，预计在 60 秒窗口内的下一个请求将转发到另一个实例。

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
```#
## 按消费者进行负载均衡和速率限制

以下示例演示了如何配置两个模型进行负载均衡，并按消费者应用速率限制。

创建消费者 `johndoe` 并在 `openai-instance` 实例上设置 60 秒窗口内 10 个令牌的速率限制配额：

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

创建另一个消费者 `janedoe` 并在 `deepseek-instance` 实例上设置 60 秒窗口内 10 个令牌的速率限制配额：

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

创建路由并更新您的 LLM 提供商、模型、API 密钥和端点（如果适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-multi-route",
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

向路由发送 POST 请求，不带任何消费者密钥：

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

由于 `total_tokens` 值超过了 `johndoe` 的 `openai` 实例配置配额，预计在 60 秒窗口内来自 `johndoe` 的下一个请求将转发到 `deepseek` 实例。

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

由于 `total_tokens` 值超过了 `janedoe` 的 `deepseek` 实例配置配额，预计在 60 秒窗口内来自 `janedoe` 的下一个请求将转发到 `openai` 实例。

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
        "content": "Sure, here are Newton's three laws of motion:\n\n1) Newton's First Law, also known as the Law of Inertia, states that an object at rest will stay at rest, and an object in motion will stay in motion, unless acted on by an external force. In simple words, this law suggests that an object will keep doing whatever it is doing until something causes it to do otherwise. \n\n2) Newton's Second Law states that the force acting on an object is equal to the mass of that object times its acceleration (F=ma). This means that force is directly proportional to mass and acceleration. The heavier the object and the faster it accelerates, the greater the force.\n\n3) Newton's Third Law, also known as the law of action and reaction, states that for every action, there is an equal and opposite reaction. Essentially, any force exerted onto a body will create a force of equal magnitude but in the opposite direction on the object that exerted the first force.\n\nRemember, these laws become less accurate when considering speeds near the speed of light (where Einstein's theory of relativity becomes more appropriate) or objects very small or very large. However, for everyday situations, they provide a good model of how things move.",
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

### 限制完成令牌的最大数量

以下示例演示了如何在生成聊天完成时限制使用的 `completion_tokens` 数量。

为了演示和更容易区分，您将配置一个 OpenAI 实例和一个 DeepSeek 实例作为上游 LLM 服务。

创建路由并更新您的 LLM 提供商、模型、API 密钥和端点（如果适用）：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-multi-route",
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
              "model": "gpt-4",
              "max_tokens": 50
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
              "model": "deepseek-chat",
              "max_tokens": 100
            }
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
      { "role": "user", "content": "Explain Newtons law" }
    ]
  }'
```

如果请求被代理到 OpenAI，您应该看到类似以下的响应，其中内容根据 50 个 `max_tokens` 阈值被截断：

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Newton's Laws of Motion are three physical laws that form the bedrock for classical mechanics. They describe the relationship between a body and the forces acting upon it, and the body'",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 50,
    "total_tokens": 70,
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

如果请求被代理到 DeepSeek，您应该看到类似以下的响应，其中内容根据 100 个 `max_tokens` 阈值被截断：

```json
{
  ...,
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Newton's Laws of Motion are three fundamental principles that form the foundation of classical mechanics. They describe the relationship between a body and the forces acting upon it, and the body's motion in response to those forces. Here's a brief explanation of each law:\n\n1. **Newton's First Law (Law of Inertia):**\n   - **Statement:** An object will remain at rest or in uniform motion in a straight line unless acted upon by an external force.\n   - **Explanation:** This law"
      },
      "logprobs": null,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 100,
    "total_tokens": 110,
    "prompt_tokens_details": {
      "cached_tokens": 0
    },
    "prompt_cache_hit_tokens": 0,
    "prompt_cache_miss_tokens": 10
  },
  "system_fingerprint": "fp_3a5770e1b4_prod0225"
}
```

### 代理到嵌入模型

以下示例演示了如何配置 `ai-proxy-multi` 插件以代理请求并在嵌入模型之间进行负载均衡。

创建路由并更新您的 LLM 提供商、嵌入模型、API 密钥和端点：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-multi-route",
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
              "model": "text-embedding-3-small"
            },
            "override": {
              "endpoint": "https://api.openai.com/v1/embeddings"
            }
          },
          {
            "name": "az-openai-instance",
            "provider": "openai-compatible",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$AZ_OPENAI_API_KEY"'"
              }
            },
            "options": {
              "model": "text-embedding-3-small"
            },
            "override": {
              "endpoint": "https://ai-plugin-developer.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2023-05-15"
            }
          }
        ]
      }
    }
  }'
```

向路由发送 POST 请求，包含输入字符串：

```shell
curl "http://127.0.0.1:9080/embeddings" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "input": "hello world"
  }'
```

您应该收到类似以下的响应：

```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "index": 0,
      "embedding": [
        -0.0067144386,
        -0.039197803,
        0.034177095,
        0.028763203,
        -0.024785956,
        -0.04201061,
        ...
      ],
    }
  ],
  "model": "text-embedding-3-small",
  "usage": {
    "prompt_tokens": 2,
    "total_tokens": 2
  }
}
```

### 启用主动健康检查

以下示例演示了如何配置 `ai-proxy-multi` 插件以代理请求并在模型之间进行负载均衡，并启用主动健康检查以提高服务可用性。您可以在一个或多个实例上启用健康检查。

创建路由并更新 LLM 提供商、嵌入模型、API 密钥和健康检查相关配置：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-multi-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "instances": [
          {
            "name": "llm-instance-1",
            "provider": "openai-compatible",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$YOUR_LLM_API_KEY"'"
              }
            },
            "options": {
              "model": "'"$YOUR_LLM_MODEL"'"
            }
          },
          {
            "name": "llm-instance-2",
            "provider": "openai-compatible",
            "weight": 0,
            "auth": {
              "header": {
                "Authorization": "Bearer '"$YOUR_LLM_API_KEY"'"
              }
            },
            "options": {
              "model": "'"$YOUR_LLM_MODEL"'"
            },
            "checks": {
              "active": {
                "type": "https",
                "host": "yourhost.com",
                "http_path": "/your/probe/path",
                "healthy": {
                  "interval": 2,
                  "successes": 1
                },
                "unhealthy": {
                  "interval": 1,
                  "http_failures": 3
                }
              }
            }
          }
        ]
      }
    }
  }'
```

为了验证，行为应与[主动健康检查](../tutorials/health-check.md)中的验证一致。

### 在访问日志中包含 LLM 信息

以下示例演示了如何在网关的访问日志中记录 LLM 请求相关信息，以改进分析和审计。以下变量可用：

* `request_llm_model`：请求中指定的 LLM 模型名称。
* `apisix_upstream_response_time`：APISIX 向上游服务发送请求并接收完整响应所花费的时间
* `request_type`：请求类型，值可能是 `traditional_http`、`ai_chat` 或 `ai_stream`。
* `llm_time_to_first_token`：从发送请求到从 LLM 服务接收第一个令牌的持续时间（毫秒）。
* `llm_model`：LLM 模型。
* `llm_prompt_tokens`：提示中的令牌数量。
* `llm_completion_tokens`：提示中的聊天完成令牌数量。

在配置文件中更新访问日志格式以包含其他 LLM 相关变量：

```yaml title="conf/config.yaml"
nginx_config:
  http:
    access_log_format: "$remote_addr - $remote_user [$time_local] $http_host \"$request_line\" $status $body_bytes_sent $request_time \"$http_referer\" \"$http_user_agent\" $upstream_addr $upstream_status $apisix_upstream_response_time \"$upstream_scheme://$upstream_host$upstream_uri\" \"$apisix_request_id\" \"$request_type\" \"$llm_time_to_first_token\" \"$llm_model\" \"$request_llm_model\"  \"$llm_prompt_tokens\" \"$llm_completion_tokens\""
```

重新加载 APISIX 以使配置更改生效。

接下来，使用 `ai-proxy-multi` 插件创建路由并发送请求。例如，如果请求转发到 OpenAI 并且您收到以下响应：

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
        "refusal": null,
        "annotations": []
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
    ...
  },
  "service_tier": "default",
  "system_fingerprint": null
}
```

在网关的访问日志中，您应该看到类似以下的日志条目：

```text
192.168.215.1 - - [21/Mar/2025:04:28:03 +0000] api.openai.com "POST /anything HTTP/1.1" 200 804 2.858 "-" "curl/8.6.0" - - - 5765 "http://api.openai.com" "5c5e0b95f8d303cb81e4dc456a4b12d9" "ai_chat" "2858" "gpt-4" "gpt-4" "23" "8"
```

访问日志条目显示请求类型为 `ai_chat`，Apisix 上游响应时间为 `5765` 毫秒，首次令牌时间为 `2858` 毫秒，请求的 LLM 模型为 `gpt-4`。LLM 模型为 `gpt-4`，提示令牌使用量为 `23`，完成令牌使用量为 `8`。
