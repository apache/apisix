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

The Plugin supports using [OpenAI](https://platform.openai.com/docs/api-reference/embeddings) or [Azure OpenAI](https://learn.microsoft.com/en-us/azure/search/vector-search-how-to-generate-embeddings?tabs=rest-api) services for generating embeddings, [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) services for performing vector search, and optionally [Cohere Rerank](https://docs.cohere.com/docs/rerank-overview) services for reranking the retrieval results.

## Attributes

| Name                                      |   Required   |   Type   | Valid Values | Description                                                                                                                             |
| ----------------------------------------------- | ------------ | -------- | --- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| embeddings_provider                             | True         | object   | openai, azure-openai, openai-compatible | Configurations of the embedding models provider. Must and can only specify one. Currently supports `openai`, `azure-openai`, `openai-compatible`.                                                                                         |
| vector_search_provider                          | True         | object   | azure-ai-search | Configuration for the vector search provider.                                                                                              |
| vector_search_provider.azure-ai-search          | True         | object   |  | Configuration for Azure AI Search.                                                                                                         |
| vector_search_provider.azure-ai-search.endpoint | True         | string   |  | Azure AI Search endpoint.                                                                                                                  |
| vector_search_provider.azure-ai-search.api_key  | True         | string   |  | Azure AI Search API key.                                                                                                                  |
| vector_search_provider.azure-ai-search.fields   | True         | string   |  | Target fields for vector search.                                                                                           |
| vector_search_provider.azure-ai-search.select   | True         | string   |  | Fields to select in the response.                                                                            |
| vector_search_provider.azure-ai-search.exhaustive| False       | boolean  |  | Whether to perform an exhaustive search. Defaults to `true`.                                                                                       |
| vector_search_provider.azure-ai-search.k        | False        | integer  | >0 | Number of nearest neighbors to return. Defaults to 5.                                                                                              |
| rerank_provider                                 | False        | object   | cohere | Configuration for the rerank provider.                                                                                                |
| rerank_provider.cohere                          | False        | object   |  | Configuration for Cohere Rerank.                                                                                                            |
| rerank_provider.cohere.endpoint                 | False        | string   |  | Cohere Rerank API endpoint. Defaults to `https://api.cohere.ai/v1/rerank`.                                                               |
| rerank_provider.cohere.api_key                  | True         | string   |  | Cohere API key.                                                                                                                    |
| rerank_provider.cohere.model                    | False        | string   |  | Rerank model name.                                                                                    |
| rerank_provider.cohere.top_n                    | False        | integer  |  | Number of top results to keep after reranking. Defaults to 3.                                                                                                |
| rag_config                                      | False        | object   |  | General configuration for the RAG process.                                                                                                 |
| rag_config.input_strategy                       | False        | string   |  | Strategy for extracting input text from messages. Values: `last` (last user message), `all` (concatenate all user messages). Defaults to `last`.                                     |

### embeddings_provider attributes

Currently supports `openai`, `azure-openai`, `openai-compatible`. All sub-fields are located under the `embeddings_provider.<provider>` object (e.g., `embeddings_provider.openai.api_key`).

| Name        | Required | Type    | Description                                                                 |
|-------------|--------|---------|----------------------------------------------------------------------|
| `endpoint`  | True     | string  | API service endpoint.<br>• OpenAI: `https://api.openai.com/v1`<br>• Azure: `https://<your-resource>.openai.azure.com/` |
| `api_key`   | True     | string  | Access credential (API Key).                                               |
| `model`     | False     | string  | Model name. Defaults to `text-embedding-3-large`.                         |
| `dimensions`| False     | integer | Vector dimensions (only supported by `text-embedding-3-*` series).                      |

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

COHERE_DOMAIN=https://api.cohere.ai/v2/rerank
COHERE_API_KEY=1I3xUcm6mfYzNnHGX3UaEEYyEP
COHERE_MODEL="Cohere-rerank-v4.0-fast"
```

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Integrate with Azure for RAG-Enhaned Responses

The following example demonstrates how to configure the `ai-rag` Plugin to use Azure OpenAI for embeddings, Azure AI Search for vector retrieval, and Cohere for result reranking, finally proxying the request to the LLM via `ai-proxy`.

Create a Route:

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

Send a POST request to the Route:

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

The plugin will:

1. Extract the user question "Which Azure services are good for DevOps?".
2. Call Azure OpenAI to generate an embedding vector for the question.
3. Use the vector to retrieve the top 10 most relevant documents from Azure AI Search (`k=10`).
4. Call the Cohere Rerank API to rerank these 10 documents and keep the top 3 (`top_n=3`).
5. Inject the content of these 3 documents as context into the `messages` of the request.
6. Forward the augmented request to `ai-proxy` (and subsequently to the LLM).
