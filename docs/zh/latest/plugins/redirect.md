---
title: redirect
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Redirect
description: 本文介绍了关于 Apache APISIX `redirect` 插件的基本信息及使用方法。
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

`redirect` 插件可用于配置 URI 重定向。

## 属性

| 名称                  | 类型            | 必选项 | 默认值   | 有效值          | 描述                                                                                                                                                                                                  |
|---------------------|---------------|-----|-------|--------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| http_to_https       | boolean       | 否   | false | [true,false] | 当设置为 `true` 并且请求是 HTTP 时，它将被重定向具有相同 URI 和 301 状态码的 HTTPS，原 URI 的查询字符串也将包含在 Location 头中。                                                                                                                                           |
| uri                 | string        | 否   |       |              | 要重定向到的 URI，可以包含 NGINX 变量。例如：`/test/index.htm`，`$uri/index.html`，`${uri}/index.html`，`https://example.com/foo/bar`。如果你引入了一个不存在的变量，它不会报错，而是将其视为一个空变量。                                              |
| regex_uri           | array[string] | 否   |       |              | 将来自客户端的 URL 与正则表达式匹配并重定向。当匹配成功后使用模板替换发送重定向到客户端，如果未匹配成功会将客户端请求的 URI 转发至上游。和 `regex_uri` 不可以同时存在。例如：["^/iresty/(.)/(.)/(.*)","/$1-$2-$3"] 第一个元素代表匹配来自客户端请求的 URI 正则表达式，第二个元素代表匹配成功后发送重定向到客户端的 URI 模板。 |
| ret_code            | integer       | 否   | 302   | [200, ...]   | HTTP 响应码                                                                                                                                                                                            |
| encode_uri          | boolean       | 否   | false | [true,false] | 当设置为 `true` 时，对返回的 `Location` Header 按照 [RFC3986](https://datatracker.ietf.org/doc/html/rfc3986) 的编码格式进行编码。                                                                                          |
| append_query_string | boolean       | 否   | false | [true,false] | 当设置为 `true` 时，将原始请求中的查询字符串添加到 `Location` Header。如果已配置 `uri` 或 `regex_uri` 已经包含查询字符串，则请求中的查询字符串将附加一个`&`。如果你已经处理过查询字符串（例如，使用 NGINX 变量 `$request_uri`），请不要再使用该参数以避免重复。                                 |

:::note

* `http_to_https`、`uri` 和 `regex_uri` 只能配置其中一个属性。
* `http_to_https`、和 `append_query_string` 只能配置其中一个属性。
* 当开启 `http_to_https` 时，重定向 URL 中的端口将按如下顺序选取一个值（按优先级从高到低排列）
  * 从配置文件（`conf/config.yaml`）中读取 `plugin_attr.redirect.https_port`。
  * 如果 `apisix.ssl` 处于开启状态，读取 `apisix.ssl.listen` 并从中随机选一个 `port`。
  * 使用 443 作为默认 `https port`。

:::

## 启用插件

以下示例展示了如何在指定路由中启用 `redirect` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/test/index.html",
    "plugins": {
        "redirect": {
            "uri": "/test/default.html",
            "ret_code": 301
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

你也可以在新的 URI 中使用 NGINX 内置的任意变量：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/test",
    "plugins": {
        "redirect": {
            "uri": "$uri/index.html",
            "ret_code": 301
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

## 测试插件

通过上述命令启用插件后，可以使用如下命令测试插件是否启用成功：

```shell
curl http://127.0.0.1:9080/test/index.html -i
```

```
HTTP/1.1 301 Moved Permanently
Date: Wed, 23 Oct 2019 13:48:23 GMT
Content-Type: text/html
Content-Length: 166
Connection: keep-alive
Location: /test/default.html
...
```

通过上述返回结果，可以看到响应码和响应头中的 `Location` 参数，它表示该插件已启用。

以下示例展示了如何将 HTTP 重定向到 HTTPS：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "redirect": {
            "http_to_https": true
        }
    }
}'
```

基于上述例子进行测试：

```shell
curl http://127.0.0.1:9080/hello -i
```

```
HTTP/1.1 301 Moved Permanently
...
Location: https://127.0.0.1:9443/hello
...
```

## 删除插件

当你需要禁用 `redirect` 插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/test/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```
