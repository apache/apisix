---
title: ai-request-rewrite
keywords:
  - Apache APISIX
  - AI Gateway
  - Plugin
  - ai-request-rewrite
description: The ai-request-rewrite plugin forwards client requests to LLM services for processing before sending them upstream, enabling AI-driven redaction, enrichment, and reformatting.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-request-rewrite" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `ai-request-rewrite` Plugin processes client requests by forwarding them to LLM services for transformation before relaying them to Upstream services. This enables LLM-powered modifications such as data redaction, content enrichment, or reformatting. The Plugin supports integration with OpenAI, DeepSeek, Gemini, Vertex AI, Anthropic, OpenRouter, and other OpenAI-compatible APIs.

## Plugin Attributes

| **Field** | **Required** | **Type** | **Description** |
| --- | --- | --- | --- |
| `prompt` | True | string | The prompt to send to the LLM service for rewriting the client request. |
| `provider` | True | string | LLM service provider. Valid values: `openai`, `deepseek`, `azure-openai`, `aimlapi`, `gemini`, `vertex-ai`, `anthropic`, `openrouter`, `openai-compatible`. When set to `aimlapi`, the Plugin uses the OpenAI-compatible driver and proxies the request to `https://api.aimlapi.com/v1/chat/completions`. When set to `openai-compatible`, the Plugin proxies requests to the custom endpoint configured in `override`. When set to `azure-openai`, the Plugin also proxies requests to the custom endpoint configured in `override` and additionally omits the `model` parameter from the request body sent to Azure OpenAI. |
| `auth` | True | object | Authentication configurations. |
| `auth.header` | False | object | Authentication headers. Key must match pattern `^[a-zA-Z0-9._-]+$`. At least one of `header` and `query` should be configured. |
| `auth.query` | False | object | Authentication query parameters. Key must match pattern `^[a-zA-Z0-9._-]+$`. At least one of `header` and `query` should be configured. |
| `options` | False | object | Model configurations. In addition to `model`, you can configure additional parameters and they will be forwarded to the upstream LLM service in the request body. For instance, if you are working with OpenAI, you can configure additional parameters such as `temperature`, `top_p`, and `stream`. See your LLM provider's API documentation for more available options. |
| `options.model` | False | string | Name of the LLM model, such as `gpt-4` or `gpt-3.5`. See your LLM provider's API documentation for more available models. |
| `override` | False | object | Override setting. |
| `override.endpoint` | False | string | LLM provider endpoint. Required when `provider` is `openai-compatible`. |
| `timeout` | False | integer | Request timeout in milliseconds when requesting the LLM service. Range: 1 - 60000. Default: `30000`. |
| `keepalive` | False | boolean | If true, keep the connection alive when requesting the LLM service. Default: `true`. |
| `keepalive_timeout` | False | integer | Keepalive timeout in milliseconds for requests to the LLM service. Minimum: `1000`. Default: `60000`. |
| `keepalive_pool` | False | integer | Keepalive pool size for connections to the LLM service. Minimum: `1`. Default: `30`. |
| `ssl_verify` | False | boolean | If true, verify the LLM service's SSL certificate. Default: `true`. |

## Examples

The examples below demonstrate how you can configure `ai-request-rewrite` for different scenarios.

The examples use OpenAI as the LLM service. To follow along, obtain an OpenAI [API key](https://openai.com/blog/openai-api) and save it to an environment variable:

```shell
export OPENAI_API_KEY=<your-api-key>
```

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Redact Sensitive Information

The following example demonstrates how to use the `ai-request-rewrite` Plugin to redact sensitive information before the request reaches the Upstream service.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route and configure the `ai-request-rewrite` Plugin. The `provider` is set to `openai`, the OpenAI API key is passed in the `Authorization` header, and the `prompt` instructs the LLM to identify and mask sensitive information:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-request-rewrite": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver'\''s license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

Create a Route with the `ai-request-rewrite` Plugin:

```yaml title="adc.yaml"
services:
  - name: ai-request-rewrite-service
    routes:
      - name: ai-request-rewrite-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-request-rewrite:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
            prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-request-rewrite-gw.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-request-rewrite-plugin-config
spec:
  plugins:
    - name: ai-request-rewrite
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
        prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
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
            name: ai-request-rewrite-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-request-rewrite-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-request-rewrite-route
      match:
        paths:
          - /anything
        methods:
          - POST
      upstreams:
      - name: httpbin-external-domain
      plugins:
        - name: ai-request-rewrite
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
            prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
```

</TabItem>
</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-request-rewrite-ic.yaml
```

</TabItem>
</Tabs>

Send a POST request to the Route with some personally identifiable information:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "content": "John said his debit card number is 4111 1111 1111 1111 and SIN is 123-45-6789."
  }'
```

You should receive a response similar to the following:

```json
{
  "args": {},
  "data": "{\n    \"content\": \"John said his debit card number is **** **** **** 1111 and SIN is ***-**-****.\"\n  }",
  ...,
  "json": {
    "messages": [
      {
        "content": "Client information from customer service calls",
        "role": "system"
      },
      {
        "content": "John said his debit card number is **** **** **** 1111 and SIN is ***-**-****.",
        "role": "user"
      }
    ],
    "model": "openai"
  },
  "method": "POST",
  "origin": "192.168.97.1, 103.97.2.170",
  "url": "http://127.0.0.1/anything"
}
```

### Reformat Data

The following example demonstrates how to use the `ai-request-rewrite` Plugin to reformat data before the request reaches the Upstream service.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route and configure the `ai-request-rewrite` Plugin. The `prompt` instructs the LLM to convert natural language queries into structured JSON:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-request-rewrite": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "prompt": "Convert natural language queries into structured JSON format with intent and extracted parameters."
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

Create a Route with the `ai-request-rewrite` Plugin:

```yaml title="adc.yaml"
services:
  - name: ai-request-rewrite-service
    routes:
      - name: ai-request-rewrite-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-request-rewrite:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
            prompt: "Convert natural language queries into structured JSON format with intent and extracted parameters."
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-request-rewrite-gw.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-request-rewrite-plugin-config
spec:
  plugins:
    - name: ai-request-rewrite
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
        prompt: "Convert natural language queries into structured JSON format with intent and extracted parameters."
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
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
            name: ai-request-rewrite-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-request-rewrite-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-request-rewrite-route
      match:
        paths:
          - /anything
        methods:
          - POST
      upstreams:
      - name: httpbin-external-domain
      plugins:
        - name: ai-request-rewrite
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
            prompt: "Convert natural language queries into structured JSON format with intent and extracted parameters."
```

</TabItem>
</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-request-rewrite-ic.yaml
```

</TabItem>
</Tabs>

Send a POST request to the Route:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Book a flight from NYC to LA on April 10, 2022."
  }'
```

You should receive a response similar to the following:

```json
{
  "args": {},
  "data": "{\n  \"intent\": \"BookFlight\",\n  \"parameters\": {\n    \"origin\": \"NYC\",\n    \"destination\": \"LA\",\n    \"date\": \"2022-04-10\"\n  }\n}",
  ...,
  "json": {
    "intent": "BookFlight",
    "parameters": {
      "date": "2022-04-10",
      "destination": "LA",
      "origin": "NYC"
    }
  },
  "method": "POST",
  "origin": "192.168.97.1, 103.97.2.167",
  "url": "http://127.0.0.1/anything"
}
```

### Summarize Information

The following example demonstrates how to use the `ai-request-rewrite` Plugin to summarize information before the request reaches the Upstream service.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route and configure the `ai-request-rewrite` Plugin. The `prompt` instructs the LLM to summarize lengthy input while preserving key details:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-request-rewrite": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "prompt": "Summarize lengthy input while preserving key details. Ensure the summary remains concise and informative."
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

Create a Route with the `ai-request-rewrite` Plugin:

```yaml title="adc.yaml"
services:
  - name: ai-request-rewrite-service
    routes:
      - name: ai-request-rewrite-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-request-rewrite:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
            options:
              model: gpt-4
            prompt: "Summarize lengthy input while preserving key details. Ensure the summary remains concise and informative."
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-request-rewrite-gw.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-request-rewrite-plugin-config
spec:
  plugins:
    - name: ai-request-rewrite
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: gpt-4
        prompt: "Summarize lengthy input while preserving key details. Ensure the summary remains concise and informative."
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
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
            name: ai-request-rewrite-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-request-rewrite-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-request-rewrite-route
      match:
        paths:
          - /anything
        methods:
          - POST
      upstreams:
      - name: httpbin-external-domain
      plugins:
        - name: ai-request-rewrite
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: gpt-4
            prompt: "Summarize lengthy input while preserving key details. Ensure the summary remains concise and informative."
```

</TabItem>
</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-request-rewrite-ic.yaml
```

</TabItem>
</Tabs>

Send a POST request to the Route with lengthy content:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Hey! So, I'\''m planning a trip to Japan next spring for about three weeks, and I want to visit Tokyo, Kyoto, and Osaka, but I'\''m not sure how to split my time between them. I really love history and cultural sites, so temples and shrines are a must. I'\''m also a big foodie, especially into ramen and sushi, so I'\''d love recommendations on the best spots. I prefer quieter areas for accommodation, but I don'\''t mind traveling into busy areas for sightseeing. Oh, and I'\''d also like to do a day trip somewhere outside these cities—maybe Hakone or Nara? I heard the cherry blossoms might still be in bloom in early April, so I'\''d love to catch them if possible. Also, what'\''s the best way to get around—should I get a JR Pass, or would individual tickets be better? Thanks!"
  }'
```

You should receive a response similar to the following:

```json
{
  "args": {},
  "data": "The individual is planning a three-week trip to Japan in the spring, looking to visit Tokyo, Kyoto, and Osaka. They are interested in history, culture, temples, and shrines. They love ramen and sushi, so are seeking food recommendations. Accommodation should be in quieter areas, but they are open to busy sites for sightseeing. Along with these cities, they plan to make a day trip to either Hakone or Nara, hoping to see the cherry blossoms in early April. The best transport method between buying the JR Pass or individual tickets is also a query.",
  ...,
  "method": "POST",
  "origin": "192.168.97.1, 103.97.2.171",
  "url": "http://127.0.0.1/anything"
}
```

### Send Request to an OpenAI-Compatible LLM

The following example demonstrates how to use the `ai-request-rewrite` Plugin with an OpenAI-compatible LLM provider by setting `provider` to `openai-compatible` and configuring the custom endpoint in `override.endpoint`.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route and configure the `ai-request-rewrite` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/anything",
    "plugins": {
      "ai-request-rewrite": {
        "prompt": "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver'\''s license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged.",
        "provider": "openai-compatible",
        "auth": {
          "header": {
            "Authorization": "Bearer <your-api-key>"
          }
        },
        "options": {
          "model": "qwen-plus",
          "max_tokens": 1024,
          "temperature": 1
        },
        "override": {
          "endpoint": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

Create a Route with the `ai-request-rewrite` Plugin:

```yaml title="adc.yaml"
services:
  - name: ai-request-rewrite-service
    routes:
      - name: ai-request-rewrite-route
        uris:
          - /anything
        plugins:
          ai-request-rewrite:
            prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
            provider: openai-compatible
            auth:
              header:
                Authorization: "Bearer <your-api-key>"
            options:
              model: qwen-plus
              max_tokens: 1024
              temperature: 1
            override:
              endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    upstream:
      type: roundrobin
      nodes:
        - host: httpbin.org
          port: 80
          weight: 1
```

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

```yaml title="ai-request-rewrite-gw.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  type: ExternalName
  externalName: httpbin.org
---
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-request-rewrite-plugin-config
spec:
  plugins:
    - name: ai-request-rewrite
      config:
        prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
        provider: openai-compatible
        auth:
          header:
            Authorization: "Bearer your-api-key"
        options:
          model: qwen-plus
          max_tokens: 1024
          temperature: 1
        override:
          endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /anything
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-request-rewrite-plugin-config
      backendRefs:
        - name: httpbin-external-domain
          port: 80
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

```yaml title="ai-request-rewrite-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixUpstream
metadata:
  namespace: aic
  name: httpbin-external-domain
spec:
  ingressClassName: apisix
  externalNodes:
  - type: Domain
    name: httpbin.org
---
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-request-rewrite-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-request-rewrite-route
      match:
        paths:
          - /anything
      upstreams:
      - name: httpbin-external-domain
      plugins:
        - name: ai-request-rewrite
          enable: true
          config:
            prompt: "Given a JSON request body, identify and mask any sensitive information such as credit card numbers, social security numbers, and personal identification numbers (e.g., passport or driver's license numbers). Replace detected sensitive values with a masked format (e.g., \"*** **** **** 1234\") for credit card numbers. Ensure the JSON structure remains unchanged."
            provider: openai-compatible
            auth:
              header:
                Authorization: "Bearer your-api-key"
            options:
              model: qwen-plus
              max_tokens: 1024
              temperature: 1
            override:
              endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
```

</TabItem>
</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-request-rewrite-ic.yaml
```

</TabItem>
</Tabs>
