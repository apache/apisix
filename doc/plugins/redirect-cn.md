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

[English](redirect.md)

# redirect

URI 重定向插件。

### 参数

|名称    |必须|描述|
|------- |-----|------|
|uri     |是，与 `http_to_https` 二选一| 可以包含 Nginx 变量的 URI，例如：`/test/index.html`, `$uri/index.html`。你可以通过类似于 `$ {xxx}` 的方式引用变量，以避免产生歧义，例如：`${uri}foo/index.html`。若你需要保留 `$` 字符，那么使用如下格式：`/\$foo/index.html`。|
|ret_code|否，只和 `uri` 配置使用。|请求响应码，默认值为 `302`。|
|http_to_https|是，与 `uri` 二选一|布尔值，默认是 `false`。当设置为 `ture` 并且请求是 http 时，会自动 301 重定向为 https，uri 保持不变|

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
