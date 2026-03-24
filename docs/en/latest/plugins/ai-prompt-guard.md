---
title: ai-prompt-guard
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-prompt-guard
description: The ai-prompt-guard Plugin safeguards your AI endpoints by inspecting and validating incoming prompt messages.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-prompt-guard" />
</head>

## Description

The `ai-prompt-guard` Plugin safeguards your AI endpoints by inspecting and validating incoming prompt messages. It checks the content of requests against user-defined allowed and denied patterns to ensure that only approved inputs are processed. Based on its configuration, the Plugin can either examine just the latest message or the entire conversation history, and it can be set to check prompts from all roles or only from end users.

When both **allow** and **deny** patterns are configured, the Plugin first ensures that at least one allowed pattern is matched. If none match, the request is rejected with a _"Request doesn't match allow patterns"_ error. If an allowed pattern is found, it then checks for any occurrences of denied patterns—rejecting the request with a _"Request contains prohibited content"_ error if any are detected.

## Plugin Attributes

| **Field**                      | **Required** | **Type**  | **Description**                                                                                                                                                      |
| ------------------------------ | ------------ | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| match_all_roles                | No           | boolean   | If true, validate messages from all roles. If false, validate the message from `user` role only. Default is `false`. |
| match_all_conversation_history | No           | boolean   | If true, concatenate and check all messages in the conversation history. If false, only check the content of the last message. Default is `false`. |
| allow_patterns                 | No           | array     | An array of RegEx patterns that messages should match. When configured, messages must match at least one pattern to be considered valid.              |
| deny_patterns                  | No           | array     | An array of RegEx patterns that messages should not match. If messages match any of the patterns, the request should be rejected. If both `allow_patterns` and `deny_patterns` are configured, the Plugin first ensures that at least one `allow_patterns` is matched.              |

## Examples

The following examples will be using OpenAI as the upstream service provider. Before proceeding, create an [OpenAI account](https://openai.com) and an [API key](https://openai.com/blog/openai-api). You can optionally save the key to an environment variable as such:

```shell
export OPENAI_API_KEY=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   # replace with your API key
```

If you are working with other LLM providers, please refer to the provider's documentation to obtain an API key.

### Implement Allow and Deny Patterns

The following example demonstrates how to use the `ai-prompt-guard` Plugin to validate user prompts by defining both allow and deny patterns and understand how the allow pattern takes precedence.

Define the allow and deny patterns. You can optionally save them to environment variables for easier escape:

```shell
# allow US dollar amount
export ALLOW_PATTERN_1='\\$?\\(?\\d{1,3}(,\\d{3})*(\\.\\d{1,2})?\\)?'
# deny phone number in US number format
export DENY_PATTERN_1='(\\([0-9]{3}\\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
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

Create a Route that uses `ai-proxy` to proxy to OpenAI and `ai-prompt-guard` to inspect input prompts:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-prompt-guard-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      # highlight-start
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
      },
      "ai-prompt-guard": {
        "allow_patterns": [
          "'"$ALLOW_PATTERN_1"'"
        ],
        "deny_patterns": [
          "'"$DENY_PATTERN_1"'"
        ]
      }
      # highlight-end
    }
  }'
```

</TabItem>

<TabItem value="adc">

Create a Route with the `ai-prompt-guard` and [`ai-proxy`](/hub/ai-proxy) Plugins configured as such:

```yaml title="adc.yaml"
services:
  - name: prompt-guard-service
    routes:
      - name: prompt-guard-route
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
          ai-prompt-guard:
            allow_patterns:
              - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
            deny_patterns:
              - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
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

Create a Route with the `ai-prompt-guard` and [`ai-proxy`](/hub/ai-proxy) Plugins configured as such:

```yaml title="ai-prompt-guard-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-prompt-guard-plugin-config
spec:
  plugins:
    - name: ai-prompt-guard
      config:
        allow_patterns:
          - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
        deny_patterns:
          - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer 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"
        options:
          model: gpt-4
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: prompt-guard-route
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
            name: ai-prompt-guard-plugin-config
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-prompt-guard-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

Create a Route with the `ai-prompt-guard` and [`ai-proxy`](/hub/ai-proxy) Plugins configured as such:

```yaml title="ai-prompt-guard-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: prompt-guard-route
spec:
  ingressClassName: apisix
  http:
    - name: prompt-guard-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-prompt-guard
          enable: true
          config:
            allow_patterns:
              - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
            deny_patterns:
              - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer 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"
            options:
              model: gpt-4
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-prompt-guard-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request to the Route to rate the fairness of a purchase:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

You should see receive an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  ...
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        # highlight-next-line
        "content": "The purchase is not at a decent price. Typically, a hot brewed coffee costs anywhere from $1 to $3 in most places in the US, so $12.5 is quite expensive.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

Send another request to the Route without any price in the message:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "John paid a bit for a hot brewed coffee in El Paso." }
    ]
  }'
```

You should receive an `HTTP/1.1 400 Bad Request` response and see the following message:

```text
{"message":"Request doesn't match allow patterns"}
```

Send a third request to the Route with a phone number in the message:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "John (647-200-9393) paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

You should receive an `HTTP/1.1 400 Bad Request` response and see the following message:

```text
{"message":"Request contains prohibited content"}
```

By default, the Plugin inspects only the last message from the `user` role. For instance, if you send a request including the prohibited content in the `system` prompt:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase from 647-200-9393 is at a decent price in USD." },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

You will receive an `HTTP/1.1 200 OK` response.

If you send a request including the prohibited content in the second last message:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "Customer John contact: 647-200-9393" },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

You will also receive an `HTTP/1.1 200 OK` response.

See the [next example](#validate-messages-from-all-roles-and-conversation-history) to see how to inspect messages from all roles and all messages.

### Validate Messages From All Roles and Conversation History

The following example demonstrates how to use the `ai-prompt-guard` Plugin to validate prompts from all roles, such as `system` and `user`, and validate the entire conversation history instead of the last message.

Define the allow and deny patterns. You can optionally save them to environment variables for easier escape:

```shell
export ALLOW_PATTERN_1='\\$?\\(?\\d{1,3}(,\\d{3})*(\\.\\d{1,2})?\\)?'
export DENY_PATTERN_1='(\\([0-9]{3}\\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
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

Create a Route that uses `ai-proxy` to proxy to OpenAI and `ai-prompt-guard` to inspect input prompts:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-prompt-guard-route",
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
      },
      "ai-prompt-guard": {
        "match_all_roles": true,
        "match_all_conversation_history": true,
        "allow_patterns": [
          "'"$ALLOW_PATTERN_1"'"
        ],
        "deny_patterns": [
          "'"$DENY_PATTERN_1"'"
        ]
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

Create a Route with the `ai-prompt-guard` and [`ai-proxy`](/hub/ai-proxy) Plugins configured as such:

```yaml title="adc.yaml"
services:
  - name: prompt-guard-service
    routes:
      - name: prompt-guard-route
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
          ai-prompt-guard:
            match_all_roles: true
            match_all_conversation_history: true
            allow_patterns:
              - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
            deny_patterns:
              - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
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

Create a Route with the `ai-prompt-guard` and [`ai-proxy`](/hub/ai-proxy) Plugins configured as such:

```yaml title="ai-prompt-guard-history-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-prompt-guard-plugin-config
spec:
  plugins:
    - name: ai-prompt-guard
      config:
        match_all_roles: true
        match_all_conversation_history: true
        allow_patterns:
          - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
        deny_patterns:
          - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer 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"
        options:
          model: gpt-4
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: prompt-guard-route
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
            name: ai-prompt-guard-plugin-config
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-prompt-guard-history-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

Create a Route with the `ai-prompt-guard` and [`ai-proxy`](/hub/ai-proxy) Plugins configured as such:

```yaml title="ai-prompt-guard-history-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: prompt-guard-route
spec:
  ingressClassName: apisix
  http:
    - name: prompt-guard-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-prompt-guard
          enable: true
          config:
            match_all_roles: true
            match_all_conversation_history: true
            allow_patterns:
              - '\$?\(?\d{1,3}(,\d{3})*(\.\d{1,2})?\)?'
            deny_patterns:
              - '(\([0-9]{3}\)|[0-9]{3}-)[0-9]{3}-[0-9]{4}'
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer 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"
            options:
              model: gpt-4
```

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-prompt-guard-history-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

Send a request including with prohibited content in the `system` prompt:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase from 647-200-9393 is at a decent price in USD." },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

You should receive an `HTTP/1.1 400 Bad Request` response and see the following message:

```text
{"message":"Request contains prohibited content"}
```

Send a request with multiple messages from the same role with prohibited content:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "user", "content": "Customer John contact: 647-200-9393" },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee in El Paso." }
    ]
  }'
```

You should receive an `HTTP/1.1 400 Bad Request` response and see the following message:

```text
{"message":"Request contains prohibited content"}
```

Send a request that conforms to the patterns:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "Rate if the purchase is at a decent price in USD." },
      { "role": "system", "content": "The purchase is made in El Paso." },
      { "role": "user", "content": "Customer John contact: xxx-xxx-xxxx" },
      { "role": "user", "content": "John paid $12.5 for a hot brewed coffee." }
    ]
  }'
```

You should receive an `HTTP/1.1 200 OK` response similar to the following:

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "$12.5 is generally considered quite expensive for a cup of brew coffee.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```
