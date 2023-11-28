---
title: key-auth
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Key Auth
  - key-auth
description: 本文介绍了关于 Apache APISIX `key-auth` 插件的基本信息及使用方法。
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

`key-auth` 插件用于向 Route 或 Service 添加身份验证密钥（API key）。

它需要与 [Consumer](../terminology/consumer.md) 一起配合才能工作，通过 Consumer 将其密钥添加到查询字符串参数或标头中以验证其请求。

## 属性

Consumer 端：

| 名称 | 类型   | 必选项  | 描述                                                                                                          |
| ---- | ------ | ------ | ------------------------------------------------------------------------------------------------------------- |
| key  | string | 是     | 不同的 Consumer 应有不同的 `key`，它应当是唯一的。如果多个 Consumer 使用了相同的 `key`，将会出现请求匹配异常。该字段支持使用 [APISIX Secret](../terminology/secret.md) 资源，将值保存在 Secret Manager 中。 |

注意：schema 中还定义了 `encrypt_fields = {"key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

Router 端：

| 名称              | 类型   | 必选项 | 默认值 | 描述                                                                                                                                                       |
| ----------------- | ------ | ----- | ------ |----------------------------------------------------------------------------------------------------------------------------------------------------------|
| header            | string | 否    | apikey | 设置我们从哪个 header 获取 key。                                                                                                                                   |
| query             | string | 否    | apikey | 设置我们从哪个 query string 获取 key，优先级低于 `header`。                                                                                                              |
| hide_credentials  | bool   | 否    | false  | 当设置为 `false` 时将含有认证信息的 header 或 query string 传递给 Upstream。如果为 `true` 时将删除对应的 header 或 query string，具体删除哪一个取决于是从 header 获取 key 还是从 query string  获取 key。 |

## 启用插件

如果你要启用插件，就必须使用身份验证密钥创建一个 Consumer 对象，并且需要配置 Route 才可以对请求进行身份验证。

首先，你可以通过 Admin API 创建一个具有唯一 key 的 Consumer：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "auth-one"
        }
    }
}'
```

你还可以通过 [APISIX Dashboard](https://github.com/apache/apisix-dashboard) 的 Web 界面完成上述操作。

<!--

首先创建一个 Consumer：

![create a consumer](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/key-auth-1.png)

然后在 Consumer 页面中添加 `key-auth` 插件：

![enable key-auth plugin](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/key-auth-2.png)

-->

创建 Consumer 对象后，你可以创建 Route 进行验证：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "key-auth": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

如果你不想从默认的 `apikey` header 获取 key，可以自定义 header，如下所示：

```json
{
    "key-auth": {
        "header": "Authorization"
    }
}
```

## 测试插件

通过上述方法配置插件后，可以通过以下命令测试插件：

```shell
curl http://127.0.0.2:9080/index.html -H 'apikey: auth-one' -i
```

```
HTTP/1.1 200 OK
...
```

如果当前请求没有正确配置 `apikey`，将得到一个 `401` 的应答：

```shell
curl http://127.0.0.2:9080/index.html -i
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Missing API key found in request"}
```

```shell
curl http://127.0.0.2:9080/index.html -H 'apikey: abcabcabc' -i
```

```shell
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid API key in request"}
```

## 删除插件

当你需要禁用 `key-auth` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
