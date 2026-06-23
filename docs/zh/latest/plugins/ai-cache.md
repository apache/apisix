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

本次发布实现了**精确**缓存层（L1）；语义缓存层（L2）计划在未来的版本中提供。

`ai-cache` 插件必须与 [`ai-proxy`](./ai-proxy.md) 或 [`ai-proxy-multi`](./ai-proxy-multi.md) 插件一起使用。

:::note

默认情况下缓存按路由隔离，因此即使两个路由看到相同的协议、模型与消息，也不会相互返回对方的缓存条目。将 `cache_key.share_across_routes` 设为 `true` 可让多个路由共享同一个缓存空间。

缓存键使用**请求中**的模型，而非路由在服务端改写后的模型（`ai-proxy` 的 `options.model` 或 `ai-proxy-multi` 的实例选择）。在跨路由共享时，如果不同路由改写到不同的上游模型，请使用独立的 Redis 实例，或通过 `cache_key.include_vars` 将它们隔离。

:::

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|------|------|--------|--------|--------|------|
| exact.ttl | integer | 否 | 3600 | >= 1 | 精确缓存条目的存活时间（TTL），单位为秒。 |
| cache_key.share_across_routes | boolean | 否 | false | | 默认情况下缓存按路由隔离。如果为 true，则计算出相同缓存键的所有路由之间共享缓存条目。 |
| cache_key.include_consumer | boolean | 否 | false | | 如果为 true，则按消费者隔离缓存，使缓存条目不会在不同消费者之间共享。 |
| cache_key.include_vars | array[string] | 否 | [] | | 加入缓存作用域的 NGINX 变量（例如 `["http_x_tenant"]`），按其取值隔离缓存条目。 |
| max_cache_body_size | integer | 否 | 1048576 | >= 0 | 允许缓存的最大响应体大小，单位为字节。超过该大小的响应不会被缓存。 |
| cache_headers | boolean | 否 | true | | 如果为 true，则添加 `X-AI-Cache-Status` 响应头（命中时还会添加 `X-AI-Cache-Age`，表示缓存条目的存在时长，单位为秒）。 |
| bypass_on | array[object] | 否 | | | 当任一规则匹配时，完全跳过缓存（不查询、不回写）的规则列表。 |
| bypass_on[].header | string | 是 | | | 要匹配的请求头名称。 |
| bypass_on[].equals | string | 是 | | | 当该请求头的值与此字符串完全相等时，绕过缓存。 |
| policy | string | 否 | redis | redis | 存储后端。本次发布仅支持单节点 `redis`。 |
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
