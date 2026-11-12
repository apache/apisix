---
title: ai-rag
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-rag
  - AI
  - LLM
description: The ai-rag Plugin retrieves context with Azure OpenAI embeddings and Azure AI Search or Qdrant before an LLM request is proxied.
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

## Description

The `ai-rag` Plugin implements the retrieval step of a Retrieval-Augmented Generation (RAG) request flow. It generates an embedding from the request, performs a vector search, adds the retrieved content to the protocol-specific LLM request input, and removes the `ai_rag` request object before the request is proxied.

The current implementation supports [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) for embeddings, and [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) or [Qdrant](https://qdrant.tech/documentation/) for vector search. Use the [`ai-proxy`](./ai-proxy.md) Plugin in the same request flow to proxy the augmented request to the LLM provider. Create and fill the search index or collection before you send requests through APISIX. The Plugin only reads from it.

The Plugin enriches Chat Completions, Responses API, Anthropic Messages, and Bedrock Converse requests using each protocol's native prompt structure. For Responses, it appends retrieved context to `input`. It leaves direct Embeddings API and passthrough requests unchanged. The nested `ai_rag.embeddings` object configures the embedding input used internally for retrieval and is distinct from a top-level Embeddings request.

See [request protocol detection](./ai-proxy.md#request-protocol-detection) for the detection order and URI requirements.

## Plugin Attributes

| Name | Type | Required | Default | Valid values | Description |
| --- | --- | --- | --- | --- | --- |
| `embeddings_provider` | object | True | | | Embedding model provider configurations. |
| `embeddings_provider.azure_openai` | object | True | | | [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) embedding model configurations. |
| `embeddings_provider.azure_openai.endpoint` | string | True | | | Azure OpenAI embedding model endpoint. |
| `embeddings_provider.azure_openai.api_key` | string | True | | | Azure OpenAI API key. |
| `vector_search_provider` | object | True | | | Vector search provider configurations. |
| `vector_search_provider.azure_ai_search` | object | False | | | Configurations of [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search). Configure exactly one of `azure_ai_search` and `qdrant`. |
| `vector_search_provider.azure_ai_search.endpoint` | string | True | | | Azure AI Search endpoint. |
| `vector_search_provider.azure_ai_search.api_key` | string | True | | | Azure AI Search API key. |
| `vector_search_provider.qdrant` | object | False | | | Configurations of [Qdrant](https://qdrant.tech/documentation/). Configure exactly one of `azure_ai_search` and `qdrant`. |
| `vector_search_provider.qdrant.endpoint` | string | True | | | URL of the Qdrant instance, such as `http://127.0.0.1:6333`. It can include a path prefix. The Plugin sends search requests to the [Query API](https://qdrant.tech/documentation/concepts/search/) at `{endpoint}/collections/{collection_name}/points/query`. |
| `vector_search_provider.qdrant.collection_name` | string | True | | | Name of the [collection](https://qdrant.tech/documentation/concepts/collections/) to search. |
| `vector_search_provider.qdrant.api_key` | string | False | | | Qdrant [API key](https://qdrant.tech/documentation/guides/security/). The Plugin sends it in the `api-key` header. Configure it when the Qdrant instance requires an API key. |

## Request Body Format

The following fields must be present in the request body.

| Field | Type | Description |
| --- | --- | --- |
| `ai_rag` | object | Request body RAG specifications. |
| `ai_rag.embeddings` | object | Request parameters required to generate embeddings. Contents will depend on the API specification of the configured provider. |
| `ai_rag.vector_search` | object | Request parameters required to perform vector search. Contents will depend on the API specification of the configured provider. |

- Parameters of `ai_rag.embeddings`

  - Azure OpenAI

  | Name | Required | Type | Description |
  | --- | --- | --- | --- |
  | `input` | True | string | Input text used to compute embeddings, encoded as a string. |
  | `user` | False | string | A unique identifier representing your end user, which can help in monitoring and detecting abuse. |
  | `encoding_format` | False | string | The format to return the embeddings in. Can be either `float` or `base64`. Defaults to `float`. |
  | `dimensions` | False | integer | The number of dimensions the resulting output embeddings should have. It should match the dimension of your embedding model. For instance, the dimensions for `text-embedding-ada-002` are fixed at 1536. For `text-embedding-3-small` or `text-embedding-3-large`, dimensions range from 1 to 1536 and 3072, respectively. |

  For other parameters please refer to the [Azure OpenAI embeddings documentation](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#embeddings).

- Parameters of `ai_rag.vector_search`

  - Azure AI Search

  | Field | Required | Type | Description |
  | --- | --- | --- | --- |
  | `fields` | True | string | Fields for the vector search. |

  For other parameters please refer to the [Azure AI Search documentation](https://learn.microsoft.com/en-us/rest/api/searchservice/documents/search-post). In addition, [these vector query parameters](https://learn.microsoft.com/en-us/rest/api/searchservice/documents/search-post?view=rest-searchservice-2024-07-01&tabs=HTTP#vectorizabletextquery) are also supported.

  - Qdrant

  All fields are optional. Send an empty `vector_search` object to use the Qdrant defaults. The Plugin rejects other fields with a `400` response.

  | Field | Required | Type | Description |
  | --- | --- | --- | --- |
  | `limit` | False | integer | Maximum number of points to return, from 1 to 100. Defaults to 10. |
  | `using` | False | string | Name of the vector to search, for a collection with [named vectors](https://qdrant.tech/documentation/concepts/vectors/#named-vectors). |
  | `filter` | False | object | [Filter](https://qdrant.tech/documentation/concepts/filtering/) conditions on the payload of the points. |
  | `params` | False | object | [Search parameters](https://qdrant.tech/documentation/concepts/search/#search-api), such as `hnsw_ef` and `exact`. |
  | `score_threshold` | False | number | Minimum score of a returned point. |
  | `with_payload` | False | array | Names of the [payload fields](https://qdrant.tech/documentation/concepts/search/#payload-and-vector-in-the-result) to return. Defaults to the full payload. |

  The Plugin adds the payloads of the matched points to the LLM request as a JSON array, such as `[{"text":"..."}]`. It skips points without a payload. When no point has a payload, the Plugin adds no message to the LLM request.

  When Qdrant rejects the query, for example because of an invalid `filter`, the Plugin returns a `400` response. When the Plugin cannot reach Qdrant, or Qdrant returns another error, the Plugin returns a `502` response. The Plugin writes the Qdrant error details to the APISIX error log, not to the response.

Example request body for Azure AI Search:

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

Example request body for Qdrant:

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

## Examples

To follow along the example, create an [Azure account](https://portal.azure.com) and complete the following steps:

* In [Azure AI Foundry](https://oai.azure.com/portal), deploy a generative chat model, such as `gpt-4o`, and an embedding model, such as `text-embedding-3-large`. Obtain the API key and model endpoints.
* Follow [Azure's example](https://github.com/Azure/azure-search-vector-samples/blob/main/demo-python/code/basic-vector-workflow/azure-search-vector-python-sample.ipynb) to prepare for a vector search in [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) using Python. The example will create a search index called `vectest` with the desired schema and upload the [sample data](https://github.com/Azure/azure-search-vector-samples/blob/main/data/text-sample.json) which contains 108 descriptions of various Azure services, for embeddings `titleVector` and `contentVector` to be generated based on `title` and `content`. Complete all the setups before performing vector searches in Python.
* In [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search), [obtain the Azure vector search API key and the search service endpoint](https://learn.microsoft.com/en-us/azure/search/search-get-started-vector?tabs=api-key#retrieve-resource-information).

Save the API keys and endpoints to environment variables:

```shell
# replace with your values

AZ_OPENAI_DOMAIN=https://your-openai-resource.openai.azure.com
AZ_OPENAI_API_KEY=your-azure-openai-api-key
AZ_CHAT_ENDPOINT=${AZ_OPENAI_DOMAIN}/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-15-preview
AZ_EMBEDDING_MODEL=text-embedding-3-large
AZ_EMBEDDINGS_ENDPOINT=${AZ_OPENAI_DOMAIN}/openai/deployments/${AZ_EMBEDDING_MODEL}/embeddings?api-version=2023-05-15

AZ_AI_SEARCH_SVC_DOMAIN=https://your-search-service.search.windows.net
AZ_AI_SEARCH_KEY=your-azure-ai-search-api-key
AZ_AI_SEARCH_INDEX=vectest
AZ_AI_SEARCH_ENDPOINT=${AZ_AI_SEARCH_SVC_DOMAIN}/indexes/${AZ_AI_SEARCH_INDEX}/docs/search?api-version=2024-07-01
```

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```shell
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Integrate with Azure for RAG-Enhanced Responses

The following example demonstrates how you can use the [`ai-proxy`](./ai-proxy.md) Plugin to proxy requests to Azure OpenAI LLM and use the `ai-rag` Plugin to generate embeddings and perform vector search to enhance LLM responses.

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route as such:

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

Create a Route with the `ai-rag` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

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

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
<TabItem value="ingress" label="Ingress Controller">

<Tabs groupId="k8s-api">
<TabItem value="gateway-api" label="Gateway API">

Create a Route with the `ai-rag` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

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
            api_key: "your-azure-openai-api-key"
        vector_search_provider:
          azure_ai_search:
            endpoint: "https://your-search-service.search.windows.net/indexes/vectest/docs/search?api-version=2024-07-01"
            api_key: "your-azure-ai-search-api-key"
    - name: ai-proxy
      config:
        provider: openai
        auth:
          header:
            api-key: "your-azure-openai-api-key"
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

Create a Route with the `ai-rag` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

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
                api_key: "your-azure-openai-api-key"
            vector_search_provider:
              azure_ai_search:
                endpoint: "https://your-search-service.search.windows.net/indexes/vectest/docs/search?api-version=2024-07-01"
                api_key: "your-azure-ai-search-api-key"
        - name: ai-proxy
          enable: true
          config:
            provider: openai
            auth:
              header:
                api-key: "your-azure-openai-api-key"
            options:
              model: gpt-4o
            override:
              endpoint: "https://your-openai-resource.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-15-preview"
```

</TabItem>
</Tabs>

Apply the configuration to your cluster:

```shell
kubectl apply -f ai-rag-ic.yaml
```

</TabItem>
</Tabs>

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

### Integrate with Qdrant for RAG-Enhanced Responses

The following example uses [Qdrant](https://qdrant.tech/documentation/) for vector search. It uses Azure OpenAI for embeddings and for the chat model, as in the previous example.

Complete the following steps before you create the Route:

* Start a Qdrant instance. For a local instance, run `docker run -p 6333:6333 qdrant/qdrant`. For a managed instance, create a cluster in [Qdrant Cloud](https://cloud.qdrant.io) and obtain its URL and API key.
* [Create a collection](https://qdrant.tech/documentation/concepts/collections/#create-a-collection) and [upload points](https://qdrant.tech/documentation/concepts/points/#upload-points). Generate the vectors with the same embedding model that the Plugin uses, and set the vector size of the collection to the dimensions of that model. Store the text of each document in the payload, such as in a `text` field.

Save the Qdrant settings to environment variables:

```shell
# replace with your values

QDRANT_URL=http://127.0.0.1:6333
QDRANT_API_KEY=your-qdrant-api-key
QDRANT_COLLECTION=azure-services
```

<Tabs groupId="api">
<TabItem value="admin-api" label="Admin API">

Create a Route as such:

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

Create a Route with the `ai-rag` and [`ai-proxy`](./ai-proxy.md) Plugins configured as such:

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

Synchronize the configuration to the gateway:

```shell
adc sync -f adc.yaml
```

</TabItem>
</Tabs>

Send a POST request to the Route with the search parameters and an input prompt in the request body:

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

The Plugin finds the three nearest points in the collection and adds their `text` payload fields to the LLM request. You should receive an `HTTP/1.1 200 OK` response with an answer from the model that uses the retrieved text.
