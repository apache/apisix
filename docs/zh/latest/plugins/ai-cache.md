---
title: ai-cache
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - ai-cache
  - AI
  - LLM
description: ai-cache 插件将 LLM 响应缓存在 Redis 中，并在后续解析到相同提示词的请求中重放这些响应，从而降低上游的 Token 消耗与延迟。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-cache" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`ai-cache` 插件缓存 LLM 响应，并在后续解析到相同提示词的请求中重放这些响应，从而为重复性工作负载（FAQ 机器人、文档问答、翻译等）降低上游的 Token 消耗与延迟。

该插件支持两个缓存层：

- **精确缓存（L1）：** 对有效提示词计算 SHA-256 指纹并用作 Redis 键。完全相同的提示词始终命中同一条缓存条目。
- **语义缓存（L2）：** 当 L1 未命中时，将提示词向量化，并通过最近邻搜索检索相似度在阈值以上的历史响应。L2 默认关闭；在 `layers` 中加入 `"semantic"` 即可启用。

精确缓存支持 Chat Completions、Responses API、Embeddings、Anthropic Messages 和 Bedrock Converse 请求，并将不同协议存储在独立的缓存条目中。语义缓存仅适用于 Chat Completions 请求；其他协议可以使用精确缓存层，但会绕过语义缓存层。

`ai-cache` 插件必须与 [`ai-proxy`](./ai-proxy.md) 或 [`ai-proxy-multi`](./ai-proxy-multi.md) 插件一起使用。

### 流式响应

插件支持缓存并回放流式（SSE）响应。流式响应仅在**完成后**才写入缓存，即接收到客户端协议对应的终止事件（OpenAI 为 `data: [DONE]`，Anthropic 为 `message_stop`，OpenAI Responses 为 `response.completed`）。被中断的流（客户端断开连接，或触发 `ai-proxy` 的 `max_stream_duration_ms` / `max_response_bytes` 限制）不会被缓存，因此不会回放不完整的响应。命中缓存时，存储的响应会作为单个 `text/event-stream` 响应体完整回放，并保留其终止事件。

对于相同的提示词，流式请求与非流式请求会在两个缓存层中分别存储为**独立**的条目，因此流式客户端始终收到流式响应，非流式客户端始终收到单个 JSON 响应。无论流式是由客户端请求（`"stream": true`）还是由路由通过 `options.stream` 强制开启，均是如此。

限制：不含 SSE 终止事件的二进制流式格式（例如 Bedrock ConverseStream）不会被缓存；回放是即时的（一次性发送完整的存储响应），而非按 token 重新计时逐个发送。

:::note

默认情况下缓存按路由隔离，因此即使两个路由看到相同的协议、模型与消息，也不会相互返回对方的缓存条目。将 `cache_key.share_across_routes` 设为 `true` 可让多个路由共享同一个缓存空间。

即使开启 `cache_key.share_across_routes`，来自不同上游模型或 provider 的响应也会分别存储在各自的缓存条目中，因此某个模型的响应绝不会被返回给另一个模型。

:::

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| exact.ttl | integer | 否 | 3600 | >= 1 | 精确缓存条目的存活时间（TTL），单位为秒。 |
| cache_key.share_across_routes | boolean | 否 | false | | 默认情况下缓存按路由隔离。如果为 true，则计算出相同缓存键的所有路由之间共享缓存条目。 |
| cache_key.include_consumer | boolean | 否 | false | | 如果为 true，则按消费者隔离缓存，使缓存条目不会在不同消费者之间共享。 |
| cache_key.include_vars | array[string] | 否 | [] | | 加入缓存作用域的 NGINX 变量（例如 `["http_x_tenant"]`），按其取值隔离缓存条目。 |
| max_cache_body_size | integer | 否 | 1048576 | >= 0 | 允许缓存的最大响应体大小，单位为字节。超过该大小的响应不会被缓存。 |
| cache_headers | boolean | 否 | true | | 如果为 true，则输出以下响应头：`X-AI-Cache-Status`（始终输出），取值为 `MISS`、`HIT`（精确或语义缓存命中）或 `BYPASS`；`X-AI-Cache-Age`，表示缓存条目的存在时长（秒），在任意缓存命中时输出；`X-AI-Cache-Similarity`，表示请求提示词与命中条目之间的余弦相似度（0–1），仅在语义缓存命中时输出。 |
| fail_mode | string | 否 | `"skip"` | `skip`、`warn`、`error` | 当请求不是该插件可缓存的 AI 请求时的处理行为（例如未经过 `ai-proxy` 或 `ai-proxy-multi` 的请求）。`skip`：放行请求且不缓存；`warn`：放行不缓存并记录 warning 日志；`error`：拒绝请求。 |
| bypass_on | array[object] | 否 | | | 当任一规则匹配时，完全跳过缓存（不查询、不回写）的规则列表。 |
| bypass_on[].header | string | 是 | | | 要匹配的请求头名称。 |
| bypass_on[].equals | string | 是 | | | 当该请求头的值与此字符串完全相等时，绕过缓存。 |
| policy | string | 否 | redis | redis | 存储后端。本次发布仅支持单节点 `redis`。 |
| layers | array[string] | 否 | ["exact"] | exact, semantic | 要启用的缓存层。`exact` 执行精确指纹匹配（L1），始终处于激活状态，数组中必须包含 `"exact"`；`semantic` 启用向量相似度匹配（L2），仅在 L1 未命中时查询。至少需要一个值，且不可重复。 |
| redis_host | string | 是 | | | Redis 节点的地址。 |
| redis_port | integer | 否 | 6379 | >= 1 | Redis 节点的端口。 |
| redis_username | string | 否 | | | 使用 Redis ACL 时的用户名。如果使用传统的 `requirepass` 认证方式，则仅配置 `redis_password`。 |
| redis_password | string | 否 | | | Redis 节点的密码。在存入 etcd 之前使用 AES 加密。 |
| redis_database | integer | 否 | 0 | >= 0 | Redis 中使用的数据库编号。 |
| redis_timeout | integer | 否 | 1000 | >= 1 | Redis 超时时间，单位为毫秒。 |
| redis_ssl | boolean | 否 | false | | 如果为 true，则使用 SSL 连接 Redis。 |
| redis_ssl_verify | boolean | 否 | false | | 如果为 true，则校验 Redis 服务器的 SSL 证书。 |
| redis_keepalive_timeout | integer | 否 | 10000 | >= 1000 | Redis 连接池的保活超时时间，单位为毫秒。 |
| redis_keepalive_pool | integer | 否 | 100 | >= 1 | Redis 保活连接池中的最大连接数。 |

### 语义缓存（L2）属性

:::caution 语义缓存需要 Redis Stack

当 `layers` 中包含 `"semantic"` 时，所配置的 Redis 实例**必须**为 [Redis Stack](https://redis.io/docs/stack/)（含 RediSearch 模块）。L1 精确缓存与 L2 语义缓存共用同一个由 `redis_host` / `redis_port` 等参数配置的 Redis 连接。

若 `layers` 省略或仅包含 `"exact"`（默认值），则使用普通 Redis 即可。

:::

当 `layers` 中包含 `"semantic"` 时，`semantic` 对象为必填项，其属性如下：

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| semantic.similarity_threshold | number | 否 | 0.95 | [0, 1] | 将检索向量视为匹配所需的最小余弦相似度（即 1 − 距离）。低于该阈值的请求将透传至上游。 |
| semantic.top_k | integer | 否 | 1 | >= 1 | 从向量索引中检索的最近邻候选数量。只有得分最高的结果会与 `similarity_threshold` 进行比较。 |
| semantic.distance_metric | string | 否 | `"cosine"` | `cosine` | 向量距离度量方式。目前仅支持 `cosine`（余弦距离）。 |
| semantic.ttl | integer | 否 | 86400 | >= 1 | 语义缓存（L2）条目的存活时间（TTL），单位为秒。 |
| semantic.match.message_countback | integer | 否 | 1 | >= 1 | 纳入向量化输入的末尾 `user` 角色消息数量。 |
| semantic.match.ignore_system_prompts | boolean | 否 | true | | 如果为 true，则 `system` 角色消息不纳入向量化输入。 |
| semantic.match.ignore_assistant_prompts | boolean | 否 | true | | 如果为 true，则 `assistant` 角色消息不纳入向量化输入。 |
| semantic.match.ignore_tool_prompts | boolean | 否 | true | | 如果为 true，则 `tool` 角色消息不纳入向量化输入。 |
| semantic.embedding | object | **是** | | | 向量化服务配置。`openai` 与 `azure_openai` 二选一，必须且只能配置其中一个。 |
| semantic.embedding.openai.endpoint | string | 否 | | | OpenAI 兼容的向量化 API 端点 URL。省略时默认使用 OpenAI 公共 API。 |
| semantic.embedding.openai.model | string | **是** | | | 向量化模型名称（例如 `text-embedding-3-small`）。 |
| semantic.embedding.openai.api_key | string | **是** | | | OpenAI API 密钥。存入 etcd 时使用 AES 加密。 |
| semantic.embedding.openai.dimensions | integer | 否 | | >= 1 | 覆盖向量输出维度（仅对支持该参数的模型有效）。 |
| semantic.embedding.openai.ssl_verify | boolean | 否 | true | | 如果为 true，验证向量化服务的证书。 |
| semantic.embedding.openai.timeout | integer | 否 | 5000 | >= 1 | 向量化服务的请求超时时间（毫秒）。 |
| semantic.embedding.azure_openai.endpoint | string | **是** | | | Azure OpenAI 部署端点 URL。 |
| semantic.embedding.azure_openai.api_key | string | **是** | | | Azure OpenAI API 密钥。存入 etcd 时使用 AES 加密。 |
| semantic.embedding.azure_openai.dimensions | integer | 否 | | >= 1 | 覆盖向量输出维度。 |
| semantic.embedding.azure_openai.ssl_verify | boolean | 否 | true | | 如果为 true，验证向量化服务的证书。 |
| semantic.embedding.azure_openai.timeout | integer | 否 | 5000 | >= 1 | 向量化服务的请求超时时间（毫秒）。 |
| semantic.vector_search | object | **是** | | | 向量索引配置。 |
| semantic.vector_search.redis.index | string | 否 | `"ai-cache"` | | 作为向量存储使用的 RediSearch 索引名称。 |

:::note 安全说明：多租户部署

缓存条目默认按路由隔离。在多个消费者共用同一路由的多租户场景下，为某个消费者生成的缓存响应可能会被返回给其他消费者。为防止跨租户信息泄漏，请采取以下措施：

- 将 `cache_key.include_consumer` 设为 `true`，按消费者身份隔离缓存条目。
- 使用 `cache_key.include_vars` 添加标识租户的 NGINX 变量（例如 `["http_x_tenant_id"]`）到缓存作用域。

L1 与 L2 缓存条目均遵循相同的 `cache_key` 作用域规则。

:::

## 示例

以下示例使用 OpenAI 作为上游 LLM 服务提供商。请获取 [OpenAI API key](https://openai.com/blog/openai-api)，并将其与 Admin API key 一起保存到环境变量中：

```shell
export OPENAI_API_KEY=your-openai-api-key
export admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

在配置的 `redis_host` 上必须有一个可访问的 Redis 实例。

### 缓存 LLM 响应

使用 [`ai-proxy`](./ai-proxy.md) 和 `ai-cache` 插件创建一个指向 LLM 聊天补全端点的路由。

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'},
{label: 'Ingress Controller', value: 'aic'}
]}>

<TabItem value="admin-api">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-cache-route",
    "uri": "/anything",
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": { "header": { "Authorization": "Bearer '"$OPENAI_API_KEY"'" } },
        "options": { "model": "gpt-4o" }
      },
      "ai-cache": {
        "redis_host": "127.0.0.1"
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: ai-cache-service
    routes:
      - name: ai-cache-route
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
              model: gpt-4o
          ai-cache:
            redis_host: 127.0.0.1
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

```yaml title="ai-cache-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-cache-plugin-config
spec:
  plugins:
    - name: ai-cache
      config:
        redis_host: 127.0.0.1
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            Authorization: "Bearer your-openai-api-key"
        options:
          model: gpt-4o
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-cache-route
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
            name: ai-cache-plugin-config
```

将配置应用到您的集群：

```shell
kubectl apply -f ai-cache-ic.yaml
```

</TabItem>

<TabItem value="apisix-crd">

```yaml title="ai-cache-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-cache-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-cache-route
      match:
        paths:
          - /anything
        methods:
          - POST
      plugins:
        - name: ai-cache
          enable: true
          config:
            redis_host: 127.0.0.1
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                Authorization: "Bearer your-openai-api-key"
            options:
              model: gpt-4o
```

将配置应用到您的集群：

```shell
kubectl apply -f ai-cache-ic.yaml
```

</TabItem>

</Tabs>

</TabItem>

</Tabs>

向该路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{ "messages": [{ "role": "user", "content": "What is Apache APISIX? Answer in one sentence." }] }'
```

第一次请求是缓存未命中（MISS），会被代理到 LLM。响应中携带 `X-AI-Cache-Status: MISS` 响应头，响应体类似如下：

```json
{
  "id": "chatcmpl-DtmdUDZeSZ0t62y6BvLkSk5qfH3zA",
  "object": "chat.completion",
  "created": 1782187368,
  "model": "gpt-4o-2024-08-06",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Apache APISIX is a dynamic, cloud-native API gateway that provides high performance, scalability, and security for API management."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 19,
    "completion_tokens": 25,
    "total_tokens": 44
  }
}
```

再次发送相同的请求。该请求将直接由缓存返回，而不会调用 LLM，返回完全相同的响应体，并携带以下响应头：

```text
X-AI-Cache-Status: HIT
X-AI-Cache-Age: 8
```

### 绕过缓存

如需为特定请求跳过缓存，可添加 `bypass_on` 规则并更新路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/ai-cache-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "ai-cache": {
        "redis_host": "127.0.0.1",
        "bypass_on": [{ "header": "X-Cache-Bypass", "equals": "1" }]
      }
    }
  }'
```

发送带有匹配请求头的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -H "X-Cache-Bypass: 1" \
  -d '{ "messages": [{ "role": "user", "content": "What is Apache APISIX? Answer in one sentence." }] }'
```

缓存被完全跳过（不查询、不回写），响应中携带 `X-AI-Cache-Status: BYPASS` 响应头。

### 使用语义匹配缓存 LLM 响应

以下示例启用语义缓存（L2）层，使措辞略有不同但语义相近的提示词也能命中缓存。除可用的 Redis Stack 实例外，还需要 OpenAI API 密钥用于向量化服务。

:::caution

Redis 实例必须为 [Redis Stack](https://redis.io/docs/stack/)（含 RediSearch 模块）。语义缓存不支持普通 Redis。

:::

<Tabs
groupId="api"
defaultValue="admin-api"
values={[
{label: 'Admin API', value: 'admin-api'},
{label: 'ADC', value: 'adc'}
]}>

<TabItem value="admin-api">

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-cache-semantic-route",
    "uri": "/anything",
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": { "header": { "Authorization": "Bearer '"$OPENAI_API_KEY"'" } },
        "options": { "model": "gpt-4o" }
      },
      "ai-cache": {
        "redis_host": "127.0.0.1",
        "layers": ["exact", "semantic"],
        "semantic": {
          "similarity_threshold": 0.92,
          "embedding": {
            "openai": {
              "model": "text-embedding-3-small",
              "api_key": "'"$OPENAI_API_KEY"'"
            }
          },
          "vector_search": {
            "redis": {
              "index": "ai-cache"
            }
          }
        }
      }
    }
  }'
```

</TabItem>

<TabItem value="adc">

```yaml title="adc.yaml"
services:
  - name: ai-cache-semantic-service
    routes:
      - name: ai-cache-semantic-route
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
              model: gpt-4o
          ai-cache:
            redis_host: 127.0.0.1
            layers:
              - exact
              - semantic
            semantic:
              similarity_threshold: 0.92
              embedding:
                openai:
                  model: text-embedding-3-small
                  api_key: "${OPENAI_API_KEY}"
              vector_search:
                redis:
                  index: ai-cache
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>

</Tabs>

发送初始请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{ "messages": [{ "role": "user", "content": "What is Apache APISIX?" }] }'
```

首次请求同时未命中 L1 和 L2；插件将其代理到 LLM，对提示词进行向量化，并将精确缓存条目和向量分别存入 Redis。响应携带 `X-AI-Cache-Status: MISS`。

发送语义相近但措辞不同的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{ "messages": [{ "role": "user", "content": "Can you explain what Apache APISIX is?" }] }'
```

该请求未命中 L1（指纹不同），但命中了 L2（向量相似度超过阈值）。响应由语义缓存直接返回，并携带以下响应头：

```text
X-AI-Cache-Status: HIT
X-AI-Cache-Age: 12
X-AI-Cache-Similarity: 0.9487
```

`X-AI-Cache-Similarity` 响应头表示请求提示词与命中缓存条目之间的余弦相似度（1 − 距离）。
