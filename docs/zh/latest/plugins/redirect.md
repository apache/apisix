---
title: redirect
keywords:
  - APISIX
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

| Name          | Type    | Requirement | Default | Valid      | Description                                                                                                                                                                                                                   |
| ------------- | ------- | ----------- | ------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| http_to_https | boolean | 可选        | false   |            | 当设置为 `true` 并且请求是 http 时，会自动 301 重定向为 https，uri 保持不变                                                                                                                                                   |
| uri           | string  | 可选        |         |            | 可以包含 Nginx 变量的 URI，例如：`/test/index.html`, `$uri/index.html`。你可以通过类似于 `$ {xxx}` 的方式引用变量，以避免产生歧义，例如：`${uri}foo/index.html`。若你需要保留 `$` 字符，那么使用如下格式：`/\$foo/index.html` |
| regex_uri | array[string] | 可选        |         |                   | 转发到上游的新 `uri` 地址, 使用正则表达式匹配来自客户端的 `uri`，当匹配成功后使用模板替换发送重定向到客户端, 未匹配成功时将客户端请求的 `uri` 转发至上游。`uri` 和 `regex_uri` 不可以同时存在。例如：["^/iresty/(.*)/(.*)/(.*)","/$1-$2-$3"] 第一个元素代表匹配来自客户端请求的 `uri` 正则表达式，第二个元素代表匹配成功后发送重定向到客户端的 `uri` 模板。 |
| ret_code      | integer | 可选        | 302     | [200, ...] | 请求响应码                                                                                                                                                                                                                    |
| ret_port      | integer | 可选        | 443     | [1, 65535] | 重定向服务器端口，仅在开启 `http_to_https` 有效。|
| encode_uri    | boolean | 可选        | false   |       | 当设置为 `true` 时，对返回的 `Location` header进行编码，编码格式参考 [RFC3986](https://datatracker.ietf.org/doc/html/rfc3986) |
| append_query_string    | boolean | optional    | false   |       | 当设置为 `true` 时，将请求url的query部分添加到Location里。如果在 `uri` 或 `regex_uri` 中配置了query, 那么请求的query会被追加在这个query后，以 `&` 分隔。 注意：如果已经处理了query，比如使用了nginx变量 `$request_uri`，那么启用此功能会造成query重复 |

:::note

`http_to_https`、`uri` 和 `regex_uri` 只能配置其中一个属性。

:::

## 启用插件

以下示例展示了如何在指定路由中启用 `redirect` 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
curl http://127.0.0.1:9080/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
curl http://127.0.0.1:9080/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "redirect": {
            "http_to_https": true,
            "ret_port": 9443
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

## 禁用插件

当你需要禁用 `redirect` 插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
