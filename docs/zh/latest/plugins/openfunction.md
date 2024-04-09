---
title: openfunction
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - OpenFunction
description: 本文介绍了 API 网关 Apache APISIX 的 openfunction 插件的基本信息及使用方法。
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

`openfunction` 插件用于将开源的分布式无服务器平台 [CNCF OpenFunction](https://openfunction.dev/) 作为动态上游集成至 APISIX。

启用 `openfunction` 插件后，该插件会终止对已配置 URI 的请求，并代表客户端向 OpenFunction 的 function 发起一个新的请求，然后 `openfunction` 插件会将响应信息返回至客户端。

## 属性

| 名称                         | 类型    | 必选项 | 默认值  | 有效值       | 描述                                                         |
| --------------------------- | ------- | ------ | ------- | ------------ | ------------------------------------------------------------ |
| function_uri                | string  | 是     |         |              | OpenFunction function uri，例如 `https://localhost:30858/default/function-sample`。     |
| ssl_verify                  | boolean | 否     | true    |              | 当设置为 `true` 时执行 SSL 验证。                            |
| authorization               | object  | 否     |         |              | 访问 OpenFunction 的函数的授权凭证。|
| authorization.service_token | string  | 否     |         |              | OpenFunction service token，其格式为 `xxx:xxx`，支持函数入口的 basic auth 认证方式。 |
| timeout                     | integer | 否     | 3000 ms | [100,...] ms | OpenFunction action 和 HTTP 调用超时时间，以毫秒为单位。          |
| keepalive                   | boolean | 否     | true    |              | 当设置为 `true` 时，保持连接的活动状态以便重复使用。         |
| keepalive_timeout           | integer | 否     | 60000 ms| [1000,...] ms| 当连接空闲时，保持该连接处于活动状态的时间，以毫秒为单位。               |
| keepalive_pool              | integer | 否     | 5       | [1,...]      | 连接断开之前，可接收的最大请求数。                           |

:::note 注意

`timeout` 字段规定了 OpenFunction function 的最大执行时间，以及 APISIX 中 HTTP 客户端的请求超时时间。

因为 OpenFunction function 调用可能会耗费很长时间来拉取容器镜像和启动容器，如果 `timeout` 字段的值设置太小，可能会导致大量请求失败。

:::

## 前提条件

在使用 `openfunction` 插件之前，你需要通过以下命令运行 OpenFunction。详情参考 [OpenFunction 安装指南](https://openfunction.dev/docs/getting-started/installation/) 。

请确保当前环境中已经安装对应版本的 Kubernetes 集群。

### 创建并推送函数

你可以参考 [OpenFunction 官方示例](https://github.com/OpenFunction/samples) 创建函数。构建函数时，你需要使用以下命令为容器仓库生成一个密钥，才可以将函数容器镜像推送到容器仓库 ( 例如 Docker Hub 或 Quay.io）。

```shell
REGISTRY_SERVER=https://index.docker.io/v1/ REGISTRY_USER=<your_registry_user> REGISTRY_PASSWORD=<your_registry_password>
kubectl create secret docker-registry push-secret \
    --docker-server=$REGISTRY_SERVER \
    --docker-username=$REGISTRY_USER \
    --docker-password=$REGISTRY_PASSWORD
```

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "openfunction": {
            "function_uri": "http://localhost:3233/default/function-sample/test",
            "authorization": {
                "service_token": "test:test"
            }
        }
    }
}'
```

## 测试插件

使用 `curl` 命令测试：

```shell
curl -i http://127.0.0.1:9080/hello -X POST -d'test'
```

正常返回结果：

```
hello, test!
```

### 配置路径转发

`OpenFunction` 插件还支持 URL 路径转发，同时将请求代理到上游的 OpenFunction API 端点。基本请求路径的扩展（如路由 `/hello/*` 中 `*` 的部分）会被添加到插件配置中指定的 `function_uri`。

:::info 重要

路由上配置的 `uri` 必须以 `*` 结尾，此功能才能正常工作。APISIX 路由是严格匹配的，`*` 表示此 URI 的任何子路径都将匹配到同一路由。

:::

下面的示例配置了此功能：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello/*",
    "plugins": {
        "openfunction": {
            "function_uri": "http://localhost:3233/default/function-sample",
            "authorization": {
                "service_token": "test:test"
            }
        }
    }
}'
```

现在，对路径 `hello/123` 的任何请求都将调用 OpenFunction 插件设置的对应的函数，并转发添加的路径：

```shell
curl  http://127.0.0.1:9080/hello/123
```

```shell
Hello, 123!
```

## 删除插件

当你需要禁用 `openfunction` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
