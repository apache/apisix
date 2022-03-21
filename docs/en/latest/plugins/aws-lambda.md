---
title: aws-lambda
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

`aws-lambda` is a serverless plugin built into Apache APISIX for seamless integration with [AWS Lambda](https://aws.amazon.com/lambda/), a widely used serverless solution, as a dynamic upstream to proxy all requests for a particular URI to the AWS cloud - one of the highly used public cloud platforms for production environment. If enabled, this plugin terminates the ongoing request to that particular URI and initiates a new request to the AWS lambda gateway uri (the new upstream) on behalf of the client with the suitable authorization details set by the users, request headers, request body, params (all these three components are passed from the original request) and returns the response body, status code and the headers back to the original client that has invoked the request to the APISIX agent.
At present, the plugin supports authorization via AWS api key and AWS IAM Secrets.

## Attributes

| Name             | Type   | Requirement  | Default      | Valid       | Description                                                                                |
| -----------      | ------ | -----------  | -------      | -----       | ------------------------------------------------------------                               |
| function_uri      | string | required    |          |   | The AWS api gateway endpoint which triggers the lambda serverless function code.   |
| authorization   | object | optional    |         |     |  Authorization credentials to access the cloud function.                                                             |
| authorization.apikey | string | optional    |             |     | Field inside _authorization_. The generate API Key to authorize requests to that endpoint of the AWS gateway. |                         |
| authorization.iam | object | optional    |             |     | Field inside _authorization_. AWS IAM role based authorization, performed via AWS v4 request signing. See schema details below ([here](#iam-authorization-schema)). |                         |
| timeout  | integer | optional    | 3000           | [100,...]     | Proxy request timeout in milliseconds.   |
| ssl_verify  | boolean | optional    | true           | true/false     | If enabled performs SSL verification of the server.                     |
| keepalive  | boolean | optional    | true           | true/false     | To reuse the same proxy connection in near future. Set to false to disable keepalives and immediately close the connection.                    |
| keepalive_pool  | integer | optional    | 5          | [1,...]     | The maximum number of connections in the pool.              |
| keepalive_timeout  | integer | optional    | 60000           | [1000,...]     |  The maximal idle timeout (ms).                     |

### IAM Authorization Schema

| Name             | Type   | Requirement  | Default        | Valid       | Description                                                                                |
| -----------      | ------ | -----------  | -------        | -----       | ------------------------------------------------------------                               |
| accesskey        | string | required     |                |             | Generated access key ID from AWS IAM console.                                            |
| secret_key       | string | required     |                |             | Generated access key secret from AWS IAM console.                                         |
| aws_region       | string | optional     | "us-east-1"    |             | The AWS region where the request is being sent.                                            |
| service          | string | optional     | "execute-api"  |             | The service that is receiving the request (In case of Http Trigger it is "execute-api").   |

## How To Enable

The following is an example of how to enable the aws-lambda faas plugin for a specific route URI. Calling the APISIX route uri will make an invocation to the lambda function uri (the new upstream). We are assuming your cloud function is already up and running.

```shell
# enable aws lambda for a route via api key authorization
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "aws-lambda": {
            "function_uri": "https://x9w6z07gb9.execute-api.us-east-1.amazonaws.com/default/test-apisix",
            "authorization": {
                "apikey": "<Generated API Key from aws console>",
            },
            "ssl_verify":false
        }
    },
    "uri": "/aws"
}'
```

Now any requests (HTTP/1.1, HTTPS, HTTP2) to URI `/aws` will trigger an HTTP invocation to the aforesaid function URI and response body along with the response headers and response code will be proxied back to the client. For example (here AWS lambda function just take the `name` query param and returns `Hello $name`) :

```shell
$ curl -i -XGET localhost:9080/aws\?name=APISIX
HTTP/1.1 200 OK
Content-Type: application/json
Connection: keep-alive
Date: Sat, 27 Nov 2021 13:08:27 GMT
x-amz-apigw-id: JdwXuEVxIAMFtKw=
x-amzn-RequestId: 471289ab-d3b7-4819-9e1a-cb59cac611e0
Content-Length: 16
X-Amzn-Trace-Id: Root=1-61a22dca-600c552d1c05fec747fd6db0;Sampled=0
Server: APISIX/2.10.2

"Hello, APISIX!"
```

For requests where the mode of communication between the client and the Apache APISIX gateway is HTTP/2, the example looks like ( make sure you are running APISIX agent with `enable_http2: true` for a port in `config-default.yaml`. You can do it by uncommenting the port 9081 from `apisix.node_listen` field ) :

```shell
$ curl -i -XGET --http2 --http2-prior-knowledge localhost:9081/aws\?name=APISIX
HTTP/2 200
content-type: application/json
content-length: 16
x-amz-apigw-id: JdwulHHrIAMFoFg=
date: Sat, 27 Nov 2021 13:10:53 GMT
x-amzn-trace-id: Root=1-61a22e5d-342eb64077dc9877644860dd;Sampled=0
x-amzn-requestid: a2c2b799-ecc6-44ec-b586-38c0e3b11fe4
server: APISIX/2.10.2

"Hello, APISIX!"
```

Similarly, the lambda can be triggered via AWS API Gateway by using AWS `IAM` permissions to authorize access to your API via APISIX aws-lambda plugin. Plugin includes authentication signatures in their HTTP calls via AWS v4 request signing. Here is an example:

```shell
# enable aws lambda for a route via iam authorization
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "aws-lambda": {
            "function_uri": "https://ajycz5e0v9.execute-api.us-east-1.amazonaws.com/default/test-apisix",
            "authorization": {
                "iam": {
                    "accesskey": "<access key>",
                    "secretkey": "<access key secret>"
                }
            },
            "ssl_verify": false
        }
    },
    "uri": "/aws"
}'
```

**Note**: This approach assumes you already have an iam user with the programmatic access enabled and required permissions (`AmazonAPIGatewayInvokeFullAccess`) to access the endpoint.

### Plugin with Path Forwarding

AWS Lambda plugin supports url path forwarding while proxying request to the modified upstream (AWS Gateway URI endpoint). With that being said, any extension to the path of the base request APISIX gateway URI gets "appended" (path join) to the `function_uri` specified in the plugin configuration.

**Note**: APISIX route uri must be ended with an asterisk (`*`) for this feature to work properly. APISIX routes are strictly matched and the extra asterisk at the suffix means any subpath appended to the original parent path will use the same route object configurations.

Here is an example:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "aws-lambda": {
            "function_uri": "https://x9w6z07gb9.execute-api.us-east-1.amazonaws.com",
            "authorization": {
                "apikey": "<Generate API key>"
            },
            "ssl_verify":false
        }
    },
    "uri": "/aws/*"
}'
```

Now any request with path `aws/default/test-apisix` will invoke the aws api gateway endpoint. Here the extra path (where the magic character `*` has been used) up to the query params have been forwarded.

```shell
curl -i -XGET http://127.0.0.1:9080/aws/default/test-apisix\?name\=APISIX
HTTP/1.1 200 OK
Content-Type: application/json
Connection: keep-alive
Date: Wed, 01 Dec 2021 14:23:27 GMT
X-Amzn-Trace-Id: Root=1-61a7855f-0addc03e0cf54ddc683de505;Sampled=0
x-amzn-RequestId: f5f4e197-9cdd-49f9-9b41-48f0d269885b
Content-Length: 16
x-amz-apigw-id: JrHG8GC4IAMFaGA=
Server: APISIX/2.11.0

"Hello, APISIX!"
```

## Disable Plugin

Remove the corresponding JSON configuration in the plugin configuration to disable the `aws-lambda` plugin and add the suitable upstream configuration.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/aws",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
