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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Description

The `ai-rag` Plugin provides Retrieval-Augmented Generation (RAG) capabilities with LLMs. It facilitates the efficient retrieval of relevant documents or information from external data sources, which are used to enhance the LLM responses, thereby improving the accuracy and contextual relevance of the generated outputs.

The Plugin supports using [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) and [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search) services for generating embeddings and performing vector search. PRs for introducing support for other service providers are welcomed.

## Plugin Attributes

| Name | Type | Required | Default | Valid values | Description |
| --- | --- | --- | --- | --- | --- |
| `embeddings_provider` | object | True | | | Embedding model provider configurations. |
| `embeddings_provider.azure_openai` | object | True | | | [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) embedding model configurations. |
| `embeddings_provider.azure_openai.endpoint` | string | True | | | Azure OpenAI embedding model endpoint. |
| `embeddings_provider.azure_openai.api_key` | string | True | | | Azure OpenAI API key. |
| `vector_search_provider` | object | True | | | Vector search provider configurations. |
| `vector_search_provider.azure_ai_search` | object | True | | | Configurations of [Azure AI Search](https://azure.microsoft.com/en-us/products/ai-services/ai-search). |
| `vector_search_provider.azure_ai_search.endpoint` | string | True | | | Azure AI Search endpoint. |
| `vector_search_provider.azure_ai_search.api_key` | string | True | | | Azure AI Search API key. Supports [secret references](../terminology/secret.md) via environment variables (e.g. `$ENV://AI_RAG_APIKEY`) and secret managers. |

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

## Examples

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

## Secret References

The `api_key` fields support APISIX secret resolution, via environment variable and secret manager. For secret reference formats and setup, see [APISIX Secret](../terminology/secret.md). Example:

```json
{
  "embeddings_provider": {
    "azure_openai": {
      "endpoint": "'"$AZ_EMBEDDINGS_ENDPOINT"'",
      "api_key": "$ENV://AI_RAG_APIKEY"
    }
  },
  "vector_search_provider": {
    "azure_ai_search": {
      "endpoint": "'"$AZ_AI_SEARCH_ENDPOINT"'",
      "api_key": "$ENV://AI_RAG_APIKEY"
    }
  }
}
```
