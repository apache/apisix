---
title: referer-restriction
keywords:
  - APISIX
  - API 网关
  - Referer restriction
description: 本文介绍了 Apache APISIX referer-restriction 插件的使用方法，通过该插件可以将 referer 请求头中的域名加入黑名单或者白名单来限制其对服务或路由的访问。
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

`referer-restriction` 插件允许用户将 `Referer` 请求头中的域名列入白名单或黑名单来限制该域名对服务或路由的访问。

## 属性

| 名称    | 类型          | 必选项 | 默认值 | 有效值 | 描述                             |
| --------- | ------------- | ------ | ------ | ------ | -------------------------------- |
| whitelist | array[string] | 否    |         |       | 白名单域名列表。域名开头可以用 `*` 作为通配符。 |
| blacklist | array[string] | 否    |         |       | 黑名单域名列表。域名开头可以用 `*` 作为通配符。 |
| message | string | 否    | "Your referer host is not allowed" | [1, 1024] | 在未允许访问的情况下返回的信息。 |
| bypass_missing  | boolean       | 否    | false   |       | 当设置为 `true` 时，如果 `Referer` 请求头不存在或格式有误，将绕过检查。 |

:::info IMPORTANT

`whitelist` 和 `blacklist` 属性无法同时在同一个服务或路由上使用，只能使用其中之一。

:::

## 启用插件

以下示例展示了如何在特定路由上启用 `referer-restriction` 插件，并配置 `whitelist` 和 `bypass_missing` 属性：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "referer-restriction": {
            "bypass_missing": true,
            "whitelist": [
                "xx.com",
                "*.xx.com"
            ]
        }
    }
}'
```

## 测试插件

通过上述命令启用插件后，你可以在请求中添加 `Referer: http://xx.com/x` 测试插件：

```shell
curl http://127.0.0.1:9080/index.html -H 'Referer: http://xx.com/x'
```

返回的 HTTP 响应头中带有 `200` 状态码则表示访问成功：

```shell
HTTP/1.1 200 OK
...
```

接下来，将请求设置为 `Referer: http://yy.com/x`：

```shell
curl http://127.0.0.1:9080/index.html -H 'Referer: http://yy.com/x'
```

返回的 HTTP 响应头中带有 `403` 状态码，并在响应体中带有 `message` 属性值，代表访问被阻止：

```shell
HTTP/1.1 403 Forbidden
...
{"message":"Your referer host is not allowed"}
```

因为启用插件时会将属性 `bypass_missing` 设置为 `true`，所以未指定 `Refer` 请求头的请求将跳过检查：

```shell
curl http://127.0.0.1:9080/index.html
```

返回的 HTTP 响应头中带有 `200` 状态码，代表访问成功：

```shell
HTTP/1.1 200 OK
...
```

## 删除插件

当你需要删除该插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
