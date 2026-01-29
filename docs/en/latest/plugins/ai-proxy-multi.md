---
title: ai-proxy-multi
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy-multi
  - AI
  - LLM
description: The ai-proxy-multi Plugin extends the capabilities of ai-proxy with load balancing, retries, fallbacks, and health chekcs, simplifying the integration with OpenAI, DeepSeek, Azure, AIMLAPI, Anthropic, OpenRouter, Gemini, Vertex AI, and other OpenAI-compatible APIs.
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

## Description

The `ai-proxy-multi` Plugin simplifies access to LLM and embedding models by transforming Plugin configurations into the designated request format for OpenAI, DeepSeek, Azure, AIMLAPI, Anthropic, OpenRouter, Gemini, Vertex AI, and other OpenAI-compatible APIs. It extends the capabilities of [`ai-proxy`](./ai-proxy.md) with load balancing, retries, fallbacks, and health checks.

In addition, the Plugin also supports logging LLM request information in the access log, such as token usage, model, time to the first response, and more.

## Request Format

| Name               | Type   | Required | Description                                         |
| ------------------ | ------ | -------- | --------------------------------------------------- |
| `messages`         | Array  | True      | An array of message objects.                        |
| `messages.role`    | String | True      | Role of the message (`system`, `user`, `assistant`).|
| `messages.content` | String | True      | Content of the message.                             |

## Attributes

| Name                               | Type            | Required | Default                           | Valid Values | Description |
|------------------------------------|----------------|----------|-----------------------------------|--------------|-------------|
| fallback_strategy                  | string or array         | False    |  | string: "instance_health_and_rate_limiting", "http_429", "http_5xx"<br />array: ["rate_limiting", "http_429", "http_5xx"] | Fallback strategy. When set, the Plugin will check whether the specified instance’s token has been exhausted when a request is forwarded. If so, forward the request to the next instance regardless of the instance priority. When not set, the Plugin will not forward the request to low priority instances when token of the high priority instance is exhausted. |
| balancer                           | object         | False    |                                   |              | Load balancing configurations. |
| balancer.algorithm                 | string         | False    | roundrobin                     | [roundrobin, chash] | Load balancing algorithm. When set to `roundrobin`, weighted round robin algorithm is used. When set to `chash`, consistent hashing algorithm is used. |
| balancer.hash_on                   | string         | False    |                                   | [vars, headers, cookie, consumer, vars_combinations] | Used when `type` is `chash`. Support hashing on [NGINX variables](https://nginx.org/en/docs/varindex.html), headers, cookie, consumer, or a combination of [NGINX variables](https://nginx.org/en/docs/varindex.html). |
| balancer.key                       | string         | False    |                                   |              | Used when `type` is `chash`. When `hash_on` is set to `header` or `cookie`, `key` is required. When `hash_on` is set to `consumer`, `key` is not required as the consumer name will be used as the key automatically. |
| instances                          | array[object]  | True     |                                   |              | LLM instance configurations. |
| instances.name                     | string         | True     |                                   |              | Name of the LLM service instance. |
| instances.provider                 | string         | True     |                                   | [openai, deepseek, azure-openai, aimlapi, anthropic, openrouter, gemini, vertex-ai, openai-compatible] | LLM service provider. When set to `openai`, the Plugin will proxy the request to `api.openai.com`. When set to `deepseek`, the Plugin will proxy the request to `api.deepseek.com`. When set to `aimlapi`, the Plugin uses the OpenAI-compatible driver and proxies the request to `api.aimlapi.com` by default. When set to `anthropic`, the Plugin will proxy the request to `api.anthropic.com` by default. When set to `openrouter`, the Plugin uses the OpenAI-compatible driver and proxies the request to `openrouter.ai` by default. When set to `gemini`, the Plugin uses the OpenAI-compatible driver and proxies the request to `generativelanguage.googleapis.com` by default. When set to `vertex-ai`, the Plugin will proxy the request to `aiplatform.googleapis.com` by default and requires `provider_conf` or `override`. When set to `openai-compatible`, the Plugin will proxy the request to the custom endpoint configured in `override`. |
| instances.provider_conf            | object         | False     |                                   |              | Configuration for the specific provider. Required when `provider` is set to `vertex-ai` and `override` is not configured. |
| instances.provider_conf.project_id | string         | True     |                                   |              | Google Cloud Project ID. |
| instances.provider_conf.region     | string         | True     |                                   |              | Google Cloud Region. |
| instances.priority                  | integer        | False    | 0                               |              | Priority of the LLM instance in load balancing. `priority` takes precedence over `weight`. |
| instances.weight                    | string         | True     | 0                               | greater or equal to 0 | Weight of the LLM instance in load balancing. |
| instances.auth                      | object         | True     |                                   |              | Authentication configurations. |
| instances.auth.header               | object         | False    |                                   |              | Authentication headers. At least one of the `header` and `query` should be configured. |
| instances.auth.query                | object         | False    |                                   |              | Authentication query parameters. At least one of the `header` and `query` should be configured. |
| instances.auth.gcp                  | object         | False    |                                   |              | Configuration for Google Cloud Platform (GCP) authentication. |
| instances.auth.gcp.service_account_json | string     | False    |                                   |              | Content of the GCP service account JSON file. This can also be configured by setting the `GCP_SERVICE_ACCOUNT` environment variable. |
| instances.auth.gcp.max_ttl          | integer        | False    |                                   | minimum = 1  | Maximum TTL (in seconds) for caching the GCP access token. |
| instances.auth.gcp.expire_early_secs| integer        | False    | 60                                | minimum = 0  | Seconds to expire the access token before its actual expiration time to avoid edge cases. |
| instances.options                   | object         | False    |                                   |              | Model configurations. In addition to `model`, you can configure additional parameters and they will be forwarded to the upstream LLM service in the request body. For instance, if you are working with OpenAI, DeepSeek, or AIMLAPI, you can configure additional parameters such as `max_tokens`, `temperature`, `top_p`, and `stream`. See your LLM provider's API documentation for more available options. |
| instances.options.model             | string         | False    |                                   |              | Name of the LLM model, such as `gpt-4` or `gpt-3.5`. See your LLM provider's API documentation for more available models. |
| logging                             | object         | False    |                                   |              | Logging configurations. |
| logging.summaries                   | boolean        | False    | false                           |              | If true, log request LLM model, duration, request, and response tokens. |
| logging.payloads                    | boolean        | False    | false                           |              | If true, log request and response payload. |
| logging.override                    | object         | False    |                                   |              | Override setting. |
| logging.override.endpoint           | string         | False    |                                   |              | LLM provider endpoint to replace the default endpoint with. If not configured, the Plugin uses the default OpenAI endpoint `https://api.openai.com/v1/chat/completions`. |
| checks                              | object         | False    |                                   |              | Health check configurations. Note that at the moment, OpenAI, DeepSeek, and AIMLAPI do not provide an official health check endpoint. Other LLM services that you can configure under `openai-compatible` provider may have available health check endpoints. |
| checks.active                       | object         | True     |                                   |              | Active health check configurations. |
| checks.active.type                  | string         | False    | http                            | [http, https, tcp] | Type of health check connection. |
| checks.active.timeout               | number         | False    | 1                               |              | Health check timeout in seconds. |
| checks.active.concurrency           | integer        | False    | 10                              |              | Number of upstream nodes to be checked at the same time. |
| checks.active.host                  | string         | False    |                                   |              | HTTP host. |
| checks.active.port                  | integer        | False    |                                   | between 1 and 65535 inclusive | HTTP port. |
| checks.active.http_path             | string         | False    | /                               |              | Path for HTTP probing requests. |
| checks.active.https_verify_certificate | boolean   | False    | true                            |              | If true, verify the node's TLS certificate. |
| timeout                             | integer        | False    | 30000                           | greater than or equal to 1 | Request timeout in milliseconds when requesting the LLM service. |
| keepalive                           | boolean        | False    | true                            |              | If true, keep the connection alive when requesting the LLM service. |
| keepalive_timeout                   | integer        | False    | 60000                           | greater than or equal to 1000 | Request timeout in milliseconds when requesting the LLM service. |
| keepalive_pool                      | integer        | False    | 30                              |              | Keepalive pool size for when connecting with the LLM service. |
| ssl_verify                          | boolean        | False    | true                            |              | If true, verify the LLM service's certificate. |

## Examples

The examples below demonstrate how you can configure `ai-proxy-multi` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Load Balance between Instances

The following example demonstrates how you can configure two models for load balancing, forwarding 80% of the traffic to one instance and 20% to the other.

For demonstration and easier differentiation, you will be configuring one OpenAI instance and one DeepSeek instance as the upstream LLM services.

Create a Route as such and update with your LLM providers, models, API keys, and endpoints if applicable:

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

Send 10 POST requests to the Route with a system prompt and a sample user question in the request body, to see the number of requests forwarded to OpenAI and DeepSeek:

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

You should see a response similar to the following:

```text
OpenAI responses: 8
DeepSeek responses: 2
```

### Configure Instance Priority and Rate Limiting

The following example demonstrates how you can configure two models with different priorities and apply rate limiting on the instance with a higher priority. In the case where `fallback_strategy` is set to `["rate_limiting"]`, the Plugin should continue to forward requests to the low priority instance once the high priority instance's rate limiting quota is fully consumed.

Create a Route as such and update with your LLM providers, models, API keys, and endpoints if applicable:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-multi-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy-multi": {
        "fallback_strategy: ["rate_limiting"],
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

Send a POST request to the Route with a system prompt and a sample user question in the request body:

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

Since the `total_tokens` value exceeds the configured quota of `10`, the next request within the 60-second window is expected to be forwarded to the other instance.

Within the same 60-second window, send another POST request to the route:

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

You should see a response similar to the following:

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

### Load Balance and Rate Limit by Consumers

The following example demonstrates how you can configure two models for load balancing and apply rate limiting by consumer.

Create a Consumer `johndoe` and a rate limiting quota of 10 tokens in a 60-second window on `openai-instance` instance:

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

Configure `key-auth` credential for `johndoe`:

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

Create another Consumer `janedoe` and a rate limiting quota of 10 tokens in a 60-second window on `deepseek-instance` instance:

```shell
curl "http://127.0.0.1:9180/apisix/admin/consumers" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "username": "johndoe",
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

Configure `key-auth` credential for `janedoe`:

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

Create a Route as such and update with your LLM providers, models, API keys, and endpoints if applicable:

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
        "fallback_strategy: ["rate_limiting"],
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

Send a POST request to the Route without any consumer key:

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

You should receive an `HTTP/1.1 401 Unauthorized` response.

Send a POST request to the Route with `johndoe`'s key:

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

Since the `total_tokens` value exceeds the configured quota of the `openai` instance for `johndoe`, the next request within the 60-second window from `johndoe` is expected to be forwarded to the `deepseek` instance.

Within the same 60-second window, send another POST request to the Route with `johndoe`'s key:

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

You should see a response similar to the following:

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

Send a POST request to the Route with `janedoe`'s key:

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

You should receive a response similar to the following:

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

Since the `total_tokens` value exceeds the configured quota of the `deepseek` instance for `janedoe`, the next request within the 60-second window from `janedoe` is expected to be forwarded to the `openai` instance.

Within the same 60-second window, send another POST request to the Route with `janedoe`'s key:

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

You should see a response similar to the following:

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

This shows `ai-proxy-multi` load balance the traffic with respect to the rate limiting rules in `ai-rate-limiting` by consumers.

### Restrict Maximum Number of Completion Tokens

The following example demonstrates how you can restrict the number of `completion_tokens` used when generating the chat completion.

For demonstration and easier differentiation, you will be configuring one OpenAI instance and one DeepSeek instance as the upstream LLM services.

Create a Route as such and update with your LLM providers, models, API keys, and endpoints if applicable:

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

Send a POST request to the Route with a system prompt and a sample user question in the request body:

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

If the request is proxied to OpenAI, you should see a response similar to the following, where the content is truncated per 50 `max_tokens` threshold:

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Newton's Laws of Motion are three physical laws that form the bedrock for classical mechanics. They describe the relationship between a body and the forces acting upon it, and the body's motion in response to those forces. \n\n1. Newton's First Law",
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

If the request is proxied to DeepSeek, you should see a response similar to the following, where the content is truncated per 100 `max_tokens` threshold:

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

### Proxy to Embedding Models

The following example demonstrates how you can configure the `ai-proxy-multi` Plugin to proxy requests and load balance between embedding models.

Create a Route as such and update with your LLM providers, embedding models, API keys, and endpoints:

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

### Enable Active Health Checks

The following example demonstrates how you can configure the `ai-proxy-multi` Plugin to proxy requests and load balance between models, and enable active health check to improve service availability. You can enable health check on one or multiple instances.

Create a Route as such and update the LLM providers, embedding models, API keys, and health check related configurations:

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

For verification, the behaviours should be consistent with the verification in [active health checks](../tutorials/health-check.md).

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

Next, create a Route with the `ai-proxy-multi` Plugin and send a request. For instance, if the request is forwarded to OpenAI and you receive the following response:

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
