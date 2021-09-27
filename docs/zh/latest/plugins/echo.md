---
title: echo
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

## 目录

- [**简介**](#简介)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 简介

echo 可以帮助用户尽可能全面地了解如何开发APISIX插件。

该插件展示了如何在常见的 phase 中实现相应的功能，常见的 phase 包括：init, rewrite, access, balancer, header filter, body filter 以及 log。

**注意：该插件仅用作示例，并没有处理一些特别的场景。请勿将之用于生产环境上！**

## 属性

| 名称        | 类型   | 必选项 | 默认值 | 有效值 | 描述                                                                                     |
| ----------- | ------ | ------ | ------ | ------ | ---------------------------------------------------------------------------------------- |
| before_body | string | 可选   |        |        | 在 body 属性之前添加的内容，如果 body 属性没有指定将添加在 upstream response body 之前。 |
| body        | string | 可选   |        |        | 返回给客户端的响应内容，它将覆盖 upstream 返回的响应 body。                              |
| after_body  | string | 可选   |        |        | 在 body 属性之后添加的内容，如果 body 属性没有指定将在 upstream 响应 body 之后添加。     |
| headers     | object | 可选   |        |        | 返回值的 headers                                                                         |

参数 before_body，body 和 after_body 至少要存在一个

## 如何启用

为特定路由启用 echo 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

* 成功:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
before the body modification hello world
```

## 禁用插件

当您要禁用`echo`插件时，这很简单，您可以在插件配置中删除相应的 json 配置，无需重新启动服务，它将立即生效：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
