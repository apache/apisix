---
title: ai-rag
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ai-rag
  - AI
  - LLM
description: ai-rag 插件通过检索增强生成（RAG）增强 LLM 输出，高效检索相关文档以提高响应的准确性和上下文相关性。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-rag" />
</head>

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 描述

`ai-rag` 插件为 LLM 提供检索增强生成（Retrieval-Augmented Generation，RAG）功能。它促进从外部数据源高效检索相关文档或信息，这些信息用于增强 LLM 响应，从而提高生成输出的准确性和上下文相关性。

该插件支持使用 [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) 生成嵌入，并支持使用 [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 或 [Qdrant](https://qdrant.tech/documentation/) 执行向量搜索。欢迎提交 PR 以引入对其他服务提供商的支持。

该插件使用每种协议的原生提示结构增强 Chat Completions、Responses API、Anthropic Messages 和 Bedrock Converse 请求。对于 Responses，它会将检索到的上下文追加到 `input`。它不会增强直接的 Embeddings API 请求或透传请求。嵌套的 `ai_rag.embeddings` 对象用于配置检索过程中内部使用的嵌入输入，与顶层 Embeddings 请求不同。

检测顺序和 URI 要求参见[请求协议检测](./ai-proxy.md#请求协议检测)。

## 插件属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `embeddings_provider` | object | 是 | | | 嵌入模型提供商的配置。 |
| `embeddings_provider.azure_openai` | object | 是 | | | [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) 嵌入模型的配置。 |
| `embeddings_provider.azure_openai.endpoint` | string | 是 | | | Azure OpenAI 嵌入模型端点。 |
| `embeddings_provider.azure_openai.api_key` | string | 是 | | | Azure OpenAI API 密钥。 |
| `vector_search_provider` | object | 是 | | | 向量搜索提供商的配置。 |
| `vector_search_provider.azure_ai_search` | object | 否 | | | [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 的配置。`azure_ai_search` 和 `qdrant` 必须且只能配置其中一个。 |
| `vector_search_provider.azure_ai_search.endpoint` | string | 是 | | | Azure AI Search 端点。 |
| `vector_search_provider.azure_ai_search.api_key` | string | 是 | | | Azure AI Search API 密钥。 |
| `vector_search_provider.qdrant` | object | 否 | | | [Qdrant](https://qdrant.tech/documentation/) 的配置。`azure_ai_search` 和 `qdrant` 必须且只能配置其中一个。 |
| `vector_search_provider.qdrant.endpoint` | string | 是 | | | Qdrant 实例的 URL，例如 `http://127.0.0.1:6333`。URL 可以包含路径前缀。插件将搜索请求发送到 `{endpoint}/collections/{collection_name}/points/query` 的 [Query API](https://qdrant.tech/documentation/concepts/search/)。 |
| `vector_search_provider.qdrant.collection_name` | string | 是 | | | 要搜索的 [collection](https://qdrant.tech/documentation/concepts/collections/) 名称。 |
| `vector_search_provider.qdrant.api_key` | string | 否 | | | Qdrant [API 密钥](https://qdrant.tech/documentation/guides/security/)。插件在 `api-key` 请求头中发送该密钥。如果 Qdrant 实例要求 API 密钥，请配置此项。 |

## 请求体格式

请求体中必须包含以下字段。

| 字段 | 类型 | 描述 |
| --- | --- | --- |
| `ai_rag` | Object | 请求体 RAG 规范。 |
| `ai_rag.embeddings` | Object | 生成嵌入所需的请求参数。内容取决于配置的提供商的 API 规范。 |
| `ai_rag.vector_search` | Object | 执行向量搜索所需的请求参数。内容取决于配置的提供商的 API 规范。 |

- `ai_rag.embeddings` 的参数

  - Azure OpenAI

  | 名称 | 必选项 | 类型 | 描述 |
  | --- | --- | --- | --- |
  | `input` | 是 | String | 用于计算嵌入的输入文本，编码为字符串。 |
  | `user` | 否 | String | 代表最终用户的唯一标识符，可帮助监控和检测滥用行为。 |
  | `encoding_format` | 否 | String | 返回嵌入的格式。可以是 `float` 或 `base64`。默认为 `float`。 |
  | `dimensions` | 否 | Integer | 输出嵌入的维数。它应与你的嵌入模型的维数匹配。例如，`text-embedding-ada-002` 的维数固定为 1536。对于 `text-embedding-3-small` 或 `text-embedding-3-large`，维数范围分别为 1 到 1536 和 3072。 |

  有关其他参数，请参阅 [Azure OpenAI 嵌入文档](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#embeddings)。

- `ai_rag.vector_search` 的参数

  - Azure AI Search

  | 字段 | 必选项 | 类型 | 描述 |
  | --- | --- | --- | --- |
  | `fields` | 是 | String | 向量搜索的字段。 |

  有关其他参数，请参阅 [Azure AI Search 文档](https://learn.microsoft.com/en-us/rest/api/searchservice/documents/search-post)。此外，还支持[这些向量查询参数](https://learn.microsoft.com/en-us/rest/api/searchservice/documents/search-post?view=rest-searchservice-2024-07-01&tabs=HTTP#vectorizabletextquery)。

  - Qdrant

  所有字段均为可选。发送空的 `vector_search` 对象即可使用 Qdrant 的默认值。插件会以 `400` 响应拒绝其他字段。

  | 字段 | 必选项 | 类型 | 描述 |
  | --- | --- | --- | --- |
  | `limit` | 否 | Integer | 返回的 point 的最大数量，取值范围为 1 到 100。默认为 10。 |
  | `using` | 否 | String | 要搜索的向量名称，用于包含[命名向量](https://qdrant.tech/documentation/concepts/vectors/#named-vectors)的 collection。 |
  | `filter` | 否 | Object | 针对 point payload 的[过滤](https://qdrant.tech/documentation/concepts/filtering/)条件。 |
  | `params` | 否 | Object | [搜索参数](https://qdrant.tech/documentation/concepts/search/#search-api)，例如 `hnsw_ef` 和 `exact`。 |
  | `score_threshold` | 否 | Number | 返回的 point 的最低分数。 |
  | `with_payload` | 否 | Array | 要返回的 [payload 字段](https://qdrant.tech/documentation/concepts/search/#payload-and-vector-in-the-result)名称。默认返回完整的 payload。 |

  插件将匹配的 point 的 payload 以 JSON 数组的形式添加到 LLM 请求中，例如 `[{"text":"..."}]`。插件会跳过没有 payload 的 point。如果没有任何 point 包含 payload，插件不会向 LLM 请求添加消息。

  如果 Qdrant 拒绝查询（例如 `filter` 无效），插件返回 `400` 响应。如果插件无法连接 Qdrant，或 Qdrant 返回其他错误，插件返回 `502` 响应。插件将 Qdrant 的错误详情写入 APISIX 错误日志，而不是响应。

Azure AI Search 的示例请求体：

```json
{
  "ai_rag": {
    "vector_search": { "fields": "contentVector" },
    "embeddings": {
      "input": "which service is good for devops",
      "dimensions": 1024
    }
  }
}
```

Qdrant 的示例请求体：

```json
{
  "ai_rag": {
    "vector_search": {
      "limit": 3,
      "filter": {
        "must": [{ "key": "category", "match": { "value": "devops" } }]
      }
    },
    "embeddings": {
      "input": "which service is good for devops"
    }
  }
}
```

## 示例

要跟随示例操作，请创建一个 [Azure 账户](https://portal.azure.com)并完成以下步骤：

* 在 [Azure AI Foundry](https://oai.azure.com/portal) 中，部署一个生成式聊天模型（如 `gpt-4o`）和一个嵌入模型（如 `text-embedding-3-large`）。获取 API 密钥和模型端点。
* 按照 [Azure 的示例](https://github.com/Azure/azure-search-vector-samples/blob/main/demo-python/code/basic-vector-workflow/azure-search-vector-python-sample.ipynb)使用 Python 在 [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 中准备向量搜索。该示例将创建一个名为 `vectest` 的搜索索引，具有所需的架构，并上传包含 108 个各种 Azure 服务描述的[示例数据](https://github.com/Azure/azure-search-vector-samples/blob/main/data/text-sample.json)，以便基于 `title` 和 `content` 生成嵌入 `titleVector` 和 `contentVector`。在 Python 中执行向量搜索之前完成所有设置。
* 在 [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 中，[获取 Azure 向量搜索 API 密钥和搜索服务端点](https://learn.microsoft.com/en-us/azure/search/search-get-started-vector?tabs=api-key#retrieve-resource-information)。

将 API 密钥和端点保存到环境变量：

```shell
# 替换为你的值

AZ_OPENAI_DOMAIN=https://ai-plugin-developer.openai.azure.com
AZ_OPENAI_API_KEY=9m7VYroxITMDEqKKEnpOknn1rV7QNQT7DrIBApcwMLYJQQJ99ALACYeBjFXJ3w3AAABACOGXGcd
AZ_CHAT_ENDPOINT=${AZ_OPENAI_DOMAIN}/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-15-preview
AZ_EMBEDDING_MODEL=text-embedding-3-large
AZ_EMBEDDINGS_ENDPOINT=${AZ_OPENAI_DOMAIN}/openai/deployments/${AZ_EMBEDDING_MODEL}/embeddings?api-version=2023-05-15

AZ_AI_SEARCH_SVC_DOMAIN=https://ai-plugin-developer.search.windows.net
AZ_AI_SEARCH_KEY=IFZBp3fKVdq7loEVe9LdwMvVdZrad9A4lPH90AzSeC06SlR
AZ_AI_SEARCH_INDEX=vectest
AZ_AI_SEARCH_ENDPOINT=${AZ_AI_SEARCH_SVC_DOMAIN}/indexes/${AZ_AI_SEARCH_INDEX}/docs/search?api-version=2024-07-01
```

:::note

你可以使用以下命令从 `config.yaml` 获取 `admin_key` 并保存到环境变量中：

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 与 Azure 集成以获得 RAG 增强响应

以下示例演示了如何使用 [`ai-proxy`](./ai-proxy.md) 插件将请求代理到 Azure OpenAI LLM，并使用 `ai-rag` 插件生成嵌入和执行向量搜索以增强 LLM 响应。

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
  "uri": "/rag",
  "plugins": {
    "ai-rag": {
      "embeddings_provider": {
        "azure_openai": {
          "endpoint": "'"$AZ_EMBEDDINGS_ENDPOINT"'",
          "api_key": "'"$AZ_OPENAI_API_KEY"'"
        }
      },
      "vector_search_provider": {
        "azure_ai_search": {
          "endpoint": "'"$AZ_AI_SEARCH_ENDPOINT"'",
          "api_key": "'"$AZ_AI_SEARCH_KEY"'"
        }
      }
    },
    "ai-proxy": {
      "provider": "openai",
      "auth": {
        "header": {
          "api-key": "'"$AZ_OPENAI_API_KEY"'"
        }
      },
      "options": {
        "model": "gpt-4o"
      },
      "override": {
        "endpoint": "'"$AZ_CHAT_ENDPOINT"'"
      }
    }
  }
}'
```

</TabItem>
<TabItem value="adc" label="ADC">

创建路由，配置 `ai-rag` 和 [`ai-proxy`](./ai-proxy.md) 插件：

```yaml title="adc.yaml"
services:
  - name: ai-rag-service
    routes:
      - name: ai-rag-route
        uris:
          - /rag
        methods:
          - POST
        plugins:
          ai-rag:
            embeddings_provider:
              azure_openai:
                endpoint: "${AZ_EMBEDDINGS_ENDPOINT}"
                api_key: "${AZ_OPENAI_API_KEY}"
            vector_search_provider:
              azure_ai_search:
                endpoint: "${AZ_AI_SEARCH_ENDPOINT}"
                api_key: "${AZ_AI_SEARCH_KEY}"
          ai-proxy:
            provider: openai
            auth:
              header:
                api-key: "${AZ_OPENAI_API_KEY}"
            options:
              model: gpt-4o
            override:
              endpoint: "${AZ_CHAT_ENDPOINT}"
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

创建路由，配置 `ai-rag` 和 [`ai-proxy`](./ai-proxy.md) 插件：

```yaml title="ai-rag-ic.yaml"
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  namespace: aic
  name: ai-rag-plugin-config
spec:
  plugins:
    - name: ai-rag
      config:
        embeddings_provider:
          azure_openai:
            endpoint: "https://your-openai-resource.openai.azure.com/openai/deployments/text-embedding-3-large/embeddings?api-version=2023-05-15"
            api_key: "Bearer your-api-key"
        vector_search_provider:
          azure_ai_search:
            endpoint: "https://your-search-service.search.windows.net/indexes/vectest/docs/search?api-version=2024-07-01"
            api_key: "Bearer your-api-key"
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            api-key: "Bearer your-api-key"
        options:
          model: gpt-4o
        override:
          endpoint: "https://your-openai-resource.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-15-preview"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  namespace: aic
  name: ai-rag-route
spec:
  parentRefs:
    - name: apisix
  rules:
    - matches:
        - path:
            type: Exact
            value: /rag
          method: POST
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: ai-rag-plugin-config
```

</TabItem>
<TabItem value="ingress" label="APISIX Ingress Controller">

创建路由，配置 `ai-rag` 和 [`ai-proxy`](./ai-proxy.md) 插件：

```yaml title="ai-rag-ic.yaml"
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  namespace: aic
  name: ai-rag-route
spec:
  ingressClassName: apisix
  http:
    - name: ai-rag-route
      match:
        paths:
          - /rag
        methods:
          - POST
      plugins:
        - name: ai-rag
          enable: true
          config:
            embeddings_provider:
              azure_openai:
                endpoint: "https://your-openai-resource.openai.azure.com/openai/deployments/text-embedding-3-large/embeddings?api-version=2023-05-15"
                api_key: "Bearer your-api-key"
            vector_search_provider:
              azure_ai_search:
                endpoint: "https://your-search-service.search.windows.net/indexes/vectest/docs/search?api-version=2024-07-01"
                api_key: "Bearer your-api-key"
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                api-key: "Bearer your-api-key"
            options:
              model: gpt-4o
            override:
              endpoint: "https://your-openai-resource.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-15-preview"
```

</TabItem>
</Tabs>

将配置应用到集群：

```shell
kubectl apply -f ai-rag-ic.yaml
```

</TabItem>
</Tabs>

向路由发送 POST 请求，在请求体中包含向量字段名称、嵌入模型维度和输入提示：

```shell
curl "http://127.0.0.1:9080/rag" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "ai_rag":{
      "vector_search":{
        "fields":"contentVector"
      },
      "embeddings":{
        "input":"Which Azure services are good for DevOps?",
        "dimensions":1024
      }
    }
  }'
```

你应该收到类似以下的 `HTTP/1.1 200 OK` 响应：

```json
{
  "choices": [
    {
      "content_filter_results": {
        ...
      },
      "finish_reason": "length",
      "index": 0,
      "logprobs": null,
      "message": {
        "content": "Here is a list of Azure services ...",
        "role": "assistant"
      }
    }
  ],
  "created": 1740625850,
  "id": "chatcmpl-B54gQdumpfioMPIybFnirr6rq9ZZS",
  "model": "gpt-4o-2024-05-13",
  "object": "chat.completion",
  "prompt_filter_results": [
    {
      "prompt_index": 0,
      "content_filter_results": {
        ...
      }
    }
  ],
  "system_fingerprint": "fp_65792305e4",
  "usage": {
    ...
  }
}
```

### 与 Qdrant 集成以获得 RAG 增强响应

以下示例使用 [Qdrant](https://qdrant.tech/documentation/) 执行向量搜索。与上一个示例相同，它使用 Azure OpenAI 生成嵌入并作为聊天模型。

创建路由之前，请完成以下步骤：

* 启动 Qdrant 实例。对于本地实例，运行 `docker run -p 6333:6333 qdrant/qdrant`。对于托管实例，在 [Qdrant Cloud](https://cloud.qdrant.io) 中创建集群，并获取其 URL 和 API 密钥。
* [创建 collection](https://qdrant.tech/documentation/concepts/collections/#create-a-collection) 并[上传 point](https://qdrant.tech/documentation/concepts/points/#upload-points)。使用与插件相同的嵌入模型生成向量，并将 collection 的向量维度设置为该模型的维数。将每个文档的文本存储在 payload 中，例如 `text` 字段。

将 Qdrant 设置保存到环境变量中：

```shell
# 替换为你的值

QDRANT_URL=http://127.0.0.1:6333
QDRANT_API_KEY=your-qdrant-api-key
QDRANT_COLLECTION=azure-services
```

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
  "uri": "/rag",
  "plugins": {
    "ai-rag": {
      "embeddings_provider": {
        "azure_openai": {
          "endpoint": "'"$AZ_EMBEDDINGS_ENDPOINT"'",
          "api_key": "'"$AZ_OPENAI_API_KEY"'"
        }
      },
      "vector_search_provider": {
        "qdrant": {
          "endpoint": "'"$QDRANT_URL"'",
          "api_key": "'"$QDRANT_API_KEY"'",
          "collection_name": "'"$QDRANT_COLLECTION"'"
        }
      }
    },
    "ai-proxy": {
      "provider": "openai",
      "auth": {
        "header": {
          "api-key": "'"$AZ_OPENAI_API_KEY"'"
        }
      },
      "options": {
        "model": "gpt-4o"
      },
      "override": {
        "endpoint": "'"$AZ_CHAT_ENDPOINT"'"
      }
    }
  }
}'
```

</TabItem>
<TabItem value="adc" label="ADC">

创建配置了 `ai-rag` 和 [`ai-proxy`](./ai-proxy.md) 插件的路由：

```yaml title="adc.yaml"
services:
  - name: ai-rag-service
    routes:
      - name: ai-rag-route
        uris:
          - /rag
        methods:
          - POST
        plugins:
          ai-rag:
            embeddings_provider:
              azure_openai:
                endpoint: "${AZ_EMBEDDINGS_ENDPOINT}"
                api_key: "${AZ_OPENAI_API_KEY}"
            vector_search_provider:
              qdrant:
                endpoint: "${QDRANT_URL}"
                api_key: "${QDRANT_API_KEY}"
                collection_name: "${QDRANT_COLLECTION}"
          ai-proxy:
            provider: openai
            auth:
              header:
                api-key: "${AZ_OPENAI_API_KEY}"
            options:
              model: gpt-4o
            override:
              endpoint: "${AZ_CHAT_ENDPOINT}"
```

将配置同步到网关：

```shell
adc sync -f adc.yaml
```

</TabItem>
</Tabs>

向路由发送 POST 请求，在请求体中包含搜索参数和输入提示：

```shell
curl "http://127.0.0.1:9080/rag" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "ai_rag":{
      "vector_search":{
        "limit":3,
        "with_payload":["text"]
      },
      "embeddings":{
        "input":"Which Azure services are good for DevOps?"
      }
    }
  }'
```

插件在 collection 中查找最近的三个 point，并将它们的 `text` payload 字段添加到 LLM 请求中。你应该收到 `HTTP/1.1 200 OK` 响应，其中包含模型基于检索到的文本给出的回答。
