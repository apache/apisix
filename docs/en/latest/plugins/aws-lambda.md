---
title: aws-lambda
keywords:
  - Apache APISIX
  - Plugin
  - AWS Lambda
  - aws-lambda
description: This document contains information about the Apache APISIX aws-lambda Plugin.
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

The `aws-lambda` Plugin is used for integrating APISIX with [AWS Lambda](https://aws.amazon.com/lambda/) and [Amazon API Gateway](https://aws.amazon.com/api-gateway/) as a dynamic upstream to proxy all requests for a particular URI to the AWS Cloud.

When enabled, the Plugin terminates the ongoing request to the configured URI and initiates a new request to the AWS Lambda Gateway URI on behalf of the client with configured authorization details, request headers, body and parameters (all three passed from the original request). It returns the response with headers, status code and the body to the client that initiated the request with APISIX.

This Plugin supports authorization via AWS API key and AWS IAM secrets. The Plugin implements [AWS Signature Version 4 signing](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_aws-signing.html) for IAM secrets.

## Attributes

| Name                 | Type    | Required | Default | Valid values | Description                                                                                                                                |
|----------------------|---------|----------|---------|--------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| function_uri         | string  | True     |         |              | AWS API Gateway endpoint which triggers the lambda serverless function.                                                                    |
| authorization        | object  | False    |         |              | Authorization credentials to access the cloud function.                                                                                    |
| authorization.apikey | string  | False    |         |              | Generated API Key to authorize requests to the AWS Gateway endpoint.                                                                       |
| authorization.iam    | object  | False    |         |              | Used for AWS IAM role based authorization performed via AWS v4 request signing. See [IAM authorization schema](#iam-authorization-schema). |
| authorization.iam.accesskey  | string | True     |               | Generated access key ID from AWS IAM console.                                       |
| authorization.iam.secretkey | string | True     |               | Generated access key secret from AWS IAM console.                                   |
| authorization.iam.aws_region | string | False    | "us-east-1"   | AWS region where the request is being sent.                                         |
| authorization.iam.service    | string | False    | "execute-api" | The service that is receiving the request. For Amazon API gateway APIs, it should be set to `execute-api`. For Lambda function, it should be set to `lambda`. |
| timeout              | integer | False    | 3000    | [100,...]    | Proxy request timeout in milliseconds.                                                                                                     |
| ssl_verify           | boolean | False    | true    | true/false   | When set to `true` performs SSL verification.                                                                                              |
| keepalive            | boolean | False    | true    | true/false   | When set to `true` keeps the connection alive for reuse.                                                                                   |
| keepalive_pool       | integer | False    | 5       | [1,...]      | Maximum number of requests that can be sent on this connection before closing it.                                                          |
| keepalive_timeout    | integer | False    | 60000   | [1000,...]   | Time is ms for connection to remain idle without closing.                                                          |

## Enable Plugin

The example below shows how you can configure the Plugin on a specific Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "aws-lambda": {
            "function_uri": "https://x9w6z07gb9.execute-api.us-east-1.amazonaws.com/default/test-apisix",
            "authorization": {
                "apikey": "<Generated API Key from aws console>"
            },
            "ssl_verify":false
        }
    },
    "uri": "/aws"
}'
```

Now, any requests (HTTP/1.1, HTTPS, HTTP2) to the endpoint `/aws` will invoke the configured AWS Functions URI and the response will be proxied back to the client.

In the example below, AWS Lambda takes in name from the query and returns a message "Hello $name":

```shell
curl -i -XGET localhost:9080/aws\?name=APISIX
```

```shell
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

Another example of a request where the client communicates with APISIX via HTTP/2 is shown below. Before proceeding, make sure you have configured `enable_http2: true` in your configuration file `config.yaml` for port `9081` and reloaded APISIX. See [`config.yaml.example`](https://github.com/apache/apisix/blob/master/conf/config.yaml.example) for the example configuration.

```shell
curl -i -XGET --http2 --http2-prior-knowledge localhost:9081/aws\?name=APISIX
```

```shell
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

Similarly, the function can be triggered via AWS API Gateway by using AWS IAM permissions for authorization. The Plugin includes authentication signatures in HTTP calls via AWS v4 request signing. The example below shows this method:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

:::note

This approach assumes that you have already an IAM user with programmatic access enabled with the required permissions (`AmazonAPIGatewayInvokeFullAccess`) to access the endpoint.

:::

### Configuring path forwarding

The `aws-lambda` Plugin also supports URL path forwarding while proxying requests to the AWS upstream. Extensions to the base request path gets appended to the `function_uri` specified in the Plugin configuration.

:::info IMPORTANT

The `uri` configured on a Route must end with `*` for this feature to work properly. APISIX Routes are matched strictly and the `*` implies that any subpath to this URI would be matched to the same Route.

:::

The example below configures this feature:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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

Now, any requests to the path `aws/default/test-apisix` will invoke the AWS Lambda Function and the added path is forwarded:

```shell
curl -i -XGET http://127.0.0.1:9080/aws/default/test-apisix\?name\=APISIX
```

```shell
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

## Delete Plugin

To remove the `aws-lambda` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
