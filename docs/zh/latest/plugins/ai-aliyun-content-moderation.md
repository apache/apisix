---
title: ai-aliyun-content-moderation
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - ai-aliyun-content-moderation
  - AI
  - 内容审核
  - 阿里云
description: ai-aliyun-content-moderation 插件集成了阿里云机器辅助审核 Plus，用于在代理 LLM 请求时检查请求和响应内容的风险等级，拒绝超过配置阈值的请求。
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

## 描述

`ai-aliyun-content-moderation` 插件集成了[阿里云机器辅助审核 Plus](https://help.aliyun.com/document_detail/2671445.html)，用于在代理 LLM 请求时检查请求和响应内容的风险等级，例如亵渎、仇恨言论、侮辱、骚扰、暴力等，当评估结果超过配置的阈值时拒绝请求。

请确保在插件中正确配置 `access_key_secret`。如果配置错误，审核检查将失败，请求可能仍会被转发到 LLM 上游。你将在网关的错误日志中看到来自插件的 `Specified signature is not matched with our calculation` 错误。

`ai-aliyun-content-moderation` 插件应与 [`ai-proxy`](./ai-proxy.md) 或 [`ai-proxy-multi`](./ai-proxy-multi.md) 插件配合使用以代理 LLM 请求。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| access_key_id | string | 是 | | | 阿里云访问密钥 ID。 |
| access_key_secret | string | 是 | | | 阿里云访问密钥。该值在存储到 etcd 之前会使用 AES 加密。 |
| region_id | string | 是 | | | 阿里云区域 ID。 |
| endpoint | string | 是 | | | 阿里云端点。 |
| check_request | boolean | 否 | `true` | | 如果为 `true`，则审核请求内容。 |
| check_response | boolean | 否 | `false` | | 如果为 `true`，则审核响应内容。 |
| stream_check_mode | string | 否 | `"final_packet"` | `realtime`、`final_packet` | 流式审核模式。`realtime`：流式传输期间批量检查。`final_packet`：在最后附加风险等级。 |
| stream_check_cache_size | integer | 否 | `128` | >= 1 | `realtime` 模式下每次审核批次的最大字节数（按 UTF-8 编码后的字节长度计算）。 |
| stream_check_interval | number | 否 | `3` | >= 0.1 | `realtime` 模式下批次检查之间的间隔秒数。 |
| request_check_service | string | 否 | `"llm_query_moderation"` | | 用于请求审核的阿里云服务。 |
| request_check_length_limit | number | 否 | `2000` | | 请求内容字节数上限（按 UTF-8 编码后的字节长度计算）。如果超过该限制，内容将被分块发送。对于非 ASCII 内容，可能会比按字符数理解时更早触发分块。例如，如果请求内容按 UTF-8 编码后有 250 个字节，且 `request_check_length_limit` 设置为 `100`，则内容将分 3 次请求发送到阿里云。 |
| response_check_service | string | 否 | `"llm_response_moderation"` | | 用于响应审核的阿里云服务。 |
| response_check_length_limit | number | 否 | `5000` | | 响应内容字节数上限（按 UTF-8 编码后的字节长度计算）。如果超过该限制，内容将被分块发送。对于非 ASCII 内容，可能会比按字符数理解时更早触发分块。例如，如果响应内容按 UTF-8 编码后有 250 个字节，且 `response_check_length_limit` 设置为 `100`，则内容将分 3 次请求发送到阿里云。 |
| risk_level_bar | string | 否 | `"high"` | `none`、`low`、`medium`、`high`、`max` | 如果评估的风险等级低于 `risk_level_bar`，请求或响应将分别被放行到上游 LLM 或客户端。 |
| deny_code | number | 否 | `200` | | 拒绝时的 HTTP 状态码。 |
| deny_message | string | 否 | | | 拒绝时的消息。 |
| timeout | integer | 否 | `10000` | >= 1 | 超时时间（毫秒）。 |
| keepalive | boolean | 否 | `true` | | 如果为 `true`，启用到阿里云的 HTTP 连接保活。 |
| keepalive_pool | integer | 否 | `30` | >= 1 | 连接保活池的最大连接数。 |
| keepalive_timeout | integer | 否 | `60000` | >= 1000 | 连接保活超时时间（毫秒）。 |
| ssl_verify | boolean | 否 | `true` | | 如果为 `true`，启用 SSL 证书验证。 |

## 示例

以下示例使用 OpenAI 作为上游服务提供商。在开始之前，请创建一个 [OpenAI 账号](https://openai.com) 并获取 [API 密钥](https://openai.com/blog/openai-api)。如果你使用其他 LLM 提供商，请参考相应提供商的文档获取 API 密钥。

此外，创建一个[阿里云账号](https://www.aliyun.com)，开通机器辅助审核 Plus 服务，并获取端点、区域 ID、访问密钥 ID 和访问密钥。

:::note

你可以使用以下命令从 `config.yaml` 中获取 `admin_key` 并保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

你可以选择将阿里云和 OpenAI 信息保存到环境变量：

```shell
# 替换为你的数据
export OPENAI_API_KEY=your-openai-api-key
export ALIYUN_ENDPOINT=https://green-cip.cn-shanghai.aliyuncs.com
export ALIYUN_REGION_ID=cn-shanghai
export ALIYUN_ACCESS_KEY_ID=your-aliyun-access-key-id
export ALIYUN_ACCESS_KEY_SECRET=your-aliyun-access-key-secret
```

### 审核请求内容毒性

以下示例演示如何使用该插件审核请求中的内容毒性并自定义拒绝代码和消息。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建一个路由到 LLM 聊天补全端点，使用 [`ai-proxy`](./ai-proxy.md) 插件，并在 `ai-aliyun-content-moderation` 插件中配置集成详情以及 `deny_code` 和 `deny_message`：

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

创建一个配置了 `ai-aliyun-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

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

将配置同步到网关：

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

创建一个配置了 `ai-aliyun-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

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

将配置应用到集群：

```shell
kubectl apply -f ai-aliyun-moderation-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

创建一个配置了 `ai-aliyun-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

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

将配置应用到集群：

```shell
kubectl apply -f ai-aliyun-moderation-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向该路由发送一个 POST 请求，请求体中包含系统提示和一个含有不当用语的用户问题：

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

你应该收到 `HTTP/1.1 400 Bad Request` 响应并看到以下消息：

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

向该路由发送另一个包含正常问题的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

你应该收到 `HTTP/1.1 200 OK` 响应和模型输出：

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

### 调整风险等级阈值

以下示例演示如何调整风险等级的阈值，该阈值用于控制请求或响应是否应被放行。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

创建一个路由到 LLM 聊天补全端点，使用 [`ai-proxy`](./ai-proxy.md) 插件，并将 `ai-aliyun-content-moderation` 中的 `risk_level_bar` 配置为 `high`：

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
        "options": {
          "model": "gpt-4"
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

创建一个配置了 `ai-aliyun-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

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

将配置同步到网关：

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

创建一个配置了 `ai-aliyun-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

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

将配置应用到集群：

```shell
kubectl apply -f ai-aliyun-moderation-threshold-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

创建一个配置了 `ai-aliyun-content-moderation` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

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

将配置应用到集群：

```shell
kubectl apply -f ai-aliyun-moderation-threshold-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向该路由发送一个 POST 请求，请求体中包含系统提示和一个含有不当用语的用户问题：

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

你应该收到 `HTTP/1.1 400 Bad Request` 响应并看到以下消息：

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

将插件中的 `risk_level_bar` 更新为 `max`：

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

发送相同的请求到该路由：

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

你应该收到 `HTTP/1.1 200 OK` 响应和模型输出：

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

这是因为"stupid"一词的风险等级为 `high`，低于配置的阈值 `max`。
