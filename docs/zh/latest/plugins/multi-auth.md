---
title: multi-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Multi Auth
  - multi-auth
description: 本文档包含有关 Apache APISIX multi-auth 插件的信息。
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

插件 `multi-auth` 用于向 `Route` 或者 `Service` 中，添加多种身份验证方式。它支持 `auth` 类型的插件。您可以使用 `multi-auth` 插件，来组合不同的身份认证方式。

插件通过迭代 `auth_plugins` 属性指定的插件列表，提供了灵活的身份认证机制。它允许多个 `Consumer` 在使用不同身份验证方式时共享相同的 `Route` ，同时。例如：一个 Consumer 使用 basic 认证，而另一个消费者使用 JWT 认证。

## 属性

For Route:

| 名称           | 类型    | 必选项  | 默认值 | 描述                      |
|--------------|-------|------|-----|-------------------------|
| auth_plugins | array | True | -   | 添加需要支持的认证插件。至少需要 2 个插件。 |

## 启用插件

要启用插件，您必须创建两个或多个具有不同身份验证插件配置的 Consumer：

首先创建一个 Consumer 使用 basic-auth 插件：

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
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "foo1",
    "plugins": {
        "basic-auth": {
            "username": "foo1",
            "password": "bar1"
        }
    }
}'
```

然后再创建一个 Consumer 使用 key-auth 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "foo2",
    "plugins": {
        "key-auth": {
            "key": "auth-one"
        }
    }
}'
```

创建 Consumer 之后，您可以配置一个路由或服务来验证请求：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "multi-auth":{
         "auth_plugins":[
            {
               "basic-auth":{ }
            },
            {
               "key-auth":{
                  "query":"apikey",
                  "hide_credentials":true,
                  "header":"apikey"
               }
            }
         ]
      }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## 使用示例

如上所述配置插件后，您可以向对应的 API 发起一个请求，如下所示：

请求开启 basic-auth 插件的 API

```shell
curl -i -ufoo1:bar1 http://127.0.0.1:9080/hello
```

请求开启 key-auth 插件的 API

```shell
curl http://127.0.0.1:9080/hello -H 'apikey: auth-one' -i
```

```
HTTP/1.1 200 OK
...
hello, world
```

如果请求未授权，将会返回 `401 Unauthorized` 错误：

```json
{"message":"Authorization Failed"}
```

## 删除插件

要删除 `multi-auth` 插件，您可以从插件配置中删除插件对应的 JSON 配置，APISIX 会自动加载，您不需要重新启动即可生效。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
