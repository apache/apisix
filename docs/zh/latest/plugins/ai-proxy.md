---
title: ai-proxy
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-proxy
  - AI
  - LLM
description: ai-proxy 插件通过将插件配置转换为所需的请求格式，简化了对 LLM 和嵌入模型提供商的访问，支持 OpenAI、DeepSeek、Azure、AIMLAPI、Anthropic、OpenRouter、Gemini、Vertex AI 和其他 OpenAI 兼容的 API。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-proxy" />
</head>

## 描述

`ai-proxy` 插件通过将插件配置转换为指定的请求格式，简化了对 LLM 和嵌入模型的访问。它支持与 OpenAI、DeepSeek、Azure、AIMLAPI、Anthropic、OpenRouter、Gemini、Vertex AI 和其他 OpenAI 兼容的 API 集成。

此外，该插件还支持在访问日志中记录 LLM 请求信息，如令牌使用量、模型、首次响应时间等。

## 请求格式

| 名称               | 类型   | 必选项 | 描述                                         |
| ------------------ | ------ | -------- | --------------------------------------------------- |
| `messages`         | Array  | 是      | 消息对象数组。                        |
| `messages.role`    | String | 是      | 消息的角色（`system`、`user`、`assistant`）。|
| `messages.content` | String | 是      | 消息的内容。                             |

## 属性

| 名称               | 类型    | 必选项 | 默认值 | 有效值                              | 描述 |
|--------------------|--------|----------|---------|------------------------------------------|-------------|
| provider          | string  | 是     |         | [openai, deepseek, azure-openai, aimlapi, anthropic, openrouter, gemini, vertex-ai, openai-compatible] | LLM 服务提供商。当设置为 `openai` 时，插件将代理请求到 `https://api.openai.com/chat/completions`。当设置为 `deepseek` 时，插件将代理请求到 `https://api.deepseek.com/chat/completions`。当设置为 `aimlapi` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `https://api.aimlapi.com/v1/chat/completions`。当设置为 `anthropic` 时，插件将代理请求到 `https://api.anthropic.com/v1/chat/completions`。当设置为 `openrouter` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `https://openrouter.ai/api/v1/chat/completions`。当设置为 `gemini` 时，插件使用 OpenAI 兼容驱动程序，默认将请求代理到 `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`。当设置为 `vertex-ai` 时，插件默认将请求代理到 `https://aiplatform.googleapis.com`，且需要配置 `provider_conf` 或 `override`。当设置为 `openai-compatible` 时，插件将代理请求到在 `override` 中配置的自定义端点。 |
| provider_conf     | object  | 否     |         |                                          | 特定提供商的配置。当 `provider` 设置为 `vertex-ai` 且未配置 `override` 时必填。 |
| provider_conf.project_id | string | 是 |       |                                          | Google Cloud 项目 ID。 |
| provider_conf.region | string | 是   |         |                                          | Google Cloud 区域。 |
| auth             | object  | 是     |         |                                          | 身份验证配置。 |
| auth.header      | object  | 否    |         |                                          | 身份验证标头。必须配置 `header` 或 `query` 中的至少一个。 |
| auth.query       | object  | 否    |         |                                          | 身份验证查询参数。必须配置 `header` 或 `query` 中的至少一个。 |
| auth.gcp         | object  | 否    |         |                                          | Google Cloud Platform (GCP) 身份验证配置。 |
| auth.gcp.service_account_json | string | 否 |  |                                          | GCP 服务账号 JSON 文件的内容。 |
| auth.gcp.max_ttl | integer | 否    |         | minimum = 1                              | GCP 服务帐户 JSON 文件的内容。也可以通过设置“GCP_SERVICE_ACCOUNT”环境变量来配置。 |
| auth.gcp.expire_early_secs | integer | 否 | 60 | minimum = 0                              | 在访问令牌实际过期时间之前使其过期的秒数，以避免边缘情况。 |
| options         | object  | 否    |         |                                          | 模型配置。除了 `model` 之外，您还可以配置其他参数，它们将在请求体中转发到上游 LLM 服务。例如，如果您使用 OpenAI，可以配置其他参数，如 `temperature`、`top_p` 和 `stream`。有关更多可用选项，请参阅您的 LLM 提供商的 API 文档。  |
| options.model   | string  | 否    |         |                                          | LLM 模型的名称，如 `gpt-4` 或 `gpt-3.5`。请参阅 LLM 提供商的 API 文档以了解可用模型。 |
| override        | object  | 否    |         |                                          | 覆盖设置。 |
| override.endpoint | string | 否    |         |                                          | 自定义 LLM 提供商端点，当 `provider` 为 `openai-compatible` 时必需。 |
| logging        | object  | 否    |         |                                          | 日志配置。 |
| logging.summaries | boolean | 否 | false |                                          | 如果为 true，记录请求 LLM 模型、持续时间、请求和响应令牌。 |
| logging.payloads  | boolean | 否 | false |                                          | 如果为 true，记录请求和响应负载。 |
| timeout        | integer | 否    | 30000    | ≥ 1                                      | 请求 LLM 服务时的请求超时时间（毫秒）。 |
| keepalive      | boolean | 否    | true   |                                          | 如果为 true，在请求 LLM 服务时保持连接活跃。 |
| keepalive_timeout | integer | 否 | 60000  | ≥ 1000                                   | 连接到 LLM 服务时的保活超时时间（毫秒）。 |
| keepalive_pool | integer | 否    | 30       |                                          | LLM 服务连接的保活池大小。 |
| ssl_verify     | boolean | 否    | true   |                                          | 如果为 true，验证 LLM 服务的证书。 |

## 示例

以下示例演示了如何为不同场景配置 `ai-proxy`。

:::note

您可以使用以下命令从 `config.yaml` 获取 `admin_key` 并保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 代理到 OpenAI

以下示例演示了如何在 `ai-proxy` 插件中配置 API 密钥、模型和其他参数，并在路由上配置插件以将用户提示代理到 OpenAI。

获取 OpenAI [API 密钥](https://openai.com/blog/openai-api)并保存到环境变量：

```shell
export OPENAI_API_KEY=<your-api-key>
```

创建路由并配置 `ai-proxy` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-route",
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
        "options":{
          "model": "gpt-4"
        }
      }
    }
  }'
```

向路由发送 POST 请求，在请求体中包含系统提示和示例用户问题：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H "Host: api.openai.com" \
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
  ...
}
```

### 代理到 DeepSeek

以下示例演示了如何配置 `ai-proxy` 插件以将请求代理到 DeepSeek。

获取 DeepSeek API 密钥并保存到环境变量：

```shell
export DEEPSEEK_API_KEY=<your-api-key>
```

创建路由并配置 `ai-proxy` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "deepseek",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
          }
        },
        "options": {
          "model": "deepseek-chat"
        }
      }
    }
  }'
```

向路由发送 POST 请求，在请求体中包含示例问题：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "system",
        "content": "You are an AI assistant that helps people find information."
      },
      {
        "role": "user",
        "content": "Write me a 50-word introduction for Apache APISIX."
      }
    ]
  }'
```

您应该收到类似以下的响应：

```json
{
  ...
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Apache APISIX is a dynamic, real-time, high-performance API gateway and cloud-native platform. It provides rich traffic management features like load balancing, dynamic upstream, canary release, circuit breaking, authentication, observability, and more. Designed for microservices and serverless architectures, APISIX ensures scalability, security, and seamless integration with modern DevOps workflows."
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

### 代理到 Azure OpenAI

以下示例演示了如何配置 `ai-proxy` 插件以将请求代理到其他 LLM 服务，如 Azure OpenAI。

获取 Azure OpenAI API 密钥并保存到环境变量：

```shell
export AZ_OPENAI_API_KEY=<your-api-key>
```

创建路由并配置 `ai-proxy` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai-compatible",
        "auth": {
          "header": {
            "api-key": "'"$AZ_OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "override": {
          "endpoint": "https://api7-auzre-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"
        }
      }
    }
  }'
```

向路由发送 POST 请求，在请求体中包含示例问题：

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "system",
        "content": "You are an AI assistant that helps people find information."
      },
      {
        "role": "user",
        "content": "Write me a 50-word introduction for Apache APISIX."
      }
    ],
    "max_tokens": 800,
    "temperature": 0.7,
    "frequency_penalty": 0,
    "presence_penalty": 0,
    "top_p": 0.95,
    "stop": null
  }'
```

您应该收到类似以下的响应：

```json
{
  "choices": [
    {
      ...,
      "message": {
        "content": "Apache APISIX is a modern, cloud-native API gateway built to handle high-performance and low-latency use cases. It offers a wide range of features, including load balancing, rate limiting, authentication, and dynamic routing, making it an ideal choice for microservices and cloud-native architectures.",
        "role": "assistant"
      }
    }
  ],
  ...
}
```

### 代理到嵌入模型

以下示例演示了如何配置 `ai-proxy` 插件以将请求代理到嵌入模型。此示例将使用 OpenAI 嵌入模型端点。

获取 OpenAI [API 密钥](https://openai.com/blog/openai-api)并保存到环境变量：

```shell
export OPENAI_API_KEY=<your-api-key>
```

创建路由并配置 `ai-proxy` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-route",
    "uri": "/embeddings",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "text-embedding-3-small",
          "encoding_format": "float"
        },
        "override": {
          "endpoint": "https://api.openai.com/v1/embeddings"
        }
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

现在，如果您创建路由并按照[代理到 OpenAI 示例](#代理到-openai)发送请求，您应该收到类似以下的响应：

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
