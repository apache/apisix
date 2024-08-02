---
title: azure-functions
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Azure Functions
  - azure-functions
description: 本文介绍了关于 API 网关 Apache APISIX azure-functions 插件的基本信息及使用方法。
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

`azure-functions` 插件用于将 [Azure Serverless Function](https://azure.microsoft.com/en-in/services/functions/) 作为动态上游集成至 APISIX，从而实现将访问指定 URI 的请求代理到 Microsoft Azure 云服务。

启用 `azure-functions` 插件后，该插件会终止对已配置 URI 的请求，并代表客户端向 Azure Functions 发起一个新的请求。该新请求中携带了之前配置的授权详细信息，包括请求头、请求体和参数（以上参数都是从原始请求中传递的）。之后便会通过 `azure-functions` 插件，将带有响应头、状态码和响应体的信息返回给使用 APISIX 发起请求的客户端。

## 属性

| 名称                   | 类型    | 必选项 | 默认值 | 有效值     | 描述                                                         |
| ---------------------- | ------- | ------ | ------ | ---------- | ------------------------------------------------------------ |
| function_uri           | string  | 是     |        |            | 触发 Serverless Functions 的 Azure Functions 端点。例如 `http://test-apisix.azurewebsites.net/api/HttpTrigger`。 |
| authorization          | object  | 否     |        |            | 访问 Azure Functions 的授权凭证。                            |
| authorization.apikey   | string  | 否     |        |            | 授权凭证内的字段。生成 API 密钥来授权对端点的请求。          |
| authorization.clientid | string  | 否     |        |            | 授权凭证内的字段。生成客户端 ID（Azure Active Directory）来授权对端点的请求。 |
| timeout                | integer | 否     | 3000   | [100,...]  | 代理请求超时（以毫秒为单位）。                               |
| ssl_verify             | boolean | 否     | true   | true/false | 当设置为 `true` 时执行 SSL 验证。                            |
| keepalive              | boolean | 否     | true   | true/false | 当设置为 `true` 时，保持连接的活动状态以便重复使用。         |
| keepalive_pool         | integer | 否     | 5      | [1,...]    | 连接断开之前，可接收的最大请求数。                           |
| keepalive_timeout      | integer | 否     | 60000  | [1000,...] | 当连接空闲时，保持该连接处于活动状态的时间（以毫秒为单位）。 |

## 元数据

| 名称            | 类型   | 必选项 | 默认值 | 描述                                                         |
| --------------- | ------ | ------ | ------ | ------------------------------------------------------------ |
| master_apikey   | string | 否     | ""     | 可用于访问 Azure Functions URI 的 API 密钥。                 |
| master_clientid | string | 否     | ""     | 可用于授权 Azure Functions URI 的客户端 ID（Active Directory）。 |

`azure-functions` 插件的元数据提供了授权回退的功能。它定义了 `master_apikey` 和 `master_clientid` 字段，用户可以为关键任务的应用部署声明 API 密钥或客户端 ID。因此，如果在 `azure-functions` 插件属性中没有找到相关授权凭证，此时元数据中的授权凭证就会发挥作用。

:::note 注意

授权方式优先级排序如下：

1. 首先，`azure-functions` 插件在 APISIX 代理的请求头中寻找 `x-functions-key` 或 `x-functions-clientid` 键。
2. 如果没有找到，`azure-functions` 插件会检查插件属性中的授权凭证。如果授权凭证存在，`azure-functions` 插件会将相应的授权标头添加到发送到 Azure Functions 的请求中。
3. 如果未配置 `azure-functions` 插件的授权凭证属性，APISIX 将获取插件元数据配置并使用 API 密钥。

:::

如果你想添加一个新的 API 密钥，请向 `/apisix/admin/plugin_metadata` 端点发出请求，并附上所需的元数据。示例如下：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/azure-functions \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "master_apikey" : "<Your Azure master access key>"
}'
```

## 启用插件

你可以通过以下命令在指定路由中启用该插件，请确保你的 Azure Functions 已提前部署好，并正常提供服务。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "azure-functions": {
            "function_uri": "http://test-apisix.azurewebsites.net/api/HttpTrigger",
            "authorization": {
                "apikey": "${Generated API key to access the Azure-Function}"
            }
        }
    },
    "uri": "/azure"
}'
```

通过上述示例配置插件后，任何对 `/azure` URI 的请求（`HTTP/1.1`、`HTTPS`、`HTTP2`）都将调用已配置的 Azure Functions 的 URI，并且会将响应信息返回给客户端。

下述命令的含义是：Azure Functions 从请求中获取 `name` 参数，并返回一条 `"Hello $name"` 消息：

```shell
curl -i -XGET http://localhost:9080/azure\?name=APISIX
```

正常返回结果：

```shell
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
...
Hello, APISIX
```

以下示例是客户端通过 HTTP/2 协议与 APISIX 进行通信。

在进行测试之前，由于该 `enable_http2: true` 默认是禁用状态，你可以通过在 `./conf/config.yaml` 中添加 `apisix.node_listen` 下的 `- port: 9081` 和 `enable_http2: true` 字段启用。示例如下：

```yaml
apisix:
  node_listen:                      # 支持监听多个端口
    - 9080
    - port: 9081
      enable_http2: true            # 该字段如果不设置，默认值为 `false`
```

使用 `curl` 命令测试：

```shell
curl -i -XGET --http2 --http2-prior-knowledge http://localhost:9081/azure\?name=APISIX
```

正常返回结果：

```shell
HTTP/2 200
content-type: text/plain; charset=utf-8
...
Hello, APISIX
```

### 配置路径转发

`azure-functions` 插件在代理请求到 Azure Functions 上游时也支持 URL 路径转发。基本请求路径的扩展被附加到插件配置中指定的 `function_uri` 字段上。

:::info 重要

因为 APISIX 路由是严格匹配的，所以为了使 `azure-functions` 插件正常工作，在路由上配置的 `uri` 字段必须以 `*` 结尾，`*` 意味着这个 URI 的任何子路径都会被匹配到同一个路由。

:::

以下示例展示了如何通过配置文件实现路径转发：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "azure-functions": {
            "function_uri": "http://app-bisakh.azurewebsites.net/api",
            "authorization": {
                "apikey": "${Generated API key to access the Azure-Function}"
            }
        }
    },
    "uri": "/azure/*"
}'
```

通过上述示例配置插件后，任何访问 `azure/HttpTrigger1` 的请求都会调用 Azure Functions 并转发附加的参数。

使用 `curl` 命令测试：

```shell
curl -i -XGET http://127.0.0.1:9080/azure/HttpTrigger1\?name\=APISIX\
```

正常返回结果：

```shell
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
...
Hello, APISIX
```

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
