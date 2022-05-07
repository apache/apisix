---
title: azure-functions
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

`azure-functions` is a serverless plugin built into Apache APISIX for seamless integration with [Azure Serverless Function](https://azure.microsoft.com/en-in/services/functions/) as a dynamic upstream to proxy all requests for a particular URI to the Microsoft Azure cloud, one of the most used public cloud platforms for production environment. If enabled, this plugin terminates the ongoing request to that particular URI and initiates a new request to the azure faas (the new upstream) on behalf of the client with the suitable authorization details set by the users, request headers, request body, params ( all these three components are passed from the original request ) and returns the response body, status code and the headers back to the original client that has invoked the request to the APISIX agent.

## Attributes

| Name             | Type   | Requirement  | Default      | Valid       | Description                                                                                |
| -----------      | ------ | -----------  | -------      | -----       | ------------------------------------------------------------                               |
| function_uri      | string | required    |          |   | The azure function endpoint which triggers the serverless function code (eg. http://test-apisix.azurewebsites.net/api/HttpTrigger).   |
| authorization   | object | optional    |         |     |  Authorization credentials to access the cloud function.                                                             |
| authorization.apikey | string | optional    |             |     | Field inside _authorization_. The generate API Key to authorize requests to that endpoint. |                         |
| authorization.clientid | string | optional    |             |     | Field inside _authorization_. The Client ID ( azure active directory ) to authorize requests to that endpoint. |                         |
| timeout  | integer | optional    | 3000           | [100,...]     | Proxy request timeout in milliseconds.   |
| ssl_verify  | boolean | optional    | true           | true/false     | If enabled performs SSL verification of the server.                     |
| keepalive  | boolean | optional    | true           | true/false     | To reuse the same proxy connection in near future. Set to false to disable keepalives and immediately close the connection.                    |
| keepalive_pool  | integer | optional    | 5          | [1,...]     | The maximum number of connections in the pool.              |
| keepalive_timeout  | integer | optional    | 60000           | [1000,...]     |  The maximal idle timeout (ms).                     |

## Metadata

| Name                  | Type    | Requirement |     Default     | Valid         | Description                                                            |
| -----------           | ------  | ----------- |      -------    | -----         | ---------------------------------------------------------------------- |
| master_apikey         | string  | optional    |  ""             |               | The API KEY secret that could be used to access the azure function uri.                                     |
| master_clientid       | string  | optional    |   ""            |               | The Client ID (active directory) that could be used the authorize the function uri                                         |

Metadata for `azure-functions` plugin provides the functionality for authorization fallback. It defines `master_apikey` and `master_clientid` (azure active directory client id) where users (optionally) can define the master API key or Client ID for mission-critical application deployment. So if there are no authorization details found inside the plugin attribute the authorization details present in the metadata kicks in.

The relative priority ordering is as follows:

- First, the plugin looks for `x-functions-key` or `x-functions-clientid` keys inside the request header to the APISIX agent.
- If they are not found, the azure-functions plugin checks for the authorization details inside plugin attributes. If present, it adds the respective header to the request sent to the Azure cloud function.
- If no authorization details are found inside plugin attributes, APISIX fetches the metadata config for this plugin and uses the master keys.

To add a new Master APIKEY, make a request to _/apisix/admin/plugin_metadata_ endpoint with the updated metadata as follows:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/azure-functions -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "master_apikey" : "<Your azure master access key>"
}'
```

## How To Enable

The following is an example of how to enable the azure-function faas plugin for a specific APISIX route URI. We are assuming your cloud function is already up and running.

```shell
# enable azure function for a route
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Now any requests (HTTP/1.1, HTTPS, HTTP2) to URI `/azure` will trigger an HTTP invocation to the aforesaid function URI and response body along with the response headers and response code will be proxied back to the client. For example ( here azure cloud function just take the `name` query param and returns `Hello $name` ) :

```shell
$ curl -i -XGET http://localhost:9080/azure\?name=APISIX
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Request-Context: appId=cid-v1:38aae829-293b-43c2-82c6-fa94aec0a071
Date: Wed, 17 Nov 2021 14:46:55 GMT
Server: APISIX/2.10.2

Hello, APISIX
```

For requests where the mode of communication between the client and the Apache APISIX gateway is HTTP/2, the example looks like ( make sure you are running APISIX agent with `enable_http2: true` for a port in `config-default.yaml`. You can do it by uncommenting the port 9081 from `apisix.node_listen` field ) :

```shell
$ curl -i -XGET --http2 --http2-prior-knowledge http://localhost:9081/azure\?name=APISIX
HTTP/2 200
content-type: text/plain; charset=utf-8
request-context: appId=cid-v1:38aae829-293b-43c2-82c6-fa94aec0a071
date: Wed, 17 Nov 2021 14:54:07 GMT
server: APISIX/2.10.2

Hello, APISIX
```

### Plugin with Path Forwarding

Azure Faas plugin supports url path forwarding while proxying request to the modified upstream. With that being said, any extension to the path of the base request APISIX gateway URI gets "appended" (path join) to the `function_uri` specified in the plugin configuration.

**Note**: APISIX route uri must be ended with an asterisk (`*`) for this feature to work properly. APISIX routes are strictly matched and the extra asterisk at the suffix means any subpath appended to the original parent path will use the same route object configurations.

Here is an example:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Now any request with path `azure/HttpTrigger1` will invoke the azure function. Here the extra path (where the magic character `*` has been used) up to the query params have been forwarded.

```shell
curl -i -XGET http://127.0.0.1:9080/azure/HttpTrigger1\?name\=APISIX
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Date: Wed, 01 Dec 2021 14:19:53 GMT
Request-Context: appId=cid-v1:4d4b6221-07f1-4e1a-9ea0-b86a5d533a94
Server: APISIX/2.11.0

Hello, APISIX
```

## Disable Plugin

Remove the corresponding JSON configuration in the plugin configuration to disable the `azure-functions` plugin and add the suitable upstream configuration.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
