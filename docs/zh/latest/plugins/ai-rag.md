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

该插件支持使用 [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) 和 [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 服务来生成嵌入和执行向量搜索。

**_目前仅支持 [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) 和 [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) 服务来生成嵌入和执行向量搜索。欢迎提交 PR 以引入对其他服务提供商的支持。_**

## 属性

| 名称                                      |   必选项   |   类型   |   描述                                                                                                                             |
| ----------------------------------------------- | ------------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| embeddings_provider                             | 是          | object   | 嵌入模型提供商的配置。                                                                                           |
| embeddings_provider.azure_openai                | 是          | object   | [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) 作为嵌入模型提供商的配置。 |
| embeddings_provider.azure_openai.endpoint       | 是          | string   | Azure OpenAI 嵌入模型端点。                                                                                  |
| embeddings_provider.azure_openai.api_key        | 是          | string   | Azure OpenAI API 密钥。                                                                                                                    |
| vector_search_provider                          | 是          | object   | 向量搜索提供商的配置。                                                                                              |
| vector_search_provider.azure_ai_search          | 是          | object   | Azure AI Search 的配置。                                                                                                         |
| vector_search_provider.azure_ai_search.endpoint | 是          | string   | Azure AI Search 端点。                                                                                                                  |
| vector_search_provider.azure_ai_search.api_key  | 是          | string   | Azure AI Search API 密钥。                                                                                                                  |

## 请求体格式

请求体中必须包含以下字段。

|   字段              |   类型   |    描述                                                                                                                   |
| -------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------- |
| ai_rag               | object   | 请求体 RAG 规范。                                                                              |
| ai_rag.embeddings    | object   | 生成嵌入所需的请求参数。内容将取决于配置的提供商的 API 规范。   |
| ai_rag.vector_search | object   | 执行向量搜索所需的请求参数。内容将取决于配置的提供商的 API 规范。 |

- `ai_rag.embeddings` 的参数

  - Azure OpenAI

  |   名称          |   必选项   |   类型   |   描述                                                                                                              |
  | --------------- | ------------ | -------- | -------------------------------------------------------------------------------------------------------------------------- |
  | input           | 是          | string   | 用于计算嵌入的输入文本，编码为字符串。                                                                |
  | user            | 否           | string   | 代表您的最终用户的唯一标识符，可以帮助监控和检测滥用。                          |
  | encoding_format | 否           | string   | 返回嵌入的格式。可以是 `float` 或 `base64`。默认为 `float`。                            |
  | dimensions      | 否           | integer  | 结果输出嵌入应具有的维数。仅在 text-embedding-3 及更高版本的模型中支持。 |

有关其他参数，请参阅 [Azure OpenAI 嵌入文档](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#embeddings)。

- `ai_rag.vector_search` 的参数

  - Azure AI Search

  |   字段   |   必选项   |   类型   |   描述                |
  | --------- | ------------ | -------- | ---------------------------- |
  | fields    | 是          | String   | 向量搜索的字段。 |

  有关其他参数，请参阅 [Azure AI Search 文档](https://learn.microsoft.com/en-us/rest/api/searchservice/documents/search-post)。

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
```

:::note

您可以使用以下命令从 `config.yaml` 获取 `admin_key` 并保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 与 Azure 集成以获得 RAG 增强响应

以下示例演示了如何使用 [`ai-proxy`](ai-proxy.md) 插件将请求代理到 Azure OpenAI LLM，并使用 `ai-rag` 插件生成嵌入和执行向量搜索以增强 LLM 响应。

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

您应该收到类似以下的 `HTTP/1.1 200 OK` 响应：

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
        "content": "Here is a list of Azure services categorized along with a brief description of each based on the provided JSON data:\n\n### Developer Tools\n- **Azure DevOps**: A suite of services that help you plan, build, and deploy applications, including Azure Boards, Azure Repos, Azure Pipelines, Azure Test Plans, and Azure Artifacts.\n- **Azure DevTest Labs**: A fully managed service to create, manage, and share development and test environments in Azure, supporting custom templates, cost management, and integration with Azure DevOps.\n\n### Containers\n- **Azure Kubernetes Service (AKS)**: A managed container orchestration service based on Kubernetes, simplifying deployment and management of containerized applications with features like automatic upgrades and scaling.\n- **Azure Container Instances**: A serverless container runtime to run and scale containerized applications without managing the underlying infrastructure.\n- **Azure Container Registry**: A fully managed Docker registry service to store and manage container images and artifacts.\n\n### Web\n- **Azure App Service**: A fully managed platform for building, deploying, and scaling web apps, mobile app backends, and RESTful APIs with support for multiple programming languages.\n- **Azure SignalR Service**: A fully managed real-time messaging service to build and scale real-time web applications.\n- **Azure Static Web Apps**: A serverless hosting service for modern web applications using static front-end technologies and serverless APIs.\n\n### Compute\n- **Azure Virtual Machines**: Infrastructure-as-a-Service (IaaS) offering for deploying and managing virtual machines in the cloud.\n- **Azure Functions**: A serverless compute service to run event-driven code without managing infrastructure.\n- **Azure Batch**: A job scheduling service to run large-scale parallel and high-performance computing (HPC) applications.\n- **Azure Service Fabric**: A platform to build, deploy, and manage scalable and reliable microservices and container-based applications.\n- **Azure Quantum**: A quantum computing service to build and run quantum applications.\n- **Azure Stack Edge**: A managed edge computing appliance to run Azure services and AI workloads on-premises or at the edge.\n\n### Security\n- **Azure Bastion**: A fully managed service providing secure and scalable remote access to virtual machines.\n- **Azure Security Center**: A unified security management service to protect workloads across Azure and on-premises infrastructure.\n- **Azure DDoS Protection**: A cloud-based service to protect applications and resources from distributed denial-of-service (DDoS) attacks.\n\n### Databases\n",
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
