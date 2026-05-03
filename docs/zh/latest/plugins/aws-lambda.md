---
title: aws-lambda
keywords:
  - Apache APISIX
  - Plugin
  - AWS Lambda
  - aws-lambda
description: aws-lambda 插件支持 APISIX 与 AWS Lambda 和 Amazon API Gateway 集成，支持通过 IAM 访问密钥和 API 密钥进行身份验证。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/aws-lambda" />
</head>

## 描述

`aws-lambda` 插件简化了 APISIX 与 [AWS Lambda](https://aws.amazon.com/lambda/) 和 [Amazon API Gateway](https://aws.amazon.com/api-gateway/) 的集成，用于代理至其他 AWS 服务。

该插件支持通过 IAM 用户凭证和 API Gateway 的 API 密钥进行 AWS 身份验证和授权。

## 属性

| 名称                         | 类型    | 必选项 | 默认值        | 有效值     | 描述                                                                                                                                                      |
|------------------------------|---------|--------|---------------|------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| function_uri                 | string  | 是     |               |            | 触发 Lambda 函数的 AWS Lambda 函数 URL 或 Amazon API Gateway 端点。                                                                                       |
| authorization                | object  | 否     |               |            | 在 AWS 上调用 Lambda 函数时用于身份验证和授权的凭证。                                                                                                     |
| authorization.apikey         | string  | 否     |               |            | 选择 API 密钥作为安全机制时，REST API Gateway 的 API 密钥。                                                                                               |
| authorization.iam            | object  | 否     |               |            | 使用 [AWS Signature Version 4](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_aws-signing.html) 进行身份验证和授权的 IAM 凭证。               |
| authorization.iam.accesskey  | string  | 否     |               |            | IAM 用户访问密钥。当配置 `authorization.iam` 时必填。                                                                                                     |
| authorization.iam.secretkey  | string  | 否     |               |            | IAM 用户秘密访问密钥。当配置 `authorization.iam` 时必填。                                                                                                 |
| authorization.iam.aws_region | string  | 否     | "us-east-1"   |            | 发送请求的 AWS 区域。                                                                                                                                     |
| authorization.iam.service    | string  | 否     | "execute-api" |            | 接收请求的服务。与 AWS API Gateway 集成时设置为 `execute-api`，直接与 Lambda 函数集成时设置为 `lambda`。                                                  |
| timeout                      | integer | 否     | 3000          | [100,...]  | 代理请求超时时间，单位为毫秒。                                                                                                                            |
| ssl_verify                   | boolean | 否     | true          |            | 若为 true，执行 SSL 验证。                                                                                                                                |
| keepalive                    | boolean | 否     | true          |            | 若为 true，保持连接以便复用。                                                                                                                             |
| keepalive_pool               | integer | 否     | 5             | [1,...]    | 保活连接池中的最大连接数。                                                                                                                                |
| keepalive_timeout            | integer | 否     | 60000         | [1000,...] | 连接空闲时保持活跃的时间，单位为毫秒。                                                                                                                    |

## 示例

以下示例演示如何针对不同场景配置 `aws-lambda` 插件。

在操作前，请先登录 AWS 控制台并创建一个 Lambda 函数（使用任意运行时即可）。默认情况下，该函数被调用后应返回 `Hello from Lambda!`。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 使用 IAM 访问密钥安全调用 Lambda 函数

以下示例演示如何将 APISIX 与 Lambda 函数集成，并使用 IAM 访问密钥进行授权。`aws-lambda` 插件实现了 [AWS Signature Version 4](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_aws-signing.html) 签名。

对于 IAM 访问密钥，请前往 **AWS Identity and Access Management (IAM)** 并选择要用于集成的用户。

在 **安全凭证** 标签页中，选择 **创建访问密钥**：

![create access keys](https://static.api7.ai/uploads/2024/04/23/1K9FiWb4_create-access-key.png)

选择 **在 AWS 外部运行的应用程序** 作为使用场景：

![select use case](https://static.api7.ai/uploads/2024/04/23/Fa4jdK5H_iam-user-use-case.png)

继续创建凭证，并记录访问密钥和秘密访问密钥：

![save access keys](https://static.api7.ai/uploads/2024/04/23/zGCyqp20_save-access-key.png)

要创建 Lambda 函数 URL，请前往 Lambda 函数的 **配置** 标签页，在 **函数 URL** 下创建函数 URL：

![create function URL](https://static.api7.ai/uploads/2024/04/23/3fF90ws2_function-url.png)

最后，在 APISIX 中使用函数 URL 和 IAM 访问密钥创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "aws-lambda-iam-route",
    "uri": "/aws-lambda",
    "plugins": {
      "aws-lambda": {
        "function_uri": "https://<YOUR_LAMBDA_FUNCTION_URL>/",
        "authorization": {
          "iam": {
            "accesskey": "<YOUR_ACCESS_KEY>",
            "secretkey": "<YOUR_SECRET_KEY>",
            "aws_region": "<YOUR_AWS_REGION>",
            "service": "lambda"
          }
        },
        "ssl_verify": false
      }
    }
  }'
```

请将 `function_uri`、`accesskey`、`secretkey` 和 `aws_region` 替换为你的实际值。直接与 Lambda 函数集成时，将 `service` 设置为 `lambda`。

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/aws-lambda"
```

你应该收到 `HTTP/1.1 200 OK` 响应，内容如下：

```text
"Hello from Lambda!"
```

### 通过 API 密钥与 Amazon API Gateway 安全集成

以下示例演示如何将 APISIX 与 Amazon API Gateway 集成，并配置网关触发 Lambda 函数的执行。

要将 API Gateway 配置为 Lambda 触发器，请前往 Lambda 函数并选择 **添加触发器**：

![add trigger for lambda function](https://static.api7.ai/uploads/2024/04/25/UjI9bLDQ_add-trigger.png)

选择 **API Gateway** 作为触发器，**REST API** 作为 API 类型，完成触发器添加：

![select REST to be the API type and secure the API with API key](https://static.api7.ai/uploads/2024/04/25/4Bp9r3UP_rest-api-key.png)

:::note

Amazon API Gateway 支持两种 RESTful API 类型：HTTP API 和 REST API。只有 REST API 提供 API 密钥和 IAM 作为安全机制。

:::

你将被重定向回 Lambda 界面。要查找 API 密钥和网关 API 端点，请前往 Lambda 函数的 **配置** 标签页，在 **触发器** 下查看 API Gateway 详情：

![API gateway endpoint and API key](https://static.api7.ai/uploads/2024/04/25/6bjpeNIb_api-gateway-info.png)

最后，在 APISIX 中使用网关端点和 API 密钥创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "aws-lambda-apikey-route",
    "uri": "/aws-lambda",
    "plugins": {
      "aws-lambda": {
        "function_uri": "https://<YOUR_API_GATEWAY_ENDPOINT>/default/api7-docs",
        "authorization": {
          "apikey": "<YOUR_API_KEY>"
        },
        "ssl_verify": false
      }
    }
  }'
```

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/aws-lambda"
```

你应该收到 `HTTP/1.1 200 OK` 响应，内容如下：

```text
"Hello from Lambda!"
```

如果 API 密钥无效，你将收到 `HTTP/1.1 403 Forbidden` 响应。

### 将请求转发到 Amazon API Gateway 子路径

以下示例演示如何将请求转发到 Amazon API Gateway 的子路径，并配置 API 触发 Lambda 函数的执行。

请先参考[上一个示例](#通过-api-密钥与-amazon-api-gateway-安全集成)完成 API Gateway 的设置。

要创建子路径，请前往 Lambda 函数的 **配置** 标签页，在 **触发器** 下点击进入 API Gateway：

![click into the API gateway](https://static.api7.ai/uploads/2024/04/26/5Twffgyr_click-into-adjusted.png)

选择 **创建资源** 以创建子路径：

![create resource](https://static.api7.ai/uploads/2024/04/26/hXlnuVwk_create-resource.png)

填写子路径信息并完成创建：

![complete resource creation](https://static.api7.ai/uploads/2024/04/26/7t1yiWjl_create-resource-2.png)

回到网关主控制台后，你将看到新创建的路径。选择 **创建方法** 为路径配置 HTTP 方法和关联的操作：

![click on create method](https://static.api7.ai/uploads/2024/04/26/3rZZJy3e_create-method.png)

在下拉菜单中选择允许的 HTTP 方法。本示例继续使用相同的 Lambda 函数作为请求该路径时的触发操作：

![create method and lambda function](https://static.api7.ai/uploads/2024/04/26/vni7yS2q_create%20method%202.png)

完成方法创建。回到网关主控制台后，点击 **部署 API** 以部署路径和方法变更：

![deploy changes to API gateway](https://static.api7.ai/uploads/2024/04/26/2vrqnVPB_deploy-api.png)

最后，在 APISIX 中使用网关端点和 API 密钥创建路由。`uri` 必须以 `*` 结尾，以便所有子路径都匹配到同一路由，匹配到的子路径将追加到 `function_uri` 的末尾：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "aws-lambda-subpath-route",
    "plugins": {
      "aws-lambda": {
        "function_uri": "https://<YOUR_API_GATEWAY_ENDPOINT>/default",
        "authorization": {
          "apikey": "<YOUR_API_KEY>"
        },
        "ssl_verify": false
      }
    }
  }'
```

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/aws-lambda/api7-docs"
```

APISIX 将把请求转发至 `https://<YOUR_API_GATEWAY_ENDPOINT>/default/api7-docs`，你应该收到 `HTTP/1.1 200 OK` 响应，内容如下：

```text
"Hello from Lambda!"
```

如果 API 密钥无效或请求路径没有关联任何方法，你将收到 `HTTP/1.1 403 Forbidden` 响应。
