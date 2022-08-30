---
title: ua-restriction
keywords:
  - APISIX
  - API Gateway
  - UA restriction
description: 本文介绍了 Apache APISIX ua-restriction 插件的使用方法，通过该插件可以将指定的 User-Agent 列入白名单或黑名单来限制对服务或路由的访问。
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

`ua-restriction` 插件可以通过将指定 `User-Agent` 列入白名单或黑名单的方式来限制对服务或路由的访问。

一种常见的场景是用来设置爬虫规则。`User-Agent` 是客户端在向服务器发送请求时的身份标识，用户可以将一些爬虫程序的请求头列入 `ua-restriction` 插件的白名单或黑名单中。

## 属性

| 名称    | 类型          | 必选项 | 默认值 | 有效值 | 描述                             |
| --------- | ------------- | ------ | ------ | ------ | -------------------------------- |
| allowlist | array[string] | 否   |        |        | 加入白名单的 `User-Agent`。 |
| denylist  | array[string] | 否   |        |        | 加入黑名单的 `User-Agent`。 |
| message | string  | 否   | "Not allowed" | [1, 1024] | 当未允许的 `User-Agent` 访问时返回的信息。 |
| bypass_missing | boolean       | 否    | false   |       | 当设置为 `true` 时，如果 `User-Agent` 请求头不存在或格式有误时，将绕过检查。 |

:::note

`allowlist` 和 `denylist` 可以同时启用。同时启用时，插件会根据 `User-Agent` 先检查 `allowlist`，再检查 `denylist`。

:::

## 启用插件

以下示例展示了如何在指定路由上启用并配置 `ua-restriction` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "ua-restriction": {
            "bypass_missing": true,
             "allowlist": [
                 "my-bot1",
                 "(Baiduspider)/(\\d+)\\.(\\d+)"
             ],
             "denylist": [
                 "my-bot2",
                 "(Twitterspider)/(\\d+)\\.(\\d+)"
             ]
        }
    }
}'
```

当未允许的 `User-Agent` 访问时，默认返回 `{"message":"Not allowed"}`。如果你想使用自定义的 `message`，可以在 `plugins` 部分进行配置：

```json
"plugins": {
    "ua-restriction": {
        "denylist": [
            "my-bot2",
            "(Twitterspider)/(\\d+)\\.(\\d+)"
        ],
        "message": "Do you want to do something bad?"
    }
}
```

## 测试插件

通过上述命令启用插件后，你可以先发起一个简单的请求测试：

```shell
curl http://127.0.0.1:9080/index.html -i
```

返回的 HTTP 响应头中带有 `200` 状态码，代表请求成功：

```shell
HTTP/1.1 200 OK
...
```

接下来，请求的同时指定处于 `denylist` 中的 `User-Agent`，如 `Twitterspider/2.0`：

```shell
curl http://127.0.0.1:9080/index.html --header 'User-Agent: Twitterspider/2.0'
```

返回的 HTTP 响应头中带有 `403` 状态码，请求失败，代表插件生效：

```shell
HTTP/1.1 403 Forbidden
...
{"message":"Not allowed"}
```

## 禁用插件

当你需要禁用 `ua-restriction` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
