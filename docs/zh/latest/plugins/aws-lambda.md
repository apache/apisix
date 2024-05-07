---
title: aws-lambda
keywords:
  - Apache APISIX
  - Plugin
  - AWS Lambda
  - aws-lambda
description: 本文介绍了关于 Apache APISIX aws-lambda 插件的基本信息及使用方法。
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

`aws-lambda` 插件用于将 [AWS Lambda](https://aws.amazon.com/lambda/) 和 [Amazon API Gateway](https://aws.amazon.com/api-gateway/) 作为动态上游集成至 APISIX，从而实现将访问指定 URI 的请求代理到 AWS 云。

启用 `aws-lambda` 插件后，该插件会终止对已配置 URI 的请求，并代表客户端向 AWS Lambda Gateway URI 发起一个新的请求。这个新请求中携带了之前配置的授权详细信息，包括请求头、请求体和参数（以上参数都是从原始请求中传递的），然后 `aws-lambda` 插件会将带有响应头、状态码和响应体的响应信息返回给使用 APISIX 发起请求的客户端。

该插件支持通过 AWS API key 和 AWS IAM secrets 进行授权。当使用 AWS IAM secrets 时，该插件支持 [AWS Signature Version 4 signing](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_aws-signing.html)。

## 属性

| 名称                 | 类型     | 必选项   | 默认值  | 有效值       | 描述                                                 |
| ------------------ - | ------- | -------- | ------- | ------------ | ------------------------------------------------------------ |
| function_uri         | string  | 是       |         |              | 触发 lambda serverless 函数的 AWS API Gateway 端点。        |
| authorization        | object  | 否       |         |              | 访问云函数的授权凭证。                                       |
| authorization.apikey | string  | 否       |         |              | 生成的 API 密钥，用于授权对 AWS Gateway 端点的请求。         |
| authorization.iam    | object  | 否       |         |              | 用于通过 AWS v4 请求签名执行的基于 AWS IAM 角色的授权。请参考 [IAM 授权方案](#iam-授权方案)。 |
| authorization.iam.accesskey  | string | 是       |               | 从 AWS IAM 控制台生成的访问密钥 ID。                     |
| authorization.iam.secretkey | string | 是       |               | 从 AWS IAM 控制台生成的访问密钥。                          |
| authorization.iam.aws_region | string | 否       | "us-east-1"   | 发出请求的 AWS 区域。有关更多 AWS 区域代码的信息请参考 [AWS 区域代码表](https://docs.aws.amazon.com/zh_cn/general/latest/gr/rande.html#region-names-codes)。 |
| authorization.iam.service    | string | 否       | "execute-api" | 接收该请求的服务。若使用 Amazon API gateway APIs, 应设置为 `execute-api`。若使用 Lambda function, 应设置为 `lambda`。 |
| timeout              | integer | 否       | 3000    | [100,...]    | 代理请求超时（以毫秒为单位）。                                 |
| ssl_verify           | boolean | 否       | true    | true/false   | 当设置为 `true` 时执行 SSL 验证。                          |
| keepalive            | boolean | 否       | true    | true/false   | 当设置为 `true` 时，保持连接的活动状态以便重复使用。         |
| keepalive_pool       | integer | 否       | 5       | [1,...]      | 在关闭该连接之前，可以在该连接上发送的最大请求数。           |
| keepalive_timeout    | integer | 否       | 60000   | [1000,...]   | 当连接空闲时，保持该连接处于活动状态的时间，以毫秒为单位。           |

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

通过上述示例配置插件后，任何对 `/aws` URI 的请求（`HTTP/1.1`、`HTTPS`、`HTTP2`）都将调用已配置的 AWS 函数的 URI，并且会将响应信息返回给客户端。

下述命令的含义是：AWS Lambda 从请求中获取 `name` 参数，并返回一条 `"Hello $name"` 消息：

```shell
curl -i -XGET localhost:9080/aws\?name=APISIX
```

正常返回结果：

```shell
HTTP/1.1 200 OK
Content-Type: application/json
...
"Hello, APISIX!"
```

以下示例是客户端通过 HTTP/2 协议与 APISIX 进行通信。

在进行测试之前，由于该 `enable_http2: true` 默认是禁用状态，你可以通过在 `./conf/config.yaml` 中添加 `apisix.node_listen` 下的 `- port: 9081` 和 `enable_http2: true` 字段启用。示例如下

```yaml
apisix:
  node_listen:                      # 支持监听多个端口
    - 9080
    - port: 9081
      enable_http2: true            # 该字段如果不设置，默认值为 `false`
```

使用 `curl` 命令测试：

```shell
curl -i -XGET --http2 --http2-prior-knowledge localhost:9081/aws\?name=APISIX
```

正常返回结果：

```shell
HTTP/2 200
content-type: application/json
...
"Hello, APISIX!"
```

与上面的示例类似，AWS Lambda 函数也可以通过 AWS API Gateway 触发，但需要使用 AWS IAM 权限进行授权。`aws-lambda` 插件的配置文件中包含了 `"authorization"` 字段，用户可以在 HTTP 调用中通过 AWS v4 请求签名。

以下示例展示了如何通过配置文件实现授权：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

:::note 注意

使用该方法时已经假设你有一个启用了程序化访问的 IAM 用户，并具有访问端点的必要权限（AmazonAPIGatewayInvokeFullAccess）。

:::

### 配置路径转发

`aws-lambda` 插件在代理请求到 AWS 上游时也支持 URL 路径转发。基本请求路径的扩展被附加到插件配置中指定的 `function_uri` 字段上。

:::info 重要

因为 APISIX 路由是严格匹配的，所以为了使 `aws-lambda` 插件正常工作，在路由上配置的 `uri` 字段必须以 `*` 结尾，`*` 意味着这个 URI 的任何子路径都会被匹配到同一个路由。

:::

以下示例展示了如何通过配置文件实现路径转发：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

通过上述示例配置插件后，任何访问 `aws/default/test-apisix` 的请求都会调用 AWS Lambda 函数，并转发附加的参数。

使用 `curl` 命令测试：

```shell
curl -i -XGET http://127.0.0.1:9080/aws/default/test-apisix\?name\=APISIX
```

正常返回结果：

```shell
HTTP/1.1 200 OK
Content-Type: application/json
...
"Hello, APISIX!"
```

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
