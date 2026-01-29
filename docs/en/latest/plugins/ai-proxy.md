---
title: ai-proxy
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy
  - AI
  - LLM
description: The ai-proxy Plugin simplifies access to LLM and embedding models providers by converting Plugin configurations into the required request format for OpenAI, DeepSeek, Azure, AIMLAPI, Anthropic, OpenRouter, Gemini, Vertex AI, and other OpenAI-compatible APIs.
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

## Description

The `ai-proxy` Plugin simplifies access to LLM and embedding models by transforming Plugin configurations into the designated request format. It supports the integration with OpenAI, DeepSeek, Azure, AIMLAPI, Anthropic, OpenRouter, Gemini, Vertex AI, and other OpenAI-compatible APIs.

In addition, the Plugin also supports logging LLM request information in the access log, such as token usage, model, time to the first response, and more.

## Request Format

| Name               | Type   | Required | Description                                         |
| ------------------ | ------ | -------- | --------------------------------------------------- |
| `messages`         | Array  | True      | An array of message objects.                        |
| `messages.role`    | String | True      | Role of the message (`system`, `user`, `assistant`).|
| `messages.content` | String | True      | Content of the message.                             |

## Attributes

| Name               | Type    | Required | Default | Valid values                              | Description |
|--------------------|--------|----------|---------|------------------------------------------|-------------|
| provider          | string  | True     |         | [openai, deepseek, azure-openai, aimlapi, anthropic, openrouter, gemini, vertex-ai, openai-compatible] | LLM service provider. When set to `openai`, the Plugin will proxy the request to `https://api.openai.com/chat/completions`. When set to `deepseek`, the Plugin will proxy the request to `https://api.deepseek.com/chat/completions`. When set to `aimlapi`, the Plugin uses the OpenAI-compatible driver and proxies the request to `https://api.aimlapi.com/v1/chat/completions` by default. When set to `anthropic`, the Plugin will proxy the request to `https://api.anthropic.com/v1/chat/completions` by default. When set to `openrouter`, the Plugin uses the OpenAI-compatible driver and proxies the request to `https://openrouter.ai/api/v1/chat/completions` by default. When set to `gemini`, the Plugin uses the OpenAI-compatible driver and proxies the request to `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions` by default. When set to `vertex-ai`, the Plugin will proxy the request to `https://aiplatform.googleapis.com` by default and requires `provider_conf` or `override`. When set to `openai-compatible`, the Plugin will proxy the request to the custom endpoint configured in `override`. |
| provider_conf      | object  | False    |         |                                          | Configuration for the specific provider. Required when `provider` is set to `vertex-ai` and `override` is not configured. |
| provider_conf.project_id | string | True |       |                                          | Google Cloud Project ID.  |
| provider_conf.region | string | True   |         |                                          | Google Cloud Region.  |
| auth             | object  | True     |         |                                          | Authentication configurations. |
| auth.header      | object  | False    |         |                                          | Authentication headers. At least one of `header` or `query` must be configured. |
| auth.query       | object  | False    |         |                                          | Authentication query parameters. At least one of `header` or `query` must be configured. |
| auth.gcp         | object  | False    |         |                                          | Configuration for Google Cloud Platform (GCP) authentication. |
| auth.gcp.service_account_json | string | False |  |                                          | Content of the GCP service account JSON file. This can also be configured by setting the `GCP_SERVICE_ACCOUNT` environment variable. |
| auth.gcp.max_ttl | integer | False    |         | minimum = 1                              | Maximum TTL (in seconds) for caching the GCP access token. |
| auth.gcp.expire_early_secs | integer | False | 60 | minimum = 0                              | Seconds to expire the access token before its actual expiration time to avoid edge cases. |
| options         | object  | False    |         |                                          | Model configurations. In addition to `model`, you can configure additional parameters and they will be forwarded to the upstream LLM service in the request body. For instance, if you are working with OpenAI, you can configure additional parameters such as `temperature`, `top_p`, and `stream`. See your LLM provider's API documentation for more available options.  |
| options.model   | string  | False    |         |                                          | Name of the LLM model, such as `gpt-4` or `gpt-3.5`. Refer to the LLM provider's API documentation for available models. |
| override        | object  | False    |         |                                          | Override setting. |
| override.endpoint | string | False    |         |                                          | Custom LLM provider endpoint, required when `provider` is `openai-compatible`. |
| logging        | object  | False    |         |                                          | Logging configurations. |
| logging.summaries | boolean | False | false |                                          | If true, logs request LLM model, duration, request, and response tokens. |
| logging.payloads  | boolean | False | false |                                          | If true, logs request and response payload. |
| timeout        | integer | False    | 30000    | ≥ 1                                      | Request timeout in milliseconds when requesting the LLM service. |
| keepalive      | boolean | False    | true   |                                          | If true, keeps the connection alive when requesting the LLM service. |
| keepalive_timeout | integer | False | 60000  | ≥ 1000                                   | Keepalive timeout in milliseconds when connecting to the LLM service. |
| keepalive_pool | integer | False    | 30       |                                          | Keepalive pool size for the LLM service connection. |
| ssl_verify     | boolean | False    | true   |                                          | If true, verifies the LLM service's certificate. |

## Examples

The examples below demonstrate how you can configure `ai-proxy` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Proxy to OpenAI

The following example demonstrates how you can configure the API key, model, and other parameters in the `ai-proxy` Plugin and configure the Plugin on a Route to proxy user prompts to OpenAI.

Obtain the OpenAI [API key](https://openai.com/blog/openai-api) and save it to an environment variable:

```shell
export OPENAI_API_KEY=<your-api-key>
```

Create a Route and configure the `ai-proxy` Plugin as such:

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

Send a POST request to the Route with a system prompt and a sample user question in the request body:

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

You should receive a response similar to the following:

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

### Proxy to DeepSeek

The following example demonstrates how you can configure the `ai-proxy` Plugin to proxy requests to DeekSeek.

Obtain the DeekSeek API key and save it to an environment variable:

```shell
export DEEPSEEK_API_KEY=<your-api-key>
```

Create a Route and configure the `ai-proxy` Plugin as such:

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

Send a POST request to the Route with a sample question in the request body:

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

You should receive a response similar to the following:

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

### Proxy to Azure OpenAI

The following example demonstrates how you can configure the `ai-proxy` Plugin to proxy requests to other LLM services, such as Azure OpenAI.

Obtain the Azure OpenAI API key and save it to an environment variable:

```shell
export AZ_OPENAI_API_KEY=<your-api-key>
```

Create a Route and configure the `ai-proxy` Plugin as such:

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

Send a POST request to the Route with a sample question in the request body:

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

You should receive a response similar to the following:

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

### Proxy to Embedding Models

The following example demonstrates how you can configure the `ai-proxy` Plugin to proxy requests to embedding models. This example will use the OpenAI embedding model endpoint.

Obtain the OpenAI [API key](https://openai.com/blog/openai-api) and save it to an environment variable:

```shell
export OPENAI_API_KEY=<your-api-key>
```

Create a Route and configure the `ai-proxy` Plugin as such:

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

Send a POST request to the Route with an input string:

```shell
curl "http://127.0.0.1:9080/embeddings" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "input": "hello world"
  }'
```

You should receive a response similar to the following:

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

### Include LLM Information in Access Log

The following example demonstrates how you can log LLM request related information in the gateway's access log to improve analytics and audit. The following variables are available:

* `request_llm_model`: LLM model name specified in the request.
* `apisix_upstream_response_time`: Time taken for APISIX to send the request to the upstream service and receive the full response
* `request_type`: Type of request, where the value could be `traditional_http`, `ai_chat`, or `ai_stream`.
* `llm_time_to_first_token`: Duration from request sending to the first token received from the LLM service, in milliseconds.
* `llm_model`: LLM model.
* `llm_prompt_tokens`: Number of tokens in the prompt.
* `llm_completion_tokens`: Number of chat completion tokens in the prompt.

Update the access log format in your configuration file to include additional LLM related variables:

```yaml title="conf/config.yaml"
nginx_config:
  http:
    access_log_format: "$remote_addr - $remote_user [$time_local] $http_host \"$request_line\" $status $body_bytes_sent $request_time \"$http_referer\" \"$http_user_agent\" $upstream_addr $upstream_status $apisix_upstream_response_time \"$upstream_scheme://$upstream_host$upstream_uri\" \"$apisix_request_id\" \"$request_type\" \"$llm_time_to_first_token\" \"$llm_model\" \"$request_llm_model\"  \"$llm_prompt_tokens\" \"$llm_completion_tokens\""
```

Reload APISIX for configuration changes to take effect.

Now if you create a Route and send a request following the [Proxy to OpenAI example](#proxy-to-openai), you should receive a response similar to the following:

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

In the gateway's access log, you should see a log entry similar to the following:

```text
192.168.215.1 - - [21/Mar/2025:04:28:03 +0000] api.openai.com "POST /anything HTTP/1.1" 200 804 2.858 "-" "curl/8.6.0" - - - 5765 "http://api.openai.com" "5c5e0b95f8d303cb81e4dc456a4b12d9" "ai_chat" "2858" "gpt-4" "gpt-4" "23" "8"
```

The access log entry shows the request type is `ai_chat`, Apisix upstream response time is `5765` milliseconds, time to first token is `2858` milliseconds, Requested LLM model is `gpt-4`. LLM model is `gpt-4`, prompt token usage is `23`, and completion token usage is `8`.
