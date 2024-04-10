---
title: openwhisk
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - OpenWhisk
description: 本文介绍了关于 Apache APISIX openwhisk 插件的基本信息及使用方法。
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

`openwhisk` 插件用于将开源的分布式无服务器平台 [Apache OpenWhisk](https://openwhisk.apache.org) 作为动态上游集成至 APISIX。

启用 `openwhisk` 插件后，该插件会终止对已配置 URI 的请求，并代表客户端向 OpenWhisk 的 API Host 端点发起一个新的请求，然后 `openwhisk` 插件会将响应信息返回至客户端。

## 属性

| 名称              | 类型    | 必选项 | 默认值  | 有效值       | 描述                                                         |
| ----------------- | ------- | ------ | ------- | ------------ | ------------------------------------------------------------ |
| api_host          | string  | 是     |         |              | OpenWhisk API Host 地址，例如 `https://localhost:3233`。     |
| ssl_verify        | boolean | 否     | true    |              | 当设置为 `true` 时执行 SSL 验证。                            |
| service_token     | string  | 是     |         |              | OpenWhisk service token，其格式为 `xxx:xxx` ，用于 API 调用时的身份认证。 |
| namespace         | string  | 是     |         |              | OpenWhisk namespace，例如 `guest`。                          |
| action            | string  | 是     |         |              | OpenWhisk action，例如 `hello`。                              |
| result            | boolean | 否     | true    |              | 当设置为 `true` 时，获得 action 元数据（执行函数并获得响应结果）。 |
| timeout           | integer | 否     | 60000ms | [1,60000]ms  | OpenWhisk action 和 HTTP 调用超时时间（以毫秒为单位）。          |
| keepalive         | boolean | 否     | true    |              | 当设置为 `true` 时，保持连接的活动状态以便重复使用。         |
| keepalive_timeout | integer | 否     | 60000ms | [1000,...]ms | 当连接空闲时，保持该连接处于活动状态的时间（以毫秒为单位）。               |
| keepalive_pool    | integer | 否     | 5       | [1,...]      | 连接断开之前，可接收的最大请求数。                           |

:::note 注意

`timeout` 字段规定了 OpenWhisk action 的最大执行时间，以及 APISIX 中 HTTP 客户端的请求超时时间。

因为 OpenWhisk action 调用可能会耗费很长时间来拉取容器镜像和启动容器，所以如果 `timeout` 字段值设置太小，可能会导致大量的失败请求。

在 OpenWhisk 中 `timeout` 字段的值设置范围从 1 ms 到 60000 ms，建议用户将 `timeout` 字段的值至少设置为 1000ms。

:::

## 启用插件

### 搭建 Apache OpenWhisk 测试环境

1. 在使用 `openwhisk` 插件之前，你需要通过以下命令运行 OpenWhisk standalone 模式。请确保当前环境中已经安装 Docker 软件。

```shell
docker run --rm -d \
  -h openwhisk --name openwhisk \
  -p 3233:3233 -p 3232:3232 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  openwhisk/standalone:nightly
docker exec openwhisk waitready
```

2. 安装 [openwhisk-cli](https://github.com/apache/openwhisk-cli) 工具：

你可以在 [openwhisk-cli](https://github.com/apache/openwhisk-cli) 仓库下载已发布的适用于 Linux 系统的可执行二进制文件 wsk。

3. 在 OpenWhisk 中注册函数：

```shell
wsk property set --apihost "http://localhost:3233" --auth "${service_token}"
wsk action update test <(echo 'function main(){return {"ready":true}}') --kind nodejs:14
```

### 创建路由

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
    "uri": "/hello",
    "plugins": {
        "openwhisk": {
            "api_host": "http://localhost:3233",
            "service_token": "${service_token}",
            "namespace": "guest",
            "action": "test"
        }
    }
}'
```

### 测试请求

使用 `curl` 命令测试：

```shell
curl -i http://127.0.0.1:9080/hello
```

正常返回结果：

```json
{ "ready": true }
```

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
