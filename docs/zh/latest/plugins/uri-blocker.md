---
title: uri-blocker
keywords:
  - Apache APISIX
  - API 网关
  - URI Blocker
description: 本文介绍了 Apache APISIX uri-blocker 插件的基本信息及使用方法。
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

`uri-blocker` 插件通过指定一系列 `block_rules` 来拦截用户请求。

## 属性

| 名称          | 类型          | 必选项 | 默认值 | 有效值     | 描述                                                                |
| ------------- | ------------- | ------ | ------ | ---------- | ------------------------------------------------------------------- |
| block_rules   | array[string] | 是   |        |            | 正则过滤数组。它们都是正则规则，如果当前请求 URI 命中其中任何一个，则将响应代码设置为 `rejected_code` 以退出当前用户请求。例如：`["root.exe", "root.m+"]`。 |
| rejected_code | integer       | 否   | 403    | [200, ...] | 当请求 URI 命中 `block_rules` 中的任何一个时，将返回的 HTTP 状态代码。 |
| rejected_msg | string       | 否    |      | 非空 | 当请求 URI 命中 `block_rules` 中的任何一个时，将返回的 HTTP 响应体。 |
| case_insensitive | boolean       | 否    | false     |  | 是否忽略大小写。当设置为 `true` 时，在匹配请求 URI 时将忽略大小写。 |

## 启用插件

以下示例展示了如何在指定的路由上启用 `uri-blocker` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/*",
    "plugins": {
        "uri-blocker": {
            "block_rules": ["root.exe", "root.m+"]
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

## 测试插件

启用并配置插件后，使用 `curl` 命令尝试访问 `block_rules` 中指定文件的 URI：

```shell
curl -i http://127.0.0.1:9080/root.exe?a=a
```

如果发现返回了带有 `403` 状态码的 HTTP 响应头，则代表插件生效：

```shell
HTTP/1.1 403 Forbidden
Date: Wed, 17 Jun 2020 13:55:41 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 150
Connection: keep-alive
Server: APISIX web server
...
```

通过设置属性 `rejected_msg` 的值为 `access is not allowed`，将会收到包含如下信息的响应体：

```shell
...
{"error_msg":"access is not allowed"}
...
```

## 删除插件

当你需要禁用 `uri-blocker` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/*",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
