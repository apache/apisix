---
title: 路由 RadixTree
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

### 什么是 libradixtree？

[libradixtree](https://github.com/api7/lua-resty-radixtree), 是在 `Lua` 中为 `OpenResty` 实现的自适应
[基数树](https://zh.wikipedia.org/wiki/%E5%9F%BA%E6%95%B0%E6%A0%91) 。

`Apache APISIX` 使用 `libradixtree` 作为路由调度库。

### 如何在 Apache APISIX 中使用 libradixtree？

`libradixtree` 是基于 [rax](https://github.com/antirez/rax) 的 `lua-resty-*` 实现。

我们通过下面的示例可以有一个直观的理解。

#### 1. 完全匹配

```text
/blog/foo
```

此时只能匹配 `/blog/foo` 。

#### 2. 前缀匹配

```text
/blog/bar*
```

它将匹配带有前缀 `/blog/bar` 的路径，
例如： `/blog/bar/a` 、 `/blog/bar/b` 、 `/blog/bar/c/d/e` 、 `/blog/bar` 等。

#### 3. 匹配优先级

完全匹配 -> 深度前缀匹配

以下是规则：

```text
/blog/foo/*
/blog/foo/a/*
/blog/foo/c/*
/blog/foo/bar
```

| 路径            | 匹配结果        |
| --------------- | --------------- |
| /blog/foo/bar   | `/blog/foo/bar` |
| /blog/foo/a/b/c | `/blog/foo/a/*` |
| /blog/foo/c/d   | `/blog/foo/c/*` |
| /blog/foo/gloo  | `/blog/foo/*` |
| /blog/bar       | not match       |

#### 4. 不同的路由具有相同 `uri`

当不同的路由有相同的 `uri` 时，可以通过设置路由的 `priority` 字段来决定先匹配哪条路由，或者添加其他匹配规则来区分不同的路由。

注意：在匹配规则中， `priority` 字段优先于除 `uri` 之外的其他规则。

1、不同的路由有相同的 `uri` 并设置 `priority` 字段

创建两条 `priority` 值不同的路由（值越大，优先级越高）。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "priority": 3,
    "uri": "/hello"
}'
```

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/2 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
       "nodes": {
           "127.0.0.1:1981": 1
       },
       "type": "roundrobin"
    },
    "priority": 2,
    "uri": "/hello"
}'
```

测试：

```shell
curl http://127.0.0.1:1980/hello
1980
```

所有请求只到达端口 `1980` 的路由。

2、不同的路由有相同的 `uri` 并设置不同的匹配条件

以下是设置主机匹配规则的示例：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "hosts": ["localhost.com"],
    "uri": "/hello"
}'
```

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/2 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "upstream": {
       "nodes": {
           "127.0.0.1:1981": 1
       },
       "type": "roundrobin"
    },
    "hosts": ["test.com"],
    "uri": "/hello"
}'
```

测试：

```shell
$ curl http://127.0.0.1:9080/hello -H 'host: localhost.com'
1980
```

```shell
$ curl http://127.0.0.1:9080/hello -H 'host: test.com'
1981
```

```shell
$ curl http://127.0.0.1:9080/hello
{"error_msg":"404 Route Not Found"}
```

`host` 规则匹配，请求命中对应的上游，`host` 不匹配，请求返回 404 消息。

#### 5. 参数匹配

当使用 `radixtree_uri_with_parameter` 时，我们可以用参数匹配路由。

例如，使用配置：

```yaml
apisix:
  router:
    http: 'radixtree_uri_with_parameter'
```

示例：

```bash
/blog/:name
```

此时将匹配 `/blog/dog` 和 `/blog/cat`。

更多使用方式请参考：[lua-resty-radixtree#parameters-in-path](https://github.com/api7/lua-resty-radixtree/#parameters-in-path)

### 如何通过 Nginx 内置变量过滤路由

具体参数及使用方式请查看 [radixtree#new](https://github.com/api7/lua-resty-radixtree#new) 文档，下面是一个简单的示例：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/index.html",
    "vars": [
        ["http_host", "==", "iresty.com"],
        ["cookie_device_id", "==", "a66f0cdc4ba2df8c096f74c9110163a9"],
        ["arg_name", "==", "json"],
        ["arg_age", ">", "18"],
        ["arg_address", "~~", "China.*"]
    ],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

这个路由需要请求头 `host` 等于 `iresty.com`，
请求 cookie `_device_id` 等于 `a66f0cdc4ba2df8c096f74c9110163a9` 等。

### 如何通过 POST 表单属性过滤路由

APISIX 支持通过 POST 表单属性过滤路由，其中需要您使用 `Content-Type` = `application/x-www-form-urlencoded` 的 POST 请求。

我们可以定义这样的路由：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "methods": ["POST"],
    "uri": "/_post",
    "vars": [
        ["post_arg_name", "==", "json"]
    ],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

当 POST 表单中包含 `name=json` 的属性时，将匹配到路由。

### 如何通过 GraphQL 属性过滤路由

目前，APISIX 可以处理 HTTP GET 和 POST 方法。请求体正文可以是 GraphQL 查询字符串，也可以是 JSON 格式的内容。

APISIX 支持通过 GraphQL 的一些属性过滤路由。目前我们支持：

* graphql_operation
* graphql_name
* graphql_root_fields

例如，像这样的 GraphQL：

```graphql
query getRepo {
    owner {
        name
    }
    repo {
        created
    }
}
```

* `graphql_operation` 是 `query`
* `graphql_name` 是 `getRepo`，
* `graphql_root_fields` 是 `["owner", "repo"]`

我们可以用以下方法过滤掉这样的路由：

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "methods": ["POST", "GET"],
    "uri": "/graphql",
    "vars": [
        ["graphql_operation", "==", "query"],
        ["graphql_name", "==", "getRepo"],
        ["graphql_root_fields", "has", "owner"]
    ],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

我们可以通过以下三种方式分别去验证 GraphQL 匹配：

1. 使用 GraphQL 查询字符串

```shell
$ curl -H 'content-type: application/graphql' -X POST http://127.0.0.1:9080/graphql -d '
query getRepo {
    owner {
        name
    }
    repo {
        created
    }
}'
```

2. 使用 JSON 格式

```shell
$ curl -H 'content-type: application/json' -X POST \
http://127.0.0.1:9080/graphql --data '{"query": "query getRepo { owner {name } repo {created}}"}'
```

3. 尝试 `GET` 请求

```shell
$ curl -H 'content-type: application/graphql' -X GET \
"http://127.0.0.1:9080/graphql?query=query getRepo { owner {name } repo {created}}" -g
```

为了防止花费太多时间读取无效的 `GraphQL` 请求正文，我们只读取前 `1 MiB`
来自请求体的数据。此限制是通过以下方式配置的：

```yaml
graphql:
  max_size: 1048576
```

如果你需要传递一个大于限制的 GraphQL 查询语句，你可以增加 `conf/config.yaml` 中的值。
