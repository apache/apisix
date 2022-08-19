---
title: openfunction
keywords:
  - APISIX
  - Plugin
  - OpenFunction
  - openfunction
description: 本文介绍了关于 CNCF OpenFunction 插件的基本信息及使用方法。
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
| authorization.service_token | string  | 否     |         |              | OpenFunction service token，其格式为 `xxx:xxx` ，支持函数入口的 basic auth 认证方式。 |
| timeout                     | integer | 否     | 3000ms  | [100,...]ms  | OpenFunction action 和 HTTP 调用超时时间（以毫秒为单位）。          |
| keepalive                   | boolean | 否     | true    |              | 当设置为 `true` 时，保持连接的活动状态以便重复使用。         |
| keepalive_timeout           | integer | 否     | 60000ms | [1000,...]ms | 当连接空闲时，保持该连接处于活动状态的时间（以毫秒为单位）。               |
| keepalive_pool              | integer | 否     | 5       | [1,...]      | 连接断开之前，可接收的最大请求数。                           |

:::note

`timeout` 字段规定了 OpenFunction function 的最大执行时间，以及 APISIX 中 HTTP 客户端的请求超时时间。

因为 OpenFunction function 调用可能会耗费很长时间来拉取容器镜像和启动容器，所以如果 `timeout` 字段值设置太小，可能会导致大量的失败请求。

:::

## 先决条件

在使用 `openfunction` 插件之前，你需要通过以下命令运行 OpenFunction 。
详情参考[官方安装指南](https://openfunction.dev/docs/getting-started/installation/) 。
请确保当前环境中已经安装对应版本的 Kubernetes 集群。

### 通过 Helm Chart 安装 OpenFunction

```shell
#add the OpenFunction chart repository
helm repo add openfunction https://openfunction.github.io/charts/
helm repo update

#install the OpenFunction chart
kubectl create namespace openfunction
helm install openfunction openfunction/openfunction -n openfunction
```

你可以通过以下命令来验证 openfunction 是否已经安装成功：

```shell
kubectl get pods --namespace openfunction
```

### 创建并推送函数

你可以通过官方示例创建函数 [sample](https://github.com/OpenFunction/samples) 。
构建函数时，需要将函数容器镜像推送到容器仓库，如 Docker Hub 或 Quay.io。要做到这一点，首先需要输入如下命令为容器仓库生成一个密钥。

```shell
REGISTRY_SERVER=https://index.docker.io/v1/ REGISTRY_USER=<your_registry_user> REGISTRY_PASSWORD=<your_registry_password>
kubectl create secret docker-registry push-secret \
    --docker-server=$REGISTRY_SERVER \
    --docker-username=$REGISTRY_USER \
    --docker-password=$REGISTRY_PASSWORD
```

## 启用插件

通过以下命令创建一个路由，并在配置文件中添加 `openfunction` 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

### 测试请求

使用 `curl` 命令测试：

```shell
curl -i http://127.0.0.1:9080/hello -X POST -d'test'
```

正常返回结果：

```
hello, test!
```

## 禁用插件

当你需要禁用 `openfunction` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
