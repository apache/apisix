---
title: basic-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Basic Auth
  - basic-auth
description: 本文介绍了关于 Apache APISIX `basic-auth` 插件的基本信息及使用方法。
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

使用 `basic-auth` 插件可以将 [Basic_access_authentication](https://en.wikipedia.org/wiki/Basic_access_authentication) 添加到 Route 或 Service 中。

该插件需要与 [Consumer](../terminology/consumer.md) 一起使用。API 的消费者可以将它们的密钥添加到请求头中以验证其请求。

## 属性

Consumer 端：

| 名称     | 类型   | 必选项 | 描述                                                                                           |
| -------- | ------ | -----| ----------------------------------------------------------------------------------------------- |
| username | string | 是   | Consumer 的用户名并且该用户名是唯一，如果多个 Consumer 使用了相同的 `username`，将会出现请求匹配异常。|
| password | string | 是   | 用户的密码。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。        |

注意：schema 中还定义了 `encrypt_fields = {"password"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

Route 端：

| 名称             | 类型     | 必选项 | 默认值  | 描述                                                            |
| ---------------- | ------- | ------ | ------ | --------------------------------------------------------------- |
| hide_credentials | boolean | 否     | false  | 该参数设置为 `true` 时，则不会将 Authorization 请求头传递给 Upstream。|

## 启用插件

如果需要启用插件，就必须创建一个具有身份验证配置的 Consumer：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "foo",
    "plugins": {
        "basic-auth": {
            "username": "foo",
            "password": "bar"
        }
    }
}'
```

你也可以通过 [APISIX Dashboard](/docs/dashboard/USER_GUIDE) 完成上述操作。

<!--
![auth-1](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/basic-auth-1.png)

![auth-2](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/basic-auth-2.png)
-->

创建 Consumer 后，就可以通过配置 Route 或 Service 来验证插件，以下是配置 Route 的命令：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "basic-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## 测试插件

通过上述命令启用插件后，可以通过以下方法测试插件。

```shell
curl -i -ufoo:bar http://127.0.0.1:9080/hello
```

如果配置成功则返回如下结果：

```shell
HTTP/1.1 200 OK
...
hello, world
```

如果请求未授权，则返回如下结果：

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Missing authorization in request"}
```

如果用户名和密码错则返回如下结果：

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user authorization"}
```

## 删除插件

当你需要禁用 `basic-auth` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
