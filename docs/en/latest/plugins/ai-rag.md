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
augments the AI's responses with that data, improving the accuracy and context of generated outputs.

**_This plugin must be used in routes that proxy requests to LLMs only._**

## Plugin Attributes

| **Field**                                       | **Required** | **Type** | **Description**                              |
| ----------------------------------------------- | ------------ | -------- | -------------------------------------------- |
| embeddings_provider                             | Yes          | Object   | Configuration for the embeddings provider    |
| embeddings_provider.azure_openai                | Yes          | Object   | Configuration for Azure OpenAI embeddings    |
| embeddings_provider.azure_openai.endpoint       | Yes          | String   | Azure OpenAI endpoint                        |
| embeddings_provider.azure_openai.api_key        | Yes          | String   | Azure OpenAI API key                         |
| vector_search_provider                          | Yes          | Object   | Configuration for the vector search provider |
| vector_search_provider.azure_ai_search          | Yes          | Object   | Configuration for Azure AI Search            |
| vector_search_provider.azure_ai_search.endpoint | No           | String   | Azure AI Search endpoint                     |
| vector_search_provider.azure_ai_search.api_key  | No           | String   | Azure AI Search API key                      |

## Request Body Format

The following fields must be present in the request body.

| **Field**            | **Type** | **Description**                                                                                                                 |
| -------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------- |
| ai_rag               | Object   | Configuration for AI-RAG (Retrieval Augmented Generation)                                                                       |
| ai_rag.embeddings    | Object   | Request parameters required to generate embeddings. Contents will depend on the API specification of the configured provider.   |
| ai_rag.vector_search | Object   | Request parameters required to perform vector search. Contents will depend on the API specification of the configured provider. |

- Contents of ai_rag.embeddings

  - Azure OpenAI

  | **Field** | **Required** | **Type** | **Description**             |
  | --------- | ------------ | -------- | --------------------------- |
  | input     | Yes          | String   | Query string for embeddings |
  ## TODO: copy more fields from azure docs

  For other parameters please refer the Azure OpenAI embeddings documentation.

- Contents of ai_rag.vector_search

  - Azure AI Search

  | **Field** | **Required** | **Type** | **Description**              |
  | --------- | ------------ | -------- | ---------------------------- |
  | fields    | Yes          | String   | Fields for the vector search |
  ## TODO: copy more fields from azure docs

  For other parameters please refer the Azure AI Search documentation.

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
azure_openai_endpoint=https://name.openai.azure.com/openai/deployments/gpt-4o/chat/completions
vector_search_endpoint=https://name.search.windows.net/indexes/indexname/docs/search?api-version=2024-07-01
embeddings_endpoint=https://name.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2023-05-15
embeddings_key=secret-azure-openai-embeddings-key
search_key=secret-azureai-search-key
azure_openai_key=secret-azure-openai-key
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
          "endpoint": "'"$embeddings_endpoint"'",
          "api_key": "'"$embeddings_key"'"
        }
      },
      "vector_search_provider": {
        "azure_ai_search": {
          "endpoint": "'"$vector_search_endpoint"'",
          "api_key": "'"$search_key"'"
        }
      }
    },
    "ai-proxy": {
      "route_type": "llm/chat",
      "auth": {
        "header": {
          "api-key": "'"$azure_openai_key"'"
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
        "endpoint": "'"$azure_openai_endpoint"'"
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

The `ai-proxy` plugin is used here as it simplifies access to LLMs. However, you may configure the LLM in the upstream configuration as well.

Now send a request:

```shell
curl http://127.0.0.1:9080/rag -XPOST  -H 'Content-Type: application/json' -d '{"ai_rag":{"vector_search":{"fields":"contentVector"},"embeddings":{"input":"which service is good for devops","dimensions":1024}}}'
```
