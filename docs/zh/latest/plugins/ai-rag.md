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

该插件支持使用 [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) 和 [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 服务来生成嵌入和执行向量搜索。欢迎提交 PR 以引入对其他服务提供商的支持。

## 插件属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `embeddings_provider` | object | 是 | | | 嵌入模型提供商的配置。 |
| `embeddings_provider.azure_openai` | object | 是 | | | [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) 嵌入模型的配置。 |
| `embeddings_provider.azure_openai.endpoint` | string | 是 | | | Azure OpenAI 嵌入模型端点。 |
| `embeddings_provider.azure_openai.api_key` | string | 是 | | | Azure OpenAI API 密钥。 |
| `vector_search_provider` | object | 是 | | | 向量搜索提供商的配置。 |
| `vector_search_provider.azure_ai_search` | object | 是 | | | [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 的配置。 |
| `vector_search_provider.azure_ai_search.endpoint` | string | 是 | | | Azure AI Search 端点。 |
| `vector_search_provider.azure_ai_search.api_key` | string | 是 | | | Azure AI Search API 密钥。支持通过环境变量（如 `$ENV://AI_RAG_APIKEY`）和密钥管理器进行[密钥引用](../terminology/secret.md)。 |

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

示例请求体：

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
      "model": "gpt-4o",
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

## 密钥引用

`api_key` 字段支持通过环境变量和密钥管理器进行 APISIX 密钥解析。有关密钥引用格式和设置，请参阅 [APISIX 密钥](../terminology/secret.md)。示例：

```json
{
  "embeddings_provider": {
    "azure_openai": {
      "endpoint": "'"$AZ_EMBEDDINGS_ENDPOINT"'",
      "api_key": "$ENV://API_KEY"
    }
  },
  "vector_search_provider": {
    "azure_ai_search": {
      "endpoint": "'"$AZ_AI_SEARCH_ENDPOINT"'",
      "api_key": "$secret://$manager/$id/$secret_name/$key"
    }
  }
}
```
