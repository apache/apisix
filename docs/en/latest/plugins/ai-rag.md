---
title: ai-rag
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-rag
description: This document contains information about the Apache APISIX ai-rag Plugin.
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

## Description

The `ai-rag` plugin integrates Retrieval-Augmented Generation (RAG) capabilities with AI models.
It allows efficient retrieval of relevant documents or information from external data sources and
augments the LLM responses with that data, improving the accuracy and context of generated outputs.

**_As of now only [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) and [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) services are supported for generating embeddings and performing vector search respectively. PRs for introducing support for other service providers are welcomed._**

## Plugin Attributes

| **Field**                                       | **Required** | **Type** | **Description**                                                                                                                           |
| ----------------------------------------------- | ------------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| embeddings_provider                             | Yes          | object   | Configurations of the embedding models provider                                                                                           |
| embeddings_provider.azure_openai                | Yes          | object   | Configurations of [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) as the embedding models provider. |
| embeddings_provider.azure_openai.endpoint       | Yes          | string   | Azure OpenAI endpoint                                                                                                                     |
| embeddings_provider.azure_openai.api_key        | Yes          | string   | Azure OpenAI API key                                                                                                                      |
| vector_search_provider                          | Yes          | object   | Configuration for the vector search provider                                                                                              |
| vector_search_provider.azure_ai_search          | Yes          | object   | Configuration for Azure AI Search                                                                                                         |
| vector_search_provider.azure_ai_search.endpoint | Yes          | string   | Azure AI Search endpoint                                                                                                                  |
| vector_search_provider.azure_ai_search.api_key  | Yes          | string   | Azure AI Search API key                                                                                                                   |

## Request Body Format

The following fields must be present in the request body.

| **Field**            | **Type** | **Description**                                                                                                                 |
| -------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------- |
| ai_rag               | object   | Configuration for AI-RAG (Retrieval Augmented Generation)                                                                       |
| ai_rag.embeddings    | object   | Request parameters required to generate embeddings. Contents will depend on the API specification of the configured provider.   |
| ai_rag.vector_search | object   | Request parameters required to perform vector search. Contents will depend on the API specification of the configured provider. |

- Parameters of `ai_rag.embeddings`

  - Azure OpenAI

  | **Name**        | **Required** | **Type** | **Description**                                                                                                            |
  | --------------- | ------------ | -------- | -------------------------------------------------------------------------------------------------------------------------- |
  | input           | Yes          | string   | Input text used to compute embeddings, encoded as a string.                                                                |
  | user            | No           | string   | A unique identifier representing your end-user, which can help in monitoring and detecting abuse.                          |
  | encoding_format | No           | string   | The format to return the embeddings in. Can be either `float` or `base64`. Defaults to `float`.                            |
  | dimensions      | No           | integer  | The number of dimensions the resulting output embeddings should have. Only supported in text-embedding-3 and later models. |

For other parameters please refer to the [Azure OpenAI embeddings documentation](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#embeddings).

- Parameters of `ai_rag.vector_search`

  - Azure AI Search

  | **Field** | **Required** | **Type** | **Description**              |
  | --------- | ------------ | -------- | ---------------------------- |
  | fields    | Yes          | String   | Fields for the vector search |

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

## Example usage

First initialise these shell variables:

```shell
ADMIN_API_KEY=edd1c9f034335f136f87ad84b625c8f1
AZURE_OPENAI_ENDPOINT=https://name.openai.azure.com/openai/deployments/gpt-4o/chat/completions
VECTOR_SEARCH_ENDPOINT=https://name.search.windows.net/indexes/indexname/docs/search?api-version=2024-07-01
EMBEDDINGS_ENDPOINT=https://name.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2023-05-15
EMBEDDINGS_KEY=secret-azure-openai-embeddings-key
SEARCH_KEY=secret-azureai-search-key
AZURE_OPENAI_KEY=secret-azure-openai-key
```

Create a route with the `ai-rag` and `ai-proxy` plugin like so:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: ${ADMIN_API_KEY}" \
  -d '{
  "uri": "/rag",
  "plugins": {
    "ai-rag": {
      "embeddings_provider": {
        "azure_openai": {
          "endpoint": "'"$EMBEDDINGS_ENDPOINT"'",
          "api_key": "'"$EMBEDDINGS_KEY"'"
        }
      },
      "vector_search_provider": {
        "azure_ai_search": {
          "endpoint": "'"$VECTOR_SEARCH_ENDPOINT"'",
          "api_key": "'"$SEARCH_KEY"'"
        }
      }
    },
    "ai-proxy": {
      "auth": {
        "header": {
          "api-key": "'"$AZURE_OPENAI_KEY"'"
        },
        "query": {
          "api-version": "2023-03-15-preview"
         }
      },
      "model": {
        "provider": "openai",
        "name": "gpt-4",
        "options": {
          "max_tokens": 512,
          "temperature": 1.0
        }
      },
      "override": {
        "endpoint": "'"$AZURE_OPENAI_ENDPOINT"'"
      }
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "someupstream.com:443": 1
    },
    "scheme": "https",
    "pass_host": "node"
  }
}'
```

The `ai-proxy` plugin is used here as it simplifies access to LLMs. Alternatively, you may configure the LLM service address in the upstream configuration and update the route URI as well.

Now send a request:

```shell
curl http://127.0.0.1:9080/rag -XPOST  -H 'Content-Type: application/json' -d '{"ai_rag":{"vector_search":{"fields":"contentVector"},"embeddings":{"input":"which service is good for devops","dimensions":1024}}}'
```

You will receive a response like this:

```json
{
  "choices": [
    {
      "finish_reason": "length",
      "index": 0,
      "message": {
        "content": "Here are the details for some of the services you inquired about from your Azure search context:\n\n### 1. Azure DevOps\n* ... <rest of the response>",
        "role": "assistant"
      }
    }
  ],
  "created": 1727079764,
  "id": "chatcmpl-AAYdA40YjOaeIHfgFBkaHkUFCWxfc",
  "model": "gpt-4o-2024-05-13",
  "object": "chat.completion",
  "system_fingerprint": "fp_67802d9a6d",
  "usage": {
    "completion_tokens": 512,
    "prompt_tokens": 6560,
    "total_tokens": 7072
  }
}
```
