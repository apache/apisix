---
title: langfuse
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Langfuse
  - LLM Observability
description: This document contains information about the Apache APISIX langfuse Plugin.
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

The `langfuse` Plugin enables LLM observability by sending traces of AI API requests to [Langfuse](https://langfuse.com/). It captures request/response data, token usage, model information, and latency for each LLM call, making it easy to monitor and debug AI-powered applications.

## Plugin Metadata

The global configuration shared across all routes is managed through plugin metadata. You can set it using the Admin API endpoint `apisix/admin/plugin_metadata/langfuse`.

| Name | Type | Required | Default | Description |
| ---- | ---- | -------- | ------- | ----------- |
| langfuse_host | string | False | `https://cloud.langfuse.com` | Langfuse server host URL. |
| langfuse_public_key | string | True | | Langfuse project public key. |
| langfuse_secret_key | string | True | | Langfuse project secret key. |
| ssl_verify | boolean | False | true | Whether to verify the Langfuse server's SSL certificate. |
| timeout | integer | False | 3 | Timeout in seconds for requests sent to Langfuse. |
| detect_ai_requests | boolean | False | true | When set to `true`, only traces requests whose path matches one of the patterns in `ai_endpoints`. |
| ai_endpoints | array[string] | False | `["/chat/completions", "/completions", "/generate", "/responses", "/embeddings", "/messages"]` | List of path patterns used to detect AI API requests when `detect_ai_requests` is `true`. |

## Attributes

| Name | Type | Required | Default | Description |
| ---- | ---- | -------- | ------- | ----------- |
| include_metadata | boolean | False | true | When set to `true`, includes request metadata (headers, route info) in the Langfuse trace. |

## Enable Plugin

First, configure the plugin metadata with your Langfuse credentials:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/langfuse \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "langfuse_public_key": "pk-lf-...",
    "langfuse_secret_key": "sk-lf-...",
    "langfuse_host": "https://cloud.langfuse.com",
    "detect_ai_requests": true
}'
```

Then, enable the plugin on a Route:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/v1/chat/completions",
    "plugins": {
        "langfuse": {
            "include_metadata": true
        },
        "ai-proxy": {
            "auth": {
                "header": {
                    "Authorization": "Bearer sk-..."
                }
            },
            "model": {
                "provider": "openai",
                "name": "gpt-4o"
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "api.openai.com:443": 1
        }
    }
}'
```

## Example usage

After enabling the plugin and making an LLM request, you can view the traces in the Langfuse dashboard. Each request generates a trace with the following information:

- **Input/Output**: The prompt messages and the model's response
- **Token usage**: Prompt tokens, completion tokens, and total tokens
- **Model**: The LLM model name used
- **Latency**: Total request duration
- **Metadata**: Route ID, service ID, request headers (when `include_metadata` is `true`)

## Disable Plugin

To remove the `langfuse` Plugin from a Route, delete the plugin configuration from the route:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/v1/chat/completions",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "api.openai.com:443": 1
        }
    }
}'
```
