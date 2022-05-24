---
title: aws-lambda
keywords:
  - APISIX
  - Plugin
  - AWS Lambda
  - aws-lambda
description: 本文介绍了关于 Apache APISIX `aws-lambda` 插件的基本信息及使用方法。
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

`aws-lambda` 插件用于将 [AWS Lambda](https://aws.amazon.com/lambda/) 作为动态上游集成至 APISIX，从而实现将对某一特定 URI 的所有请求代理到 AWS 云。

`aws-lambda` 插件启用后会终止对已配置 URI 的请求，并代表客户端向 AWS Lambda Gateway URI 发起一个新的请求。这个新请求中包括配置的授权详细信息、请求头、请求体和参数（三个参数都是从原始请求中传递的）。然后插件会将带有响应头、状态码和响应体的响应返回给使用 APISIX 发起请求的客户端。

本插件支持通过 AWS API key 和 AWS IAM secrets 进行授权。

## 属性

| 名称                   | 类型     | 必选项 | 默认值  | 有效值       | 描述                                                 |
| ------------------- | ------- | ------ | ------- | ------------ | ------------------------------------------------------------ |
| function_uri         | string  | 是       |         |              | 触发 lambda serverless 函数的 AWS API Gateway 端点。        |
| authorization        | object  | 否       |         |              | 访问云函数的授权凭证。                                       |
| authorization.apikey | string  | 否       |         |              | 生成的 API 密钥，用于授权对 AWS Gateway 端点的请求。         |
| authorization.iam    | object  | 否       |         |              | 用于通过 AWS v4 请求签名执行的基于 AWS IAM 角色的授权。 请参阅 [IAM 授权方案](#IAM授权方案)。 |
| timeout              | integer | 否       | 3000    | [100,...]    | 代理请求超时（以毫秒为单位）。                                 |
| ssl_verify           | boolean | 否       | true    | true/false   | 当设置为 `true` 时执行 SSL 验证。                          |
| keepalive            | boolean | 否       | true    | true/false   | 当设置为 `true` 时，保持连接的活动状态以便重复使用。         |
| keepalive_pool       | integer | 否       | 5       | [1,...]      | 在关闭该连接之前，可以在该连接上发送的最大请求数。           |
| keepalive_timeout    | integer | 否       | 60000   | [1000,...]   | 在关闭该连接之前，可以在该连接上发送的最大请求数。           |

### IAM 授权方案

| 名称       | 类型    | 必选项   | 默认值         | 描述                                                  |
| ---------- | ------ | -------- | ------------- | ------------------------------------------------------------ |
| accesskey  | string | 是       |               | 从 AWS IAM 控制台生成的访问密钥 ID。                     |
| secret_key | string | 是       |               | 从 AWS IAM 控制台生成的访问密钥。                          |
| aws_region | string | 否       | "us-east-1"   | 发出请求的 AWS 区域。                                    |
| service    | string | 否       | "execute-api" | 接收该请求的服务。特别的，对于 HTTP 触发器是 `"execute-api"`。 |

## 启用插件

以下示例展示了如何在一个特定的路由上配置 `aws-lambda` 插件：

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

通过上述示例配置插件后，任何对端点 `/aws` 的请求（`HTTP/1.1`、`HTTPS`、`HTTP2`）都将调用已配置的 AWS 函数的 URI，响应进而被代理回客户端。

下面的例子中，AWS Lambda 从查询中接收 `name` 参数，并返回一条 `"Hello $name"` 消息：

```shell
curl -i -XGET localhost:9080/aws\?name=APISIX
```

预期的返回结果：

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

下面是另一个请求的例子，客户端通过 HTTP/2 协议与 APISIX 进行通信。

在进行测试之前，请确保默认配置文件（`config-default.yaml`）中配置了 `enable_http2: true`。你可以通过取消对 `apisix.node_listen` 字段中端口 `9081` 的注释来配置此项。

使用 `curl` 命令测试：

```shell
curl -i -XGET --http2 --http2-prior-knowledge localhost:9081/aws\?name=APISIX
```

预期的返回结果：

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

与上面的示例类似，AWS Lambda 函数也可以通过 AWS API Gateway 触发，但需要使用 AWS IAM 权限进行授权。`aws-lambda` 插件的配置文件中包含了 `"authorization"` 字段，用户可以在 HTTP 调用中通过 AWS v4 请求签名。

以下示例展示了如何通过配置文件实现授权：

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

:::note

此方法假设你已经有一个启用了程序化访问的 IAM 用户，并具有访问端点的必要权限（AmazonAPIGatewayInvokeFullAccess）。

:::

### 配置路径转发

`aws-lambda` 插件在代理请求到 AWS 上游的时候也支持 URL 路径转发。基本请求路径的扩展被附加到插件配置中指定的 `function_uri` 字段上。

:::info IMPORTANT

为了使 `aws-lambda` 插件正常工作，在路由上配置的 `uri` 字段必须以 `*` 结尾。这是因为 APISIX 路由是严格匹配的，`*` 意味着这个 URI 的任何子路径都会被匹配到同一个路由。

:::

以下示例展示了如何通过配置文件实现路径转发：

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

通过上述示例配置插件后，任何对 `aws/default/test-apisix` 路径的请求都会调用 AWS Lambda 函数，并转发添加的路径。

使用 `curl` 命令测试：

```shell
curl -i -XGET http://127.0.0.1:9080/aws/default/test-apisix\?name\=APISIX
```

预期的返回结果：

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

当你需要禁用 `aws-lambda` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
