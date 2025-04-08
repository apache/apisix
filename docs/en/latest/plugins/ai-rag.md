---
title: ai-rag
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-rag
  - AI
  - LLM
description: The ai-rag Plugin enhances LLM outputs with Retrieval-Augmented Generation (RAG), efficiently retrieving relevant documents to improve accuracy and contextual relevance in responses.
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

## Description

The `ai-rag` Plugin provides Retrieval-Augmented Generation (RAG) capabilities with LLMs. It facilitates the efficient retrieval of relevant documents or information from external data sources, which are used to enhance the LLM responses, thereby improving the accuracy and contextual relevance of the generated outputs.

The Plugin supports using [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) and [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) services for generating embeddings and performing vector search.

**_As of now only [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) and [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) services are supported for generating embeddings and performing vector search respectively. PRs for introducing support for other service providers are welcomed._**

## Attributes

| Name                                      |   Required   |   Type   |   Description                                                                                                                             |
| ----------------------------------------------- | ------------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| embeddings_provider                             | True          | object   | Configurations of the embedding models provider.                                                                                           |
| embeddings_provider.azure_openai                | True          | object   | Configurations of [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) as the embedding models provider. |
| embeddings_provider.azure_openai.endpoint       | True          | string   | Azure OpenAI embedding model endpoint.                                                                                  |
| embeddings_provider.azure_openai.api_key        | True          | string   | Azure OpenAI API key.                                                                                                                    |
| vector_search_provider                          | True          | object   | Configuration for the vector search provider.                                                                                              |
| vector_search_provider.azure_ai_search          | True          | object   | Configuration for Azure AI Search.                                                                                                         |
| vector_search_provider.azure_ai_search.endpoint | True          | string   | Azure AI Search endpoint.                                                                                                                  |
| vector_search_provider.azure_ai_search.api_key  | True          | string   | Azure AI Search API key.                                                                                                                  |

## Request Body Format

The following fields must be present in the request body.

|   Field              |   Type   |    Description                                                                                                                   |
| -------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------- |
| ai_rag               | object   | Request body RAG specifications.                                                                              |
| ai_rag.embeddings    | object   | Request parameters required to generate embeddings. Contents will depend on the API specification of the configured provider.   |
| ai_rag.vector_search | object   | Request parameters required to perform vector search. Contents will depend on the API specification of the configured provider. |

- Parameters of `ai_rag.embeddings`

  - Azure OpenAI

  |   Name          |   Required   |   Type   |   Description                                                                                                              |
  | --------------- | ------------ | -------- | -------------------------------------------------------------------------------------------------------------------------- |
  | input           | True          | string   | Input text used to compute embeddings, encoded as a string.                                                                |
  | user            | False           | string   | A unique identifier representing your end-user, which can help in monitoring and detecting abuse.                          |
  | encoding_format | False           | string   | The format to return the embeddings in. Can be either `float` or `base64`. Defaults to `float`.                            |
  | dimensions      | False           | integer  | The number of dimensions the resulting output embeddings should have. Only supported in text-embedding-3 and later models. |

For other parameters please refer to the [Azure OpenAI embeddings documentation](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#embeddings).

- Parameters of `ai_rag.vector_search`

  - Azure AI Search

  |   Field   |   Required   |   Type   |   Description                |
  | --------- | ------------ | -------- | ---------------------------- |
  | fields    | True          | String   | Fields for the vector search. |

  For other parameters please refer the [Azure AI Search documentation](https://learn.microsoft.com/en-us/rest/api/searchservice/documents/search-post).

Example request body:

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

## Example

To follow along the example, create an [Azure account](https://portal.azure.com) and complete the following steps:

* In [Azure AI Foundry](https://oai.azure.com/portal), deploy a generative chat model, such as `gpt-4o`, and an embedding model, such as `text-embedding-3-large`. Obtain the API key and model endpoints.
* Follow [Azure's example](https://github.com/Azure/azure-search-vector-samples/blob/main/demo-python/code/basic-vector-workflow/azure-search-vector-python-sample.ipynb) to prepare for a vector search in [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) using Python. The example will create a search index called `vectest` with the desired schema and upload the [sample data](https://github.com/Azure/azure-search-vector-samples/blob/main/data/text-sample.json) which contains 108 descriptions of various Azure services, for embeddings `titleVector` and `contentVector` to be generated based on `title` and `content`. Complete all the setups before performing vector searches in Python.
* In [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search), [obtain the Azure vector search API key and the search service endpoint](https://learn.microsoft.com/en-us/azure/search/search-get-started-vector?tabs=api-key#retrieve-resource-information).

Save the API keys and endpoints to environment variables:

```shell
# replace with your values

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

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Integrate with Azure for RAG-Enhaned Responses

The following example demonstrates how you can use the [`ai-proxy`](./ai-proxy.md) Plugin to proxy requests to Azure OpenAI LLM and use the `ai-rag` Plugin to generate embeddings and perform vector search to enhance LLM responses.

Create a Route as such:

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

Send a POST request to the Route with the vector fields name, embedding model dimensions, and an input prompt in the request body:

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

You should receive an `HTTP/1.1 200 OK` response similar to the following:

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
