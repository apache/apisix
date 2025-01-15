---
title: echo
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Echo
description: 本文介绍了关于 Apache APISIX `echo` 插件的基本信息及使用方法。
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

`echo` 插件可以帮助用户尽可能地全面了解如何开发 APISIX 插件。

该插件展示了如何在常见的 `phase` 中实现相应的功能，常见的 `phase` 包括：init, rewrite, access, balancer, header filter, body filter 以及 log。

:::caution WARNING

`echo` 插件只能用作示例，并不能处理一些特别的场景。**请勿将该插件用在生产环境中！**

:::

## 属性

| 名称        | 类型   | 必选项  |  描述                                                                                            |
| ----------- | ------ | ------ | ----------------------------------------------------------------------------------------------- |
| before_body | string | 否     | 在 `body` 属性之前添加的内容，如果 `body` 属性没有指定，就会将其添加在上游 `response body` 之前。 |
| body        | string | 否     | 返回给客户端的响应内容，它将覆盖上游返回的响应 `body`。                                        |
| after_body  | string | 否     | 在 `body` 属性之后添加的内容，如果 body 属性没有指定将在上游响应 `body` 之后添加。              |
| headers     | object | 否     | 返回值的 headers。                                                                                |

:::note

参数 `before_body`、`body` 和 `after_body` 至少要配置一个。

:::

## 启用插件

以下示例展示了如何在指定路由中启用 `echo` 插件。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

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
        "echo": {
            "before_body": "before the body modification "
        }
    },
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

## 测试插件

通过上述命令启用插件后，你可以使用如下命令测试插件是否启用成功：

```shell
curl -i http://127.0.0.1:9080/hello
```

```
HTTP/1.1 200 OK
...
before the body modification hello world
```

## 删除插件

当你需要禁用 `echo` 插件时，可通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
