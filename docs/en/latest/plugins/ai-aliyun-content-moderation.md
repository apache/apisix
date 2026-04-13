---
title: ai-aliyun-content-moderation
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-aliyun-content-moderation
  - AI
  - Content Moderation
  - Aliyun
description: The ai-aliyun-content-moderation Plugin integrates with Aliyun Machine-Assisted Moderation Plus to check request and response content for risk level when proxying to LLMs, rejecting requests that exceed the configured threshold.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-aliyun-content-moderation" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `ai-aliyun-content-moderation` Plugin integrates with [Aliyun Machine-Assisted Moderation Plus](https://help.aliyun.com/document_detail/2671445.html) to check request and response content for risk level when proxying to LLMs, such as profanity, hate speech, insult, harassment, violence, and more, rejecting requests if the evaluated outcome exceeds the configured threshold.

Please ensure that the `access_key_secret` is correctly configured in the Plugin. If misconfigured, all requests will bypass the Plugin to be directly forwarded to the LLM Upstream, and you will see a `Specified signature is not matched with our calculation` error in the gateway's error log from the Plugin.

The `ai-aliyun-content-moderation` Plugin should be used with either [`ai-proxy`](./ai-proxy.md) or [`ai-proxy-multi`](./ai-proxy-multi.md) Plugin for proxying LLM requests.

## Attributes

| Name | Type | Required | Default | Valid Values | Description |
|------|------|----------|---------|--------------|-------------|
| access_key_id | string | True | | | Aliyun access key ID. |
| access_key_secret | string | True | | | Aliyun secret access key. The value is encrypted with AES before being stored in etcd. |
| region_id | string | True | | | Aliyun region ID. |
| endpoint | string | True | | | Aliyun endpoint. |
| check_request | boolean | False | `true` | | If `true`, moderate the request content. |
| check_response | boolean | False | `false` | | If `true`, moderate the response content. |
| stream_check_mode | string | False | `"final_packet"` | `realtime`, `final_packet` | Streaming moderation mode. `realtime`: batched checks during streaming. `final_packet`: append risk level at the end. |
| stream_check_cache_size | integer | False | `128` | >= 1 | Maximum characters per moderation batch in `realtime` mode. |
| stream_check_interval | number | False | `3` | >= 0.1 | Seconds between batch checks in `realtime` mode. |
| request_check_service | string | False | `"llm_query_moderation"` | | Aliyun service for request moderation. |
| request_check_length_limit | number | False | `2000` | | Request content length limit, in character count. If exceeded, the content will be sent in chunks. For instance, if the request content has 250 characters and the `request_check_length_limit` is set to `100`, then the content will be sent in 3 requests to Aliyun. |
| response_check_service | string | False | `"llm_response_moderation"` | | Aliyun service for response moderation. |
| response_check_length_limit | number | False | `5000` | | Response content length limit, in character count. If exceeded, the content will be sent in chunks. For instance, if the response content has 250 characters and the `response_check_length_limit` is set to `100`, then the content will be sent in 3 requests to Aliyun. |
| risk_level_bar | string | False | `"high"` | `none`, `low`, `medium`, `high`, `max` | If the evaluated risk level is lower than the `risk_level_bar`, the request or response will be passed through to Upstream LLM or client respectively. |
| deny_code | number | False | `200` | | Rejection HTTP status code. |
| deny_message | string | False | | | Rejection message. |
| timeout | integer | False | `10000` | >= 1 | Timeout in milliseconds. |
| keepalive | boolean | False | `true` | | If `true`, enable HTTP connection keepalive to Aliyun. |
| keepalive_pool | integer | False | `30` | >= 1 | Maximum number of connections in the keepalive pool. |
| keepalive_timeout | integer | False | `60000` | >= 1000 | Keepalive timeout in milliseconds. |
| ssl_verify | boolean | False | `true` | | If `true`, enable SSL certificate verification. |

## Examples

The following examples use OpenAI as the Upstream service provider. Before proceeding, create an [OpenAI account](https://openai.com) and obtain an [API key](https://openai.com/blog/openai-api). If you are working with other LLM providers, please refer to the provider's documentation to obtain an API key.

Additionally, create an [Aliyun account](https://www.aliyun.com), enable Machine-Assisted Moderation Plus, and obtain the endpoint, region ID, access key ID, and access key secret.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

You can optionally save the Aliyun and OpenAI information to environment variables:

```shell
# Replace with your data
export OPENAI_API_KEY=your-openai-api-key
export ALIYUN_ENDPOINT=https://green-cip.cn-shanghai.aliyuncs.com
export ALIYUN_REGION_ID=cn-shanghai
export ALIYUN_ACCESS_KEY_ID=your-aliyun-access-key-id
export ALIYUN_ACCESS_KEY_SECRET=your-aliyun-access-key-secret
```

### Moderate Request Content Toxicity

The following example demonstrates how you can use the Plugin to moderate content toxicity in requests and customize the rejection code and message.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route to the LLM chat completion endpoint using the [`ai-proxy`](./ai-proxy.md) Plugin and configure the integration details as well as the `deny_code` and `deny_message` in the `ai-aliyun-content-moderation` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-aliyun-content-moderation-route",
    "uri": "/anything",
    "plugins": {
      "ai-aliyun-content-moderation": {
        "endpoint": "'"$ALIYUN_ENDPOINT"'",
        "region_id": "'"$ALIYUN_REGION_ID"'",
        "access_key_id": "'"$ALIYUN_ACCESS_KEY_ID"'",
        "access_key_secret": "'"$ALIYUN_ACCESS_KEY_SECRET"'",
        "deny_code": 400,
        "deny_message": "Request contains forbidden content, such as hate speech or violence."
      },
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

Create a Route with the `ai-aliyun-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="adc.yaml"
services:
  - name: aliyun-moderation-service
    routes:
      - name: aliyun-moderation-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-aliyun-content-moderation:
            endpoint: "${ALIYUN_ENDPOINT}"
            region_id: "${ALIYUN_REGION_ID}"
            access_key_id: "${ALIYUN_ACCESS_KEY_ID}"
            access_key_secret: "${ALIYUN_ACCESS_KEY_SECRET}"
            deny_code: 400
            deny_message: "Request contains forbidden content, such as hate speech or violence."
          ai-proxy:
            provider: openai
            auth:
              header:
                Authorization: "Bearer ${OPENAI_API_KEY}"
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

Create a Route with the `ai-aliyun-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="ai-aliyun-moderation-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-aliyun-moderation-plugin-config
spec:
  plugins:
    - name: ai-aliyun-content-moderation
      config:
        endpoint: "https://green-cip.cn-shanghai.aliyuncs.com"
        region_id: "cn-shanghai"
        access_key_id: "your-aliyun-access-key-id"
        access_key_secret: "your-aliyun-access-key-secret"
        deny_code: 400
        deny_message: "Request contains forbidden content, such as hate speech or violence."
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-openai-api-key"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: aliyun-moderation-route
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
            name: ai-aliyun-moderation-plugin-config
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-aliyun-moderation-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

Create a Route with the `ai-aliyun-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="ai-aliyun-moderation-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: aliyun-moderation-route
spec:
  ingressClassName: apisix
  http:
    - name: aliyun-moderation-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-aliyun-content-moderation
          enable: true
          config:
            endpoint: "https://green-cip.cn-shanghai.aliyuncs.com"
            region_id: "cn-shanghai"
            access_key_id: "your-aliyun-access-key-id"
            access_key_secret: "your-aliyun-access-key-secret"
            deny_code: 400
            deny_message: "Request contains forbidden content, such as hate speech or violence."
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-openai-api-key"
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-aliyun-moderation-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a POST request to the Route with a system prompt and a user question with a profane word in the request body:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Stupid, what is 1+1?" }
    ]
  }'
```

You should receive an `HTTP/1.1 400 Bad Request` response and see the following message:

```json
{
  "object": "chat.completion",
  "usage": {
    "completion_tokens": 0,
    "prompt_tokens": 0,
    "total_tokens": 0
  },
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Request contains forbidden content, such as hate speech or violence."
      },
      "finish_reason": "stop",
      "index": 0
    }
  ],
  "model": "gpt-4",
  "id": "c9466bbf-e010-469d-949a-a10f25525964"
}
```

Send another request to the Route with a typical question in the request body:

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

You should receive an `HTTP/1.1 200 OK` response with the model output:

```json
{
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
  ]
}
```

### Adjust Risk Level Threshold

The following example demonstrates how you can adjust the threshold of risk level, which regulates whether a request or response should be allowed through.

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

Create a Route to the LLM chat completion endpoint using the [`ai-proxy`](./ai-proxy.md) Plugin and configure the `risk_level_bar` in `ai-aliyun-content-moderation` to be `high`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-aliyun-content-moderation-route",
    "uri": "/anything",
    "plugins": {
      "ai-aliyun-content-moderation": {
        "endpoint": "'"$ALIYUN_ENDPOINT"'",
        "region_id": "'"$ALIYUN_REGION_ID"'",
        "access_key_id": "'"$ALIYUN_ACCESS_KEY_ID"'",
        "access_key_secret": "'"$ALIYUN_ACCESS_KEY_SECRET"'",
        "deny_code": 400,
        "deny_message": "Request contains forbidden content, such as hate speech or violence.",
        "risk_level_bar": "high"
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

<TabItem value="adc">

Create a Route with the `ai-aliyun-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="adc.yaml"
services:
  - name: aliyun-moderation-service
    routes:
      - name: aliyun-moderation-route
        uris:
          - /anything
        methods:
          - POST
        plugins:
          ai-aliyun-content-moderation:
            endpoint: "${ALIYUN_ENDPOINT}"
            region_id: "${ALIYUN_REGION_ID}"
            access_key_id: "${ALIYUN_ACCESS_KEY_ID}"
            access_key_secret: "${ALIYUN_ACCESS_KEY_SECRET}"
            deny_code: 400
            deny_message: "Request contains forbidden content, such as hate speech or violence."
            risk_level_bar: high
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

Create a Route with the `ai-aliyun-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="ai-aliyun-moderation-threshold-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-aliyun-moderation-plugin-config
spec:
  plugins:
    - name: ai-aliyun-content-moderation
      config:
        endpoint: "https://green-cip.cn-shanghai.aliyuncs.com"
        region_id: "cn-shanghai"
        access_key_id: "your-aliyun-access-key-id"
        access_key_secret: "your-aliyun-access-key-secret"
        deny_code: 400
        deny_message: "Request contains forbidden content, such as hate speech or violence."
        risk_level_bar: high
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-openai-api-key"
        options:
          model: gpt-4
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: aliyun-moderation-route
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
            name: ai-aliyun-moderation-plugin-config
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-aliyun-moderation-threshold-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

Create a Route with the `ai-aliyun-content-moderation` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

```yaml title="ai-aliyun-moderation-threshold-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: aliyun-moderation-route
spec:
  ingressClassName: apisix
  http:
    - name: aliyun-moderation-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-aliyun-content-moderation
          enable: true
          config:
            endpoint: "https://green-cip.cn-shanghai.aliyuncs.com"
            region_id: "cn-shanghai"
            access_key_id: "your-aliyun-access-key-id"
            access_key_secret: "your-aliyun-access-key-secret"
            deny_code: 400
            deny_message: "Request contains forbidden content, such as hate speech or violence."
            risk_level_bar: high
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-openai-api-key"
            options:
              model: gpt-4
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-aliyun-moderation-threshold-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a POST request to the Route with a system prompt and a user question with a profane word in the request body:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Stupid, what is 1+1?" }
    ]
  }'
```

You should receive an `HTTP/1.1 400 Bad Request` response and see the following message:

```json
{
  "object": "chat.completion",
  "usage": {
    "completion_tokens": 0,
    "prompt_tokens": 0,
    "total_tokens": 0
  },
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Request contains forbidden content, such as hate speech or violence."
      },
      "finish_reason": "stop",
      "index": 0
    }
  ],
  "model": "gpt-4",
  "id": "c9466bbf-e010-469d-949a-a10f25525964"
}
```

Update the `risk_level_bar` in the Plugin to `max`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/ai-aliyun-content-moderation-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "ai-aliyun-content-moderation": {
        "risk_level_bar": "max"
      }
    }
  }'
```

Send the same request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "Stupid, what is 1+1?" }
    ]
  }'
```

You should receive an `HTTP/1.1 200 OK` response with the model output:

```json
{
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
  ]
}
```

This is because the word "stupid" has a risk level of `high`, which is lower than the configured threshold of `max`.
