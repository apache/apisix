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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `ai-proxy` Plugin simplifies access to LLM and embedding models by transforming Plugin configurations into the designated request format. It supports the integration with OpenAI, DeepSeek, Azure, AIMLAPI, Anthropic, OpenRouter, Gemini, Vertex AI, and other OpenAI-compatible APIs.

In addition, the Plugin also supports logging LLM request information in the access log, such as token usage, model, time to the first response, and more. These log entries are also consumed by logging plugins such as `http-logger` and `kafka-logger`. These options do not affect `error.log`.

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
| override.llm_options | object | False  |         |                                          | Provider-aware LLM options. See [Provider-aware `max_tokens` mapping](#provider-aware-max_tokens-mapping). |
| override.llm_options.max_tokens | integer | False  |         | ≥ 1                                | Maximum number of output tokens. APISIX automatically maps this to the provider-specific field name (e.g. `max_completion_tokens` for OpenAI Chat Completions, `max_output_tokens` for OpenAI Responses API, `max_tokens` for most other providers). Always force-overwrites the client value. |
| override.request_body | object | False  |         |                                          | Per target-protocol request body overrides. Keys are target protocol names (`openai-chat`, `openai-responses`, `openai-embeddings`, `anthropic-messages`); values are partial request bodies that are deep-merged into the outgoing body (objects merged recursively, arrays and scalars replaced wholesale). See [Per-protocol request body override](#per-protocol-request-body-override). |
| override.request_body_force_override | boolean | False | false |                                    | When `false` (default), client request body fields take priority and `override.request_body` values only fill in missing fields. When `true`, `override.request_body` values forcefully overwrite client fields. Does not affect `override.llm_options`, which always force-overwrites. |
| logging        | object  | False    |         |                                          | Logging configurations. Does not affect `error.log`. |
| logging.summaries | boolean | False | false |                                          | If true, logs request LLM model, duration, request, and response tokens. |
| logging.payloads  | boolean | False | false |                                          | If true, logs request and response payload. |
| timeout        | integer | False    | 30000    | 1 - 600000                               | Request timeout in milliseconds when requesting the LLM service. |
| keepalive      | boolean | False    | true   |                                          | If true, keeps the connection alive when requesting the LLM service. |
| keepalive_timeout | integer | False | 60000  | ≥ 1000                                   | Keepalive timeout in milliseconds when connecting to the LLM service. |
| keepalive_pool | integer | False    | 30       | ≥ 1                                      | Keepalive pool size for the LLM service connection. |
| ssl_verify     | boolean | False    | true   |                                          | If true, verifies the LLM service's certificate. |

## Provider-aware `max_tokens` mapping

LLM providers and API endpoints disagree on the field name used to cap the number of output tokens. Configuring `override.llm_options.max_tokens` lets you set a single value in APISIX and have it forwarded under the field name expected by each provider/endpoint. `llm_options` always force-overwrites the client value.

The table below shows, for each `provider` and target API endpoint, the upstream field name APISIX rewrites `max_tokens` to. A `—` means the provider does not expose that endpoint.

| Provider            | OpenAI Chat Completions      | OpenAI Responses API   | Anthropic Messages |
| ------------------- | ---------------------------- | ---------------------- | ------------------ |
| `openai`            | `max_completion_tokens` ¹    | `max_output_tokens`    | —                  |
| `openai-compatible` | `max_tokens`                 | `max_output_tokens`    | —                  |
| `azure-openai`      | `max_tokens`                 | —                      | —                  |
| `deepseek`          | `max_tokens`                 | —                      | —                  |
| `aimlapi`           | `max_tokens`                 | —                      | —                  |
| `openrouter`        | `max_tokens`                 | —                      | —                  |
| `gemini`            | `max_completion_tokens`      | —                      | —                  |
| `vertex-ai`         | `max_completion_tokens`      | —                      | —                  |
| `anthropic`         | `max_tokens`                 | —                      | `max_tokens`       |

¹ When `provider` is `openai` and the target is the Chat Completions endpoint, APISIX always rewrites to `max_completion_tokens` and removes any `max_tokens` field from the request body — `max_tokens` has been deprecated in favor of `max_completion_tokens` by OpenAI.

## Per-protocol request body override

`override.request_body` provides fine-grained, per-protocol control over the outgoing request body. Keys are target protocol names (`openai-chat`, `openai-responses`, `openai-embeddings`, `anthropic-messages`); values are partial JSON objects that are deep-merged into the outgoing body after protocol conversion.

Merge semantics:

- Both sides are plain objects (string-keyed) → recursive merge.
- Otherwise (scalar, array, type mismatch) → patch value replaces target value wholesale.

Priority between client request and override is controlled by `override.request_body_force_override`:

- `false` (default): if the client request body already sets the field, it is preserved; the override value only fills in when the field is missing.
- `true`: the override value forcefully overwrites the client field.

When both `llm_options` and `request_body` are configured, `llm_options` is applied first (always force), then `request_body` deep-merges on top. This means `request_body` can override fields set by `llm_options`.

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

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

Create a Route with the `ai-proxy` Plugin configured as such:

```yaml title="adc.yaml"
services:
  - name: openai-service
    routes:
      - name: openai-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="ai-proxy-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: openai-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="ai-proxy-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: openai-route
spec:
  ingressClassName: apisix
  http:
    - name: openai-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: openai
          auth:
            header:
              Authorization: "Bearer your-api-key"
          options:
            model: gpt-4
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-proxy-ic.yaml
```

</TabItem>

</Tabs>

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

The following example demonstrates how you can configure the `ai-proxy` Plugin to proxy requests to DeepSeek.

Obtain the DeepSeek API key and save it to an environment variable:

```shell
export DEEPSEEK_API_KEY=<your-api-key>
```

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

Create a Route with the `ai-proxy` Plugin configured as such:

```yaml title="adc.yaml"
services:
  - name: deepseek-service
    routes:
      - name: deepseek-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: deepseek
            auth:
              header:
                Authorization: "Bearer ${DEEPSEEK_API_KEY}"
            options:
              model: deepseek-chat
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="deepseek-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: deepseek
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: deepseek-chat
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: deepseek-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="deepseek-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: deepseek-route
spec:
  ingressClassName: apisix
  http:
    - name: deepseek-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: deepseek
          auth:
            header:
              Authorization: "Bearer your-api-key"
          options:
            model: deepseek-chat
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f deepseek-ic.yaml
```

</TabItem>

</Tabs>

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

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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
        "provider": "azure-openai",
        "auth": {
          "header": {
            "api-key": "'"$AZ_OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "override": {
          "endpoint": "https://api7-azure-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

Create a Route with the `ai-proxy` Plugin configured as such:

```yaml title="adc.yaml"
services:
  - name: azure-openai-service
    routes:
      - name: azure-openai-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: azure-openai
            auth:
              header:
                api-key: "${AZ_OPENAI_API_KEY}"
            options:
              model: gpt-4
            override:
              endpoint: "https://api7-azure-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="azure-openai-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: azure-openai
        auth:
          header:
            api-key: "your-api-key"
        options:
          model: gpt-4
        override:
          endpoint: "https://api7-azure-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: azure-openai-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="azure-openai-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: azure-openai-route
spec:
  ingressClassName: apisix
  http:
    - name: azure-openai-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: azure-openai
          auth:
            header:
              api-key: "your-api-key"
          options:
            model: gpt-4
          override:
            endpoint: "https://api7-azure-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f azure-openai-ic.yaml
```

</TabItem>

</Tabs>

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

### Proxy to OpenAI Embedding Models

The following example demonstrates how you can configure the `ai-proxy` Plugin to proxy requests to embedding models. This example will use the OpenAI embedding model endpoint.

Obtain the OpenAI [API key](https://openai.com/blog/openai-api) and save it to an environment variable:

```shell
export OPENAI_API_KEY=<your-api-key>
```

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

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

</TabItem>

<TabItem value="adc">

Create a Route with the `ai-proxy` Plugin configured as such:

```yaml title="adc.yaml"
services:
  - name: openai-embeddings-service
    routes:
      - name: openai-embeddings-route
        uris:
          - /embeddings
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: text-embedding-3-small
              encoding_format: float
            override:
              endpoint: "https://api.openai.com/v1/embeddings"
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="openai-embeddings-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: text-embedding-3-small
          encoding_format: float
        override:
          endpoint: "https://api.openai.com/v1/embeddings"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: openai-embeddings-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /embeddings
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="openai-embeddings-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: openai-embeddings-route
spec:
  ingressClassName: apisix
  http:
    - name: openai-embeddings-route
      match:
        paths:
          - /embeddings
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: openai
          auth:
            header:
              Authorization: "Bearer your-api-key"
          options:
            model: text-embedding-3-small
            encoding_format: float
          override:
            endpoint: "https://api.openai.com/v1/embeddings"
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f openai-embeddings-ic.yaml
```

</TabItem>

</Tabs>

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

### Proxy to Anthropic

The following example demonstrates how you can configure the `ai-proxy` Plugin to proxy requests to Anthropic's Claude API for chat completion.

Obtain an Anthropic [API key](https://console.anthropic.com/settings/keys) and save it to an environment variable:

```shell
export ANTHROPIC_API_KEY=<your-api-key>
```

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route and configure the `ai-proxy` Plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-anthropic-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "anthropic",
        "auth": {
          "header": {
            "x-api-key": "'"$ANTHROPIC_API_KEY"'"
          }
        },
        "options": {
          "model": "claude-sonnet-4-20250514"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

Create a Route with the `ai-proxy` Plugin configured as such:

```yaml title="adc.yaml"
services:
  - name: anthropic-service
    routes:
      - name: anthropic-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: anthropic
            auth:
              header:
                x-api-key: "${ANTHROPIC_API_KEY}"
            options:
              model: claude-sonnet-4-20250514
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="anthropic-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: anthropic
        auth:
          header:
            x-api-key: "your-api-key"
        options:
          model: claude-sonnet-4-20250514
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: anthropic-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="anthropic-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: anthropic-route
spec:
  ingressClassName: apisix
  http:
    - name: anthropic-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: anthropic
          auth:
            header:
              x-api-key: "your-api-key"
          options:
            model: claude-sonnet-4-20250514
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f anthropic-ic.yaml
```

</TabItem>

</Tabs>

The configuration above specifies `anthropic` as the provider and attaches the Anthropic API key in the `x-api-key` header.

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
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "1+1 equals 2."
    }
  ],
  "model": "claude-sonnet-4-20250514",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 19,
    "output_tokens": 11
  }
}
```

### Convert Anthropic Requests to OpenAI-Compatible Backend

The following example demonstrates how the `ai-proxy` Plugin can accept requests in the Anthropic Messages API format and automatically convert them to the OpenAI-compatible format before forwarding to any OpenAI-compatible backend (such as OpenAI, DeepSeek, or other compatible services). This is useful when client applications send Anthropic-formatted requests but you want to use a different LLM backend.

The protocol conversion is triggered automatically when the Route URI is set to `/v1/messages` (the Anthropic Messages API endpoint). The Plugin will convert Anthropic-formatted requests to OpenAI-compatible format and transform the responses back to Anthropic format.

Obtain an API key for your chosen OpenAI-compatible backend service and save it to an environment variable. This example uses OpenAI:

```shell
export BACKEND_API_KEY=<your-api-key>
```

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route with the URI set to `/v1/messages` to trigger automatic Anthropic protocol conversion, and configure the `ai-proxy` Plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-anthropic-convert-route",
    "uri": "/v1/messages",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$BACKEND_API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

Create a Route with the URI set to `/v1/messages` to trigger automatic Anthropic protocol conversion, and configure the `ai-proxy` Plugin as such:

```yaml title="adc.yaml"
services:
  - name: anthropic-convert-service
    routes:
      - name: anthropic-convert-route
        uris:
          - /v1/messages
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${BACKEND_API_KEY}"
            options:
              model: gpt-4
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="anthropic-convert-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: anthropic-convert-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /v1/messages
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-proxy-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="anthropic-convert-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: anthropic-convert-route
spec:
  ingressClassName: apisix
  http:
    - name: anthropic-convert-route
      match:
        paths:
          - /v1/messages
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: openai
          auth:
            header:
              Authorization: "Bearer your-api-key"
          options:
            model: gpt-4
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f anthropic-convert-ic.yaml
```

</TabItem>

</Tabs>

The backend provider can be any OpenAI-compatible provider, such as `openai`, `deepseek`, or others.

Send a POST request to the Route in Anthropic Messages API format:

```shell
curl "http://127.0.0.1:9080/v1/messages" -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${BACKEND_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "gpt-4",
    "max_tokens": 1024,
    "messages": [
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

Although the request is sent in Anthropic format, it will be automatically converted to OpenAI format and forwarded to the backend. The response is converted back to Anthropic format:

```json
{
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "1+1 equals 2."
    }
  ],
  "model": "gpt-4",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 12,
    "output_tokens": 8
  }
}
```

The Plugin supports all features of the Anthropic Messages API, including streaming (SSE), system prompts, and tool use (function calling). The protocol conversion handles the bidirectional mapping between Anthropic and OpenAI formats transparently.

### Proxy to Selected Model using Request Body Parameter

The following example demonstrates how you can proxy requests to different models on the same URI, based on the user-specified model in the user requests. You will be using the `post_arg.*` variable to fetch the value of the request body parameter.

The example will use OpenAI and DeepSeek as the example LLM services. Obtain the OpenAI and DeepSeek API keys and save them to environment variables:

```shell
export OPENAI_API_KEY=<your-api-key>
export DEEPSEEK_API_KEY=<your-api-key>
```

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route to the OpenAI API with the `ai-proxy` Plugin. The Route URI is `/anything` and it matches requests where the body parameter `model` is set to `openai`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-openai-route",
    "uri": "/anything",
    "methods": ["POST"],
    "vars": [[ "post_arg.model", "==", "openai" ]],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options": {
          "model": "gpt-4"
        }
      }
    }
  }'
```

Create another Route `/anything` to the DeepSeek API with the `ai-proxy` Plugin. This Route matches requests where the body parameter `model` is set to `deepseek`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-deepseek-route",
    "uri": "/anything",
    "methods": ["POST"],
    "vars": [[ "post_arg.model", "==", "deepseek" ]],
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

</TabItem>

<TabItem value="adc">

Create two Routes with the `ai-proxy` Plugin configured for different providers:

```yaml title="adc.yaml"
services:
  - name: multi-model-service
    routes:
      - name: openai-route
        uris:
          - /anything
        methods:
          - POST
        vars:
          - - post_arg.model
            - ==
            - openai
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
      - name: deepseek-route
        uris:
          - /anything
        methods:
          - POST
        vars:
          - - post_arg.model
            - ==
            - deepseek
        plugins:
          ai-proxy:
            provider: deepseek
            auth:
              header:
                Authorization: "Bearer ${DEEPSEEK_API_KEY}"
            options:
              model: deepseek-chat
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

Body parameter matching is not supported in HTTPRoute. The supported matching mechanisms are `path`, `method`, `headers`, and `queryParams`. This example cannot be completed with Gateway API.

</TabItem>

<TabItem value="apisix-crd">

Body parameter matching is currently not supported in ApisixRoute. The supported matching mechanisms are based on `Header`, `Query`, or `Path`. This example cannot be completed with APISIX CRDs.

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a POST request to the Route with `model` set to `openai`:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai",
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

Send a POST request to the Route with `model` set to `deepseek`:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek",
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
  ...
}
```

You can also configure `post_arg.*` to fetch nested request body parameter. For instance, if the request format is:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": {
      "name": "openai"
    },
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

You can configure the `vars` on the Route to be `[[ "post_arg.model.name", "==", "openai" ]]`.

### Send Request Log to Logger

The following example demonstrates how you can log request and response information, including LLM model, token, and payload, and push them to a logger. Before proceeding, you should first set up a logger, such as Kafka. See [`kafka-logger`](./kafka-logger.md) for more information.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route to your LLM service and configure logging details. Enable `summaries` to log request LLM model, duration, request and response tokens. Enable `payloads` to log request and response payload. Update the `kafka-logger` configuration with your Kafka address, topic, and key:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-openai-route",
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
          "model": "gpt-4"
        },
        "logging": {
          "summaries": true,
          "payloads": true
        }
      },
      "kafka-logger": {
        "brokers": [
          {
            "host": "127.0.0.1",
            "port": 9092
          }
        ],
        "kafka_topic": "test2",
        "key": "key1",
        "batch_max_size": 1
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

Create a Route with both `ai-proxy` and `kafka-logger` Plugins. Enable `summaries` to log request LLM model, duration, request and response tokens. Enable `payloads` to log request and response payload. Update the `kafka-logger` configuration with your Kafka address, topic, and key:

```yaml title="adc.yaml"
services:
  - name: logging-service
    routes:
      - name: logging-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
            logging:
              summaries: true
              payloads: true
          kafka-logger:
            brokers:
              - host: 127.0.0.1
                port: 9092
            kafka_topic: test2
            key: key1
            batch_max_size: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>

<TabItem value="aic">

<Tabs
groupId="k8s-api"
defaultValue="gateway-api"
values={[
{label: 'Gateway API', value: 'gateway-api'},
{label: 'APISIX CRD', value: 'apisix-crd'}
]}>

<TabItem value="gateway-api">

```yaml title="logging-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-proxy-logging-plugin-config
spec:
  plugins:
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
        logging:
          summaries: true
          payloads: true
    - name: kafka-logger
      config:
        brokers:
          - host: kafka.aic.svc.cluster.local
            port: 9092
        kafka_topic: test2
        key: key1
        batch_max_size: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: logging-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-proxy-logging-plugin-config
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="logging-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: logging-route
spec:
  ingressClassName: apisix
  http:
    - name: logging-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
      - name: ai-proxy
        enable: true
        config:
          provider: openai
          auth:
            header:
              Authorization: "Bearer your-api-key"
          options:
            model: gpt-4
          logging:
            summaries: true
            payloads: true
      - name: kafka-logger
        enable: true
        config:
          brokers:
            - host: kafka.aic.svc.cluster.local
              port: 9092
          kafka_topic: test2
          key: key1
          batch_max_size: 1
```

</TabItem>

</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f logging-ic.yaml
```

</TabItem>

</Tabs>

Send a POST request to the Route:

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
  ...
}
```

In the Kafka topic, you should also see a log entry corresponding to the request with the LLM summary and request/response payload.

### Include LLM Information in Access Log

The following example demonstrates how you can log LLM request related information in the gateway's access log to improve analytics and audit. The following variables are available:

* `request_llm_model`: LLM model name specified in the request.
* `apisix_upstream_response_time`: Time taken for APISIX to send the request to the upstream service and receive the full response.
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
