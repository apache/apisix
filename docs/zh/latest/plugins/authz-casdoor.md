---
title: authz-casdoor
keywords:
  - APISIX
  - Plugin
  - Authz Casdoor
  - authz-casdoor
description: This document contains information about the Apache APISIX authz-casdoor Plugin.
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

使用 `authz-Casdoor` 插件可添加 [Casdoor](https://casdoor.org/) 集中认证方式。

## 属性

| 名称          | 类型   | 必选项 | 描述                                  |
|---------------|--------|----------|----------------------------------------------|
| endpoint_addr | string | 是     | Casdoor URL。                           |
| client_id     | string | 是     | Casdoor 客户端 id。                      |
| client_secret | string | 是     | Casdoor 客户端密码。                 |
| callback_url  | string | 是     | 用于接收状态和代码的回调 URL。 |

:::info IMPORTANT

`endpoint_addr` 和 `callback_url` 属性不要以 “/” 来结尾。

:::

:::info IMPORTANT

`callback_url` 必须是路由的 URI。具体细节可查看下方内容，进行相关配置的理解。

:::

## 启用插件

你可以在特定路由上启用该插件，具体操作如下所示：

```shell
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
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

一旦你启用了该插件，访问该路线的新用户将会首先被 `authz-casdoor` 插件处理，并被重定向到Casdoor 登录页面。

成功登录后，Casdoor 会将该用户重定向到 `callback_url`，并指定 GET 参数的 `code` 和 `state`。该插件还将请求一个访问 Token，并确认用户是否真正登录了。该过程只运行一次，后续请求将不会被此打断。

上述操作完成后，用户就会被重定向到他们本想访问的原始 URL 页面。

## 禁用插件

当你需要禁用 `authz-Casdoor` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org:80": 1
        }
    }
}'
```