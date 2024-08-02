---
title: authz-casdoor
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Authz Casdoor
  - authz-casdoor
description: 本篇文档介绍了 Apache APISIX auth-casdoor 插件的相关信息。
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

使用 `authz-casdoor` 插件可添加 [Casdoor](https://casdoor.org/) 集中认证方式。

## 属性

| 名称          | 类型   | 必选项 | 描述                                  |
|---------------|--------|----------|----------------------------------------------|
| endpoint_addr | string | 是     | Casdoor 的 URL。                           |
| client_id     | string | 是     | Casdoor 的客户端 id。                      |
| client_secret | string | 是     | Casdoor 的客户端密钥。                 |
| callback_url  | string | 是     | 用于接收 code 与 state 的回调地址。 |

注意：schema 中还定义了 `encrypt_fields = {"client_secret"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

:::info IMPORTANT

指定 `endpoint_addr` 和 `callback_url` 属性时不要以“/”来结尾。

`callback_url` 必须是路由的 URI。具体细节可查看下方示例内容，了解相关配置。

:::

## 启用插件

以下示例展示了如何在指定路由上启用 `auth-casdoor` 插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "methods": ["GET"],
  "uri": "/anything/*",
  "plugins": {
    "authz-casdoor": {
        "endpoint_addr":"http://localhost:8000",
        "callback_url":"http://localhost:9080/anything/callback",
        "client_id":"7ceb9b7fda4a9061ec1c",
        "client_secret":"3416238e1edf915eac08b8fe345b2b95cdba7e04"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}'
```

## 测试插件

一旦启用了该插件，访问该路由的新用户首先会经过 `authz-casdoor` 插件的处理，然后被重定向到 Casdoor 登录页面。

成功登录后，Casdoor 会将该用户重定向到 `callback_url`，并指定 GET 参数的 `code` 和 `state`。该插件还会向 Casdoor 请求一个访问 Token，并确认用户是否已登录。在成功认证后，该流程只出现一次并且后续请求不会被打断。

上述操作完成后，用户就会被重定向到目标 URL。

## 删除插件

当需要禁用 `authz-casdoor` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/anything/*",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```
