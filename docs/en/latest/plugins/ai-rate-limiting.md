---
title: ai-rate-limiting
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-rate-limiting
  - AI
  - LLM
description: The ai-rate-limiting Plugin enforces token-based rate limiting for LLM service requests, preventing overuse, optimizing API consumption, and ensuring efficient resource allocation.
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

## Description

The `ai-rate-limiting` Plugin enforces token-based rate limiting for requests sent to LLM services. It helps manage API usage by controlling the number of tokens consumed within a specified time frame, ensuring fair resource allocation and preventing excessive load on the service. It is often used with [`ai-proxy`](./ai-proxy.md) or [`ai-proxy-multi`](./ai-proxy-multi.md) plugin.

## Attributes

| Name                         | Type            | Required | Default  | Valid values                                             | Description |
|------------------------------|----------------|----------|----------|---------------------------------------------------------|-------------|
| limit                        | integer        | False    |          | >0                             | The maximum number of tokens allowed within a given time interval. At least one of `limit` and `instances.limit` should be configured. Required if `rules` is not configured. |
| time_window                  | integer        | False    |          | >0                             | The time interval corresponding to the rate limiting `limit` in seconds. At least one of `time_window` and `instances.time_window` should be configured. Required if `rules` is not configured. |
| rules                        | array[object]  | False    |          |                                                         | A list of rate limiting rules. Each rule is an object containing `count`, `time_window`, and `key`. If configured, this takes precedence over `limit` and `time_window`. |
| rules.count                  | integer or string | True  |          | >0 or variable expression                              | The maximum number of tokens allowed within a given time interval. Can be a static integer or a variable expression like `$http_custom_limit`. |
| rules.time_window            | integer or string | True  |          | >0 or variable expression                              | The time interval corresponding to the rate limiting `count` in seconds. Can be a static integer or a variable expression. |
| rules.key                    | string         | True     |          |                                                         | The key to count requests by. If the configured key does not exist, the rule will not be executed. The `key` is interpreted as a combination of variables, for example: `$http_custom_a $http_custom_b`. |
| rules.header_prefix          | string         | False    |          |                                                         | Prefix for rate limit headers. If configured, the response will include `X-{header_prefix}-RateLimit-Limit`, `X-{header_prefix}-RateLimit-Remaining`, and `X-{header_prefix}-RateLimit-Reset` headers. If not configured, the index of the rule in the rules array is used as the prefix. For example, headers for the first rule will be `X-1-RateLimit-Limit`, `X-1-RateLimit-Remaining`, and `X-1-RateLimit-Reset`. |
| show_limit_quota_header      | boolean        | False    | true     |                                                         | If true, includes `X-AI-RateLimit-Limit-*`, `X-AI-RateLimit-Remaining-*`, and `X-AI-RateLimit-Reset-*` headers in the response, where `*` is the instance name. |
| limit_strategy               | string         | False    | total_tokens | [total_tokens, prompt_tokens, completion_tokens] | Type of token to apply rate limiting. `total_tokens` is the sum of `prompt_tokens` and `completion_tokens`. |
| instances                    | array[object]  | False    |          |                                                         | LLM instance rate limiting configurations. |
| instances.name               | string         | True     |          |                                                         | Name of the LLM service instance. |
| instances.limit              | integer        | True     |          | >0                             | The maximum number of tokens allowed within a given time interval for an instance. |
| instances.time_window        | integer        | True     |          | >0                             | The time interval corresponding to the rate limiting `limit` in seconds for an instance. |
| rejected_code                | integer        | False    | 503      |  [200, 599]                           | The HTTP status code returned when a request exceeding the quota is rejected. |
| rejected_msg                 | string         | False    |          |                                           | The response body returned when a request exceeding the quota is rejected. |

## Examples

The examples below demonstrate how you can configure `ai-rate-limiting` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Apply Rate Limiting with `ai-proxy`

The following example demonstrates how you can use `ai-proxy` to proxy LLM traffic and use `ai-rate-limiting` to configure token-based rate limiting on the instance.

Create a Route as such and update with your LLM providers, models, API keys, and endpoints, if applicable:

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

If the rate limiting quota of 300 prompt tokens has been consumed in a 30-second window, all additional requests will be rejected.

### Rate Limit One Instance Among Multiple

The following example demonstrates how you can use `ai-proxy-multi` to configure two models for load balancing, forwarding 80% of the traffic to one instance and 20% to the other. Additionally, use `ai-rate-limiting` to configure token-based rate limiting on the instance that receives 80% of the traffic, such that when the configured quota is fully consumed, the additional traffic will be forwarded to the other instance.

Create a Route which applies rate limiting quota of 100 total tokens in a 30-second window on the `deepseek-instance-1` instance, and update with your LLM providers, models, API keys, and endpoints, if applicable:

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

If `deepseek-instance-1` instance rate limiting quota of 100 tokens has been consumed in a 30-second window, the additional requests will all be forwarded to `deepseek-instance-2`, which is not rate limited.

### Apply the Same Quota to All Instances

The following example demonstrates how you can apply the same rate limiting quota to all LLM upstream instances in `ai-rate-limiting`.

For demonstration and easier differentiation, you will be configuring one OpenAI instance and one DeepSeek instance as the upstream LLM services.

Create a Route which applies a rate limiting quota of 100 total tokens for all instances within a 60-second window, and update with your LLM providers, models, API keys, and endpoints, if applicable:

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

Send a POST request to the Route with a system prompt and a sample user question in the request body:

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

You should receive a response from either LLM instance, similar to the following:

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

Since the `total_tokens` value exceeds the configured quota of `100`, the next request within the 60-second window is expected to be forwarded to the other instance.

Within the same 60-second window, send another POST request to the Route:

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

You should receive a response from the other LLM instance, similar to the following:

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

Since the `total_tokens` value exceeds the configured quota of `100`, the next request within the 60-second window is expected to be rejected.

Within the same 60-second window, send a third POST request to the Route:

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

You should receive an `HTTP 429 Too Many Requests` response and observe the following headers:

```text
X-AI-RateLimit-Limit-openai-instance: 100
X-AI-RateLimit-Remaining-openai-instance: 0
X-AI-RateLimit-Reset-openai-instance: 0
X-AI-RateLimit-Limit-deepseek-instance: 100
X-AI-RateLimit-Remaining-deepseek-instance: 0
X-AI-RateLimit-Reset-deepseek-instance: 0
```

### Configure Instance Priority and Rate Limiting

The following example demonstrates how you can configure two models with different priorities and apply rate limiting on the instance with a higher priority. In the case where `fallback_strategy` is set to `["rate_limiting"]`, the Plugin should continue to forward requests to the low priority instance once the high priority instance's rate limiting quota is fully consumed.

Create a Route as such to set rate limiting and a higher priority on `openai-instance` instance and set the `fallback_strategy` to `["rate_limiting"]`. Update with your LLM providers, models, API keys, and endpoints, if applicable:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-rate-limiting-route",
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

Within the same 60-second window, send another POST request to the Route:

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

The following example demonstrates how you can configure two models for load balancing and apply rate limiting by Consumer.

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

Create a Route as such and update with your LLM providers, models, API keys, and endpoints, if applicable:

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

Send a POST request to the Route without any Consumer key:

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

This shows `ai-proxy-multi` load balance the traffic with respect to the rate limiting rules in `ai-rate-limiting` by Consumers.
