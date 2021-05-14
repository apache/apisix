---
title: redirect
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

URI 重定向插件。

### 参数

| Name          | Type    | Requirement | Default | Valid      | Description                                                                                                                                                                                                                   |
| ------------- | ------- | ----------- | ------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| http_to_https | boolean | 可选        | false   |            | 当设置为 `true` 并且请求是 http 时，会自动 301 重定向为 https，uri 保持不变                                                                                                                                                   |
| uri           | string  | 可选        |         |            | 可以包含 Nginx 变量的 URI，例如：`/test/index.html`, `$uri/index.html`。你可以通过类似于 `$ {xxx}` 的方式引用变量，以避免产生歧义，例如：`${uri}foo/index.html`。若你需要保留 `$` 字符，那么使用如下格式：`/\$foo/index.html` |
| regex_uri | array[string] | 可选        |         |                   | 转发到上游的新 `uri` 地址, 使用正则表达式匹配来自客户端的 `uri`，当匹配成功后使用模板替换发送重定向到客户端, 未匹配成功时将客户端请求的 `uri` 转发至上游。`uri` 和 `regex_uri` 不可以同时存在。例如：["^/iresty/(.*)/(.*)/(.*)","/$1-$2-$3"] 第一个元素代表匹配来自客户端请求的 `uri` 正则表达式，第二个元素代表匹配成功后发送重定向到客户端的 `uri` 模板。 |
| ret_code      | integer | 可选        | 302     | [200, ...] | 请求响应码                                                                                                                                                                                                                    |
| encode_uri    | boolean | 可选        | false   |       | 当设置为 `true` 时，对返回的 `Location` header进行编码，编码格式参考 [RFC3986](https://datatracker.ietf.org/doc/html/rfc3986) |

`http_to_https`，`uri` 或 `regex_uri` 三个中只能配置一个。

### 示例

#### 启用插件

下面是一个基本实例，为特定路由启用 `redirect` 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

我们可以在新的 URI 中使用 Nginx 内置的任意变量：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

#### 测试

测试示例基于上述例子：

```shell
$ curl http://127.0.0.1:9080/test/index.html -i
HTTP/1.1 301 Moved Permanently
Date: Wed, 23 Oct 2019 13:48:23 GMT
Content-Type: text/html
Content-Length: 166
Connection: keep-alive
Location: /test/default.html

...
```

我们可以检查响应码和响应头中的 `Location` 参数，它表示该插件已启用。

```

下面是一个实现 http 到 https 跳转的示例：
```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "redirect": {
            "http_to_https": true
        }
    }
}'
```

#### 禁用插件

移除插件配置中相应的 JSON 配置可立即禁用该插件，无需重启服务：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

这时该插件已被禁用。
