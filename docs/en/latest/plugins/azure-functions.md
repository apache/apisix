---
title: azure-functions
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Azure Functions
  - azure-functions
description: This document contains information about the Apache APISIX azure-functions Plugin.
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

The `azure-functions` Plugin is used to integrate APISIX with [Azure Serverless Function](https://azure.microsoft.com/en-in/services/functions/) as a dynamic upstream to proxy all requests for a particular URI to the Microsoft Azure Cloud.

When enabled, the Plugin terminates the ongoing request to the configured URI and initiates a new request to Azure Functions on behalf of the client with configured authorization details, request headers, body and parameters (all three passed from the original request). It returns back the response with headers, status code and the body to the client that initiated the request with APISIX.

## Attributes

| Name                   | Type    | Required | Default | Valid values | Description                                                                                                                           |
|------------------------|---------|----------|---------|--------------|---------------------------------------------------------------------------------------------------------------------------------------|
| function_uri           | string  | True     |         |              | Azure FunctionS endpoint which triggers the serverless function. For example, `http://test-apisix.azurewebsites.net/api/HttpTrigger`. |
| authorization          | object  | False    |         |              | Authorization credentials to access Azure Functions.                                                                                  |
| authorization.apikey   | string  | False    |         |              | Generated API key to authorize requests.                                                                                              |
| authorization.clientid | string  | False    |         |              | Azure AD client ID to authorize requests.                                                                                             |
| timeout                | integer | False    | 3000    | [100,...]    | Proxy request timeout in milliseconds.                                                                                                |
| ssl_verify             | boolean | False    | true    | true/false   | When set to `true` performs SSL verification.                                                                                         |
| keepalive              | boolean | False    | true    | true/false   | When set to `true` keeps the connection alive for reuse.                                                                              |
| keepalive_pool         | integer | False    | 5       | [1,...]      | Maximum number of requests that can be sent on this connection before closing it.                                                     |
| keepalive_timeout      | integer | False    | 60000   | [1000,...]   | Time is ms for connection to remain idle without closing.                                                                             |

## Metadata

| Name            | Type   | Required | Default | Description                                                          |
|-----------------|--------|----------|---------|----------------------------------------------------------------------|
| master_apikey   | string | False    | ""      | API Key secret that could be used to access the Azure Functions URI. |
| master_clientid | string | False    | ""      | Azure AD client ID that could be used to authorize the function URI. |

Metadata can be used in the `azure-functions` Plugin for an authorization fallback. If there are no authorization details in the Plugin's attributes, the `master_apikey` and `master_clientid` configured in the metadata is used.

The relative order priority is as follows:

1. Plugin looks for `x-functions-key` or `x-functions-clientid` key inside the header from the request to APISIX.
2. If not found, the Plugin checks the configured attributes for authorization details. If present, it adds the respective header to the request sent to the Azure Functions.
3. If authorization details are not configured in the Plugin's attributes, APISIX fetches the metadata and uses the master keys.

To add a new master API key, you can make a request to `/apisix/admin/plugin_metadata` with the required metadata as shown below:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/azure-functions -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "master_apikey" : "<Your Azure master access key>"
}'
```

## Enable Plugin

You can configure the Plugin on a specific Route as shown below assuming that you already have your Azure Functions up and running:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "azure-functions": {
            "function_uri": "http://test-apisix.azurewebsites.net/api/HttpTrigger",
            "authorization": {
                "apikey": "<Generated API key to access the Azure-Function>"
            }
        }
    },
    "uri": "/azure"
}'
```

Now, any requests (HTTP/1.1, HTTPS, HTTP2) to the endpoint `/azure` will invoke the configured Azure Functions URI and the response will be proxied back to the client.

In the example below, the Azure Function takes in name from the query and returns a message "Hello $name":

```shell
curl -i -XGET http://localhost:9080/azure\?name=APISIX
```

```shell
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Request-Context: appId=cid-v1:38aae829-293b-43c2-82c6-fa94aec0a071
Date: Wed, 17 Nov 2021 14:46:55 GMT
Server: APISIX/2.10.2

Hello, APISIX
```

Another example of a request where the client communicates with APISIX via HTTP/2 is shown below. Before proceeding, make sure you have configured `enable_http2: true` in your configuration file `config.yaml` for port `9081` and reloaded APISIX. See [`config.yaml.example`](https://github.com/apache/apisix/blob/master/conf/config.yaml.example) for the example configuration.

```shell
curl -i -XGET --http2 --http2-prior-knowledge http://localhost:9081/azure\?name=APISIX
```

```shell
HTTP/2 200
content-type: text/plain; charset=utf-8
request-context: appId=cid-v1:38aae829-293b-43c2-82c6-fa94aec0a071
date: Wed, 17 Nov 2021 14:54:07 GMT
server: APISIX/2.10.2

Hello, APISIX
```

### Configuring path forwarding

The `azure-functions` Plugins also supports URL path forwarding while proxying requests to the Azure Functions upstream. Extensions to the base request path gets appended to the `function_uri` specified in the Plugin configuration.

:::info IMPORTANT

The `uri` configured on a Route must end with `*` for this feature to work properly. APISIX Routes are matched strictly and the `*` implies that any subpath to this URI would be matched to the same Route.

:::

The example below configures this feature:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "azure-functions": {
            "function_uri": "http://app-bisakh.azurewebsites.net/api",
            "authorization": {
                "apikey": "<Generated API key to access the Azure-Function>"
            }
        }
    },
    "uri": "/azure/*"
}'
```

Now, any requests to the path `azure/HttpTrigger1` will invoke the Azure Function and the added path is forwarded:

```shell
curl -i -XGET http://127.0.0.1:9080/azure/HttpTrigger1\?name\=APISIX\
```

```shell
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 01 Dec 2021 14:19:53 GMT
Request-Context: appId=cid-v1:4d4b6221-07f1-4e1a-9ea0-b86a5d533a94
Server: APISIX/2.11.0

Hello, APISIX
```

## Delete Plugin

To remove the `azure-functions` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/azure",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
