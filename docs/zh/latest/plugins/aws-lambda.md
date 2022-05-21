---
title: aws-lambda
keywords:
  - APISIX
  - Plugin
  - AWS Lambda
  - aws-lambda
description: 本文介绍了关于 Apache APISIX aws-lambda 插件的基本信息。
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

## 描述

`aws-lambda` 插件用于将 [AWS Lambda](https://aws.amazon.com/lambda/) 作为动态上游集成至 `APISIX` ，将所有特定 `URI` 的请求代理到 `AWS` 云。

插件启用后会终止对已配置 `URI` 的请求，并代表客户端向 `AWS Lambda Gateway URI` 发起一个新的请求，其中包括配置的授权详细信息、请求头、正文（三个参数都是从原始请求中传递的）。然后将带有头信息、状态代码和正文的响应返回给使用 `APISIX` 发起请求的客户端。

本插件支持通过 `AWS API key` 和 `AWS IAM secrets` 进行授权。

## 属性

| Name                 | Type    | Required | Default | Valid values | Description                                                  |
| -------------------- | ------- | -------- | ------- | ------------ | ------------------------------------------------------------ |
| function_uri         | string  | 是       |         |              | 触发 `lambda` 无服务器函数的 `AWS API Gateway` 端点。        |
| authorization        | object  | 否       |         |              | 访问云函数的授权凭证。                                       |
| authorization.apikey | string  | 否       |         |              | 生成的 `API` 密钥，用于授权对 `AWS` 网关端点的请求。         |
| authorization.iam    | object  | 否       |         |              | 用于通过 `AWS v4` 请求签名执行的基于 AWS IAM 角色的授权。 请参阅 [IAM 授权方案](#IAM授权方案)。 |
| timeout              | integer | 否       | 3000    | [100,...]    | 代理请求超时，以毫秒为单位。                                 |
| ssl_verify           | boolean | 否       | true    | true/false   | 当设置为 `true` 时执行 `SSL` 验证。                          |
| keepalive            | boolean | 否       | true    | true/false   | 当设置为 `true` 时，保持连接的活动状态以便重复使用。         |
| keepalive_pool       | integer | 否       | 5       | [1,...]      | 在关闭该连接之前，可以在该连接上发送的最大请求数。           |
| keepalive_timeout    | integer | 否       | 60000   | [1000,...]   | 在关闭该连接之前，可以在该连接上发送的最大请求数。           |

### IAM 授权方案

| Name       | Type   | Required | Default       | Description                                                  |
| ---------- | ------ | -------- | ------------- | ------------------------------------------------------------ |
| accesskey  | string | 是       |               | 从 `AWS IAM` 控制台生成的访问密钥 `ID`。                     |
| secret_key | string | 是       |               | 从 `AWS IAM` 控制台生成的访问密钥。                          |
| aws_region | string | 否       | "us-east-1"   | 请求被发送的 `AWS` 区域。                                    |
| service    | string | 否       | "execute-api" | 接收该请求的服务。对于 `HTTP` 触发器，它是 `"execute-api"`。 |

## 启用插件

下面的例子向你演示了如何在一个特定的路由上配置该插件：

```shell
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

现在，任何对端点 `/aws` 的请求（`HTTP/1.1、HTTPS、HTTP2`）都将调用已配置的 `AWS` 函数的 `URI`，并且响应将被代理回给客户端。

下面的例子中，`AWS Lambda` 从查询中接收名字，并返回一条 `"Hello $name"` 消息。

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
...
"Hello, APISIX!"
```

另一个请求的例子是，客户端通过 `HTTP/2` 与 `APISIX` 进行通信，如下所示（请确保你在默认配置文件（`config-default.yaml`）中配置了 `enable_http2: true`。你可以通过取消对 `apisix.node_listen`  字段中端口`9081`的注释来做到这一点）：

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
...
"Hello, APISIX!"
```

同样，该函数也可以通过 `AWS API Gateway` 使用 `AWS IAM` 权限进行授权而触发。该插件通过 `AWS v4` 请求签名在 `HTTP` 调用中包含了身份验证签名。下面的例子显示了此方法。

```shell
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

:::注意

这种方法假设你已经有一个 `IAM` 用户，并启用了程序化访问所需要的权限（`AmazonAPIGatewayInvokeFullAccess`）来访问端点。

:::

### 配置路由转发

`aws-lambda` 插件在代理请求到 `AWS` 上游的时候也支持 `URL` 路径转发。基本请求路径的扩展被附加到插件配置中指定的 `function_uri` 上。

:::重要信息

在路由上配置的 `uri`  必须以 `*` 结尾，这样才能正常工作。`APISIX` 路由是严格匹配的，`*` 意味着这个 `URI` 的任何子路径都会被匹配到同一个路由。

:::

下面的例子配置了这一功能：

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

现在，任何对 `aws/default/test-apisix` 路径的请求都会调用 `AWS Lambda` 函数，并转发添加的路径。

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
...
"Hello, APISIX!"
```

## 禁用插件

要禁用`aws-lambda`插件，你可以从插件配置中删除相应的 `JSON` 配置。你不需要重新启动就可以生效，因为 `APISIX` 将自动重新加载配置。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
