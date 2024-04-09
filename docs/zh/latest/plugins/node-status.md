---
title: node-status
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - Node status
description: 本文介绍了 API 网关 Apache APISIX node-status 插件的相关信息。
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

`node-status` 插件可用于通过暴露的 API 查询 APISIX 的请求状态，并返回基本的状态信息。

## 插件属性

无。

## 插件接口

该插件将会增加 `/apisix/status` 的接口用来暴露 APISIX 的状态，你需要通过 [public-api](public-api.md) 插件来暴露该接口。

## 启用插件

`node-status` 插件默认为禁用状态，如果你需要使用该插件，请在配置文件 `./conf/config.yaml` 中启用它：

``` yaml title="./conf/config.yaml"
plugins:
  - limit-req
  - node-status
  - jwt-auth
  - zipkin
  ......
```

你需要为 `/apisix/status` API 配置路由，并使用 [public-api](public-api.md) 插件暴露它。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/ns -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/apisix/status",
    "plugins": {
        "public-api": {}
    }
}'
```

## 测试插件

完成上述配置后，你可以通过以下命令向 `/apisix/status` 发送请求以获取状态信息。

```shell
curl http://127.0.0.1:9080/apisix/status -i
```

```shell
HTTP/1.1 200 OK
Date: Tue, 03 Nov 2020 11:12:55 GMT
Content-Type: text/plain; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

{"status":{"total":"23","waiting":"0","accepted":"22","writing":"1","handled":"22","active":"1","reading":"0"},"id":"6790a064-8f61-44ba-a6d3-5df42f2b1bb3"}
```

返回结果中的参数释义如下：

| 参数         | 说明                                                                    |
| ------------ | ---------------------------------------------------------------------- |
| status       | APISIX 的状态信息。                                                     |
| total        | 客户端请求总数。                                                        |
| waiting      | 当前等待客户端请求的空闲连接数。                                          |
| accepted     | 当前已经接受的客户端连接总数。                                            |
| writing      | 当前正在写给客户端响应的连接数。                                          |
| handled      | 当前已经处理的连接总数，除非达到其他资源的限制，否则此值与 `accepted` 相同。 |
| active       | 当前活跃的客户端连接数。                                                 |
| reading      | 当前正在读取请求头的连接数。                                              |
| id           | APISIX UID 信息，保存在 `./conf/apisix.uid` 文件中。                |

## 删除插件

如果你不再需要该插件，可以从配置文件 (`./conf/config.yaml`) 中删除它：

``` yaml title="conf/config.yaml"
  - limit-req
  - jwt-auth
  - zipkin
  ......
```

你也可以移除暴露 `/apisix/status` 接口的路由。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/ns -H "X-API-KEY: $admin_key" -X DELETE
```
