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

## 描述

`ai-rag` 插件为 LLM 提供检索增强生成（Retrieval-Augmented Generation，RAG）功能。它促进从外部数据源高效检索相关文档或信息，这些信息用于增强 LLM 响应，从而提高生成输出的准确性和上下文相关性。

该插件支持使用 [OpenAI](https://platform.openai.com/docs/api-reference/embeddings) 或 [Azure OpenAI](https://learn.microsoft.com/en-us/azure/search/vector-search-how-to-generate-embeddings?tabs=rest-api) 服务生成嵌入，使用 [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 服务执行向量搜索，以及可选的 [Cohere Rerank](https://docs.cohere.com/docs/rerank-overview) 服务对检索结果进行重排序。

## 属性

| 名称                                      |   必选项   |   类型   | 有效值 |  描述                                                                                                                             |
| ----------------------------------------------- | ------------ | -------- | --- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| embeddings_provider                             | 是          | object   | openai, azure-openai, openai-compatible | 嵌入模型提供商的配置。必须且只能指定一种，当前支持 `openai`, `azure-openai`, `openai-compatible`                                                                                         |
| vector_search_provider                          | 是          | object   | azure-ai-search | 向量搜索提供商的配置。                                                                                              |
| vector_search_provider.azure-ai-search          | 是          | object   |  | Azure AI Search 的配置。                                                                                                         |
| vector_search_provider.azure-ai-search.endpoint | 是          | string   |  | Azure AI Search 端点。                                                                                                                  |
| vector_search_provider.azure-ai-search.api_key  | 是          | string   |  | Azure AI Search API 密钥。                                                                                                                  |
| vector_search_provider.azure-ai-search.fields   | 是          | string   |  | 向量搜索的目标字段。                                                                                           |
| vector_search_provider.azure-ai-search.select   | 是          | string   |  | 响应中选择返回的字段。                                                                            |
| vector_search_provider.azure-ai-search.exhaustive| 否         | boolean  |  | 是否进行详尽搜索。默认为 `true`。                                                                                       |
| vector_search_provider.azure-ai-search.k        | 否          | integer  | >0 | 返回的最近邻数量。默认为 5。                                                                                              |
| rerank_provider                                 | 否          | object   | cohere | 重排序提供商的配置。                                                                                                |
| rerank_provider.cohere                          | 否          | object   |  | Cohere Rerank 的配置。                                                                                                            |
| rerank_provider.cohere.endpoint                 | 否          | string   |  | Cohere Rerank API 端点。默认为 `https://api.cohere.ai/v1/rerank`。                                                               |
| rerank_provider.cohere.api_key                  | 是          | string   |  | Cohere API 密钥。                                                                                                                    |
| rerank_provider.cohere.model                    | 否          | string   |  | 重排序模型名称。                                                                                    |
| rerank_provider.cohere.top_n                    | 否          | integer  |  | 重排序后保留的文档数量。默认为 3。                                                                                                |
| rag_config                                      | 否          | object   |  | RAG 流程的通用配置。                                                                                                 |
| rag_config.input_strategy                       | 否          | string   |  | 提取用户输入文本的策略。可选值：`last`（仅最后一条消息），`all`（所有用户消息拼接）。默认为 `last`。                                     |

### embeddings_provider 属性

当前支持`openai`,`azure-openai`,`openai-compatible`,所有子字段均位于 `embeddings_provider.<provider>` 对象下（例如 `embeddings_provider.openai.api_key`）。

| 名称        | 必选项 | 类型    | 描述                                                                 |
|-------------|--------|---------|----------------------------------------------------------------------|
| `endpoint`  | 是     | string  | API 服务端点。<br>• OpenAI: `https://api.openai.com/v1`<br>• Azure: `https://<your-resource>.openai.azure.com/` |
| `api_key`   | 是     | string  | 访问凭证（API Key）。                                               |
| `model`     | 否     | string  | 模型名称，默认为 `text-embedding-3-large`。                         |
| `dimensions`| 否     | integer | 向量维度（仅 `text-embedding-3-*` 系列支持）。                      |

## 示例

要跟随示例，请创建一个 [Azure 账户](https://portal.azure.com)并完成以下步骤：

* 在 [Azure AI Foundry](https://oai.azure.com/portal) 中，部署一个生成式聊天模型，如 `gpt-4o`，以及一个嵌入模型，如 `text-embedding-3-large`。获取 API 密钥和模型端点。
* 按照 [Azure 的示例](https://github.com/Azure/azure-search-vector-samples/blob/main/demo-python/code/basic-vector-workflow/azure-search-vector-python-sample.ipynb)使用 Python 在 [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 中准备向量搜索。该示例将创建一个名为 `vectest` 的搜索索引，具有所需的架构，并上传包含 108 个各种 Azure 服务描述的[示例数据](https://github.com/Azure/azure-search-vector-samples/blob/main/data/text-sample.json)，以便基于 `title` 和 `content` 生成嵌入 `titleVector` 和 `contentVector`。在 Python 中执行向量搜索之前完成所有设置。
* 在 [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 中，[获取 Azure 向量搜索 API 密钥和搜索服务端点](https://learn.microsoft.com/en-us/azure/search/search-get-started-vector?tabs=api-key#retrieve-resource-information)。

将 API 密钥和端点保存到环境变量：

```shell
# 替换为您的值

AZ_OPENAI_DOMAIN=https://ai-plugin-developer.openai.azure.com
AZ_OPENAI_API_KEY=9m7VYroxITMDEqKKEnpOknn1rV7QNQT7DrIBApcwMLYJQQJ99ALACYeBjFXJ3w3AAABACOGXGcd
AZ_CHAT_ENDPOINT=${AZ_OPENAI_DOMAIN}/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-15-preview
AZ_EMBEDDING_MODEL=text-embedding-3-large
AZ_EMBEDDINGS_ENDPOINT=${AZ_OPENAI_DOMAIN}/openai/deployments/${AZ_EMBEDDING_MODEL}/embeddings?api-version=2023-05-15

AZ_AI_SEARCH_SVC_DOMAIN=https://ai-plugin-developer.search.windows.net
AZ_AI_SEARCH_KEY=IFZBp3fKVdq7loEVe9LdwMvVdZrad9A4lPH90AzSeC06SlR
AZ_AI_SEARCH_INDEX=vectest
AZ_AI_SEARCH_ENDPOINT=${AZ_AI_SEARCH_SVC_DOMAIN}/indexes/${AZ_AI_SEARCH_INDEX}/docs/search?api-version=2024-07-01

COHERE_DOMAIN=https://api.cohere.ai/v2/rerank
COHERE_API_KEY=1I3xUcm6mfYzNnHGX3UaEEYyEP
COHERE_MODEL="Cohere-rerank-v4.0-fast"
```

:::note

您可以使用以下命令从 `config.yaml` 获取 `admin_key` 并保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 与 Azure 集成以获得 RAG 增强响应

以下示例演示了如何配置 `ai-rag` 插件，使用 Azure OpenAI 生成嵌入，Azure AI Search 进行向量检索，并使用 Cohere 进行结果重排序，最后通过 `ai-proxy` 调用 LLM。

创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
    "id": "ai-rag-route",
    "uri": "/rag",
    "plugins": {
      "ai-rag": {
        "embeddings_provider": {
          "azure-openai": {
            "endpoint": "'"$AZ_EMBEDDINGS_ENDPOINT"'",
            "api_key": "'"$AZ_OPENAI_API_KEY"'"
          }
        },
        "vector_search_provider": {
          "azure-ai-search": {
            "endpoint": "'"$AZ_AI_SEARCH_ENDPOINT"'",
            "api_key": "'"$AZ_AI_SEARCH_KEY"'",
            "fields": "contentVector",
            "select": "content",
            "k": 10
          }
        },
        "rerank_provider": {
          "cohere": {
              "endpoint":"'"$COHERE_DOMAIN"'",
              "api_key": "'"$COHERE_API_KEY"'",
              "model": "'"$COHERE_MODEL"'",
              "top_n": 3
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

向路由发送 POST 请求：

```shell
curl "http://127.0.0.1:9080/rag" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
        {
            "role": "user",
            "content": "Which Azure services are good for DevOps?"
        }
    ]
  }'
```

插件将会：

1. 提取用户问题 "Which Azure services are good for DevOps?"。
2. 调用 Azure OpenAI 生成该问题的嵌入向量。
3. 使用向量在 Azure AI Search 中检索最相关的 10 个文档 (`k=10`)。
4. 调用 Cohere Rerank API 对这 10 个文档进行重排序，并取前 3 个 (`top_n=3`)。
5. 将这 3 个文档的内容作为上下文注入到请求的 `messages` 中。
6. 将增强后的请求转发给 `ai-proxy`（进而转发给 LLM）。
