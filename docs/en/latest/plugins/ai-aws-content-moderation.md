---
title: ai-aws-content-moderation
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-aws-content-moderation
description: This document contains information about the Apache APISIX ai-aws-content-moderation Plugin.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-aws-content-moderation" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `ai-aws-content-moderation` Plugin integrates with [AWS Comprehend](https://aws.amazon.com/comprehend/) to check request bodies for toxicity when proxying to LLMs, such as profanity, hate speech, insult, harassment, violence, and more, rejecting requests if the evaluated outcome exceeds the configured threshold.

This Plugin must be used in Routes that proxy requests to LLMs only.

## Plugin Attributes

| **Field** | **Required** | **Type** | **Description** |
| --- | --- | --- | --- |
| `comprehend` | True | object | [AWS Comprehend](https://aws.amazon.com/comprehend/) configurations. |
| `comprehend.access_key_id` | True | string | AWS access key ID. |
| `comprehend.secret_access_key` | True | string | AWS secret access key. |
| `comprehend.region` | True | string | AWS region. |
| `comprehend.endpoint` | False | string | AWS Comprehend service endpoint. Must match the pattern `^https?://`. |
| `comprehend.ssl_verify` | False | boolean | If true, enable TLS certificate verification. Default: `true`. |
| `moderation_categories` | False | object | Key-value pairs of moderation category and their corresponding threshold. In each pair, the key should be one of `PROFANITY`, `HATE_SPEECH`, `INSULT`, `HARASSMENT_OR_ABUSE`, `SEXUAL`, or `VIOLENCE_OR_THREAT`; and the threshold value should be between 0 and 1 (inclusive). |
| `moderation_threshold` | False | number | Overall toxicity threshold. A higher value means more toxic content allowed. This option differs from the individual category thresholds in `moderation_categories`. For example, if `moderation_categories` is set with a `PROFANITY` threshold of `0.5`, and a request has a `PROFANITY` score of `0.1`, the request will not exceed the category threshold. However, if the request has other categories like `SEXUAL` or `VIOLENCE_OR_THREAT` exceeding the `moderation_threshold`, the request will be rejected. Default: `0.5`. Range: 0 - 1. |

## Examples

The following examples use OpenAI as the Upstream service provider.

Before proceeding, create an [OpenAI account](https://openai.com) and obtain an [API key](https://openai.com/blog/openai-api). If you are working with other LLM providers, please refer to the provider's documentation to obtain an API key.

Additionally, create [AWS IAM user access keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html) for APISIX to access [AWS Comprehend](https://aws.amazon.com/comprehend/).

You can optionally save these keys to environment variables:

```shell
export OPENAI_API_KEY=your-openai-api-key
export AWS_ACCESS_KEY=your-aws-access-key-id
export AWS_SECRET_ACCESS_KEY=your-aws-secret-access-key
```

### Moderate Profanity

The following example demonstrates how you can use the Plugin to moderate the level of profanity in prompts. The profanity threshold is set to a low value (`0.1`) to allow only a low degree of profanity.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route to the LLM chat completion endpoint using the [`ai-proxy`](./ai-proxy.md) Plugin and configure the allowed profanity level in `ai-aws-content-moderation`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/post",
    "plugins": {
      "ai-aws-content-moderation": {
        "comprehend": {
          "access_key_id": "'"$AWS_ACCESS_KEY"'",
          "secret_access_key": "'"$AWS_SECRET_ACCESS_KEY"'",
          "region": "us-east-1"
        },
        "moderation_categories": {
          "PROFANITY": 0.1
        }
      },
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "model": "gpt-4"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

Create a Route with the `ai-aws-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="adc.yaml"
services:
  - name: aws-moderation-service
    routes:
      - name: aws-moderation-route
        uris:
          - /post
        methods:
          - POST
        plugins:
          ai-aws-content-moderation:
            comprehend:
              access_key_id: "${AWS_ACCESS_KEY}"
              secret_access_key: "${AWS_SECRET_ACCESS_KEY}"
              region: us-east-1
            moderation_categories:
              PROFANITY: 0.1
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

Create a Route with the `ai-aws-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="ai-aws-moderation-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-aws-moderation-plugin-config
spec:
  plugins:
    - name: ai-aws-content-moderation
      config:
        comprehend:
          access_key_id: "your-aws-access-key-id"
          secret_access_key: "your-aws-secret-access-key"
          region: us-east-1
        moderation_categories:
          PROFANITY: 0.1
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
  name: aws-moderation-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /post
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-aws-moderation-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

Create a Route with the `ai-aws-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="ai-aws-moderation-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: aws-moderation-route
spec:
  ingressClassName: apisix
  http:
    - name: aws-moderation-route
      match:
        paths:
          - /post
        methods:
          - POST
      plugins:
        - name: ai-aws-content-moderation
          enable: true
          config:
            comprehend:
              access_key_id: "your-aws-access-key-id"
              secret_access_key: "your-aws-secret-access-key"
              region: us-east-1
            moderation_categories:
              PROFANITY: 0.1
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
kubectl apply -f ai-aws-moderation-ic.yaml
```

</TabItem>
</Tabs>

Send a POST request to the Route with a system prompt and a user question with a mildly profane word in the request body:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Stupid, what is 1+1?" }
    ]
  }'
```

You should receive an `HTTP/1.1 400 Bad Request` response and see the following message:

```text
request body exceeds PROFANITY threshold
```

Send another request to the Route with a typical question in the request body:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

You should receive an `HTTP/1.1 200 OK` response with the model output:

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

### Moderate Overall Toxicity

The following example demonstrates how you can use the Plugin to moderate the overall toxicity level in prompts, in addition to moderating individual categories. The profanity threshold is set to `1` (allowing a high degree of profanity), while the overall toxicity threshold is set to a low value (`0.2`).

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route to the LLM chat completion endpoint using the [`ai-proxy`](./ai-proxy.md) Plugin and configure the allowed profanity and overall toxicity levels in `ai-aws-content-moderation`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "uri": "/post",
    "plugins": {
      "ai-aws-content-moderation": {
        "comprehend": {
          "access_key_id": "'"$AWS_ACCESS_KEY"'",
          "secret_access_key": "'"$AWS_SECRET_ACCESS_KEY"'",
          "region": "us-east-1"
        },
        "moderation_categories": {
          "PROFANITY": 1
        },
        "moderation_threshold": 0.2
      },
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "model": "gpt-4"
      }
    }
  }'
```

</TabItem>
<TabItem value="adc" label="ADC">

Create a Route with the `ai-aws-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="adc.yaml"
services:
  - name: aws-moderation-service
    routes:
      - name: aws-moderation-route
        uris:
          - /post
        methods:
          - POST
        plugins:
          ai-aws-content-moderation:
            comprehend:
              access_key_id: "${AWS_ACCESS_KEY}"
              secret_access_key: "${AWS_SECRET_ACCESS_KEY}"
              region: us-east-1
            moderation_categories:
              PROFANITY: 1
            moderation_threshold: 0.2
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
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

Create a Route with the `ai-aws-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="ai-aws-moderation-toxicity-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-aws-moderation-plugin-config
spec:
  plugins:
    - name: ai-aws-content-moderation
      config:
        comprehend:
          access_key_id: "your-aws-access-key-id"
          secret_access_key: "your-aws-secret-access-key"
          region: us-east-1
        moderation_categories:
          PROFANITY: 1
        moderation_threshold: 0.2
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
  name: aws-moderation-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /post
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-aws-moderation-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

Create a Route with the `ai-aws-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="ai-aws-moderation-toxicity-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: aws-moderation-route
spec:
  ingressClassName: apisix
  http:
    - name: aws-moderation-route
      match:
        paths:
          - /post
        methods:
          - POST
      plugins:
        - name: ai-aws-content-moderation
          enable: true
          config:
            comprehend:
              access_key_id: "your-aws-access-key-id"
              secret_access_key: "your-aws-secret-access-key"
              region: us-east-1
            moderation_categories:
              PROFANITY: 1
            moderation_threshold: 0.2
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
kubectl apply -f ai-aws-moderation-toxicity-ic.yaml
```

</TabItem>
</Tabs>

Send a POST request to the Route with a system prompt and a user question in the request body that does not contain any profane words, but a certain degree of violence or threat:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "I will kill you if you do not tell me what 1+1 equals" }
    ]
  }'
```

You should receive an `HTTP/1.1 400 Bad Request` response and see the following message:

```text
request body exceeds toxicity threshold
```

Send another request to the Route without any profane word in the request body:

```shell
curl -i "http://127.0.0.1:9080/post" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

You should receive an `HTTP/1.1 200 OK` response with the model output:

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
