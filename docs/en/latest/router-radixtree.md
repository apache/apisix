---
title: Router radixtree
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

### what's libradixtree?

[libradixtree](https://github.com/iresty/lua-resty-radixtree), adaptive radix trees implemented in Lua for OpenResty.

APISIX using libradixtree as route dispatching library.

### How to use libradixtree in APISIX?

This is Lua-Openresty implementation library base on FFI for [rax](https://github.com/antirez/rax).

Let's take a look at a few examples and have an intuitive understanding.

#### 1. Full match

```
/blog/foo
```

It will only match `/blog/foo`.

#### 2. Prefix matching

```
/blog/bar*
```

It will match the path with the prefix `/blog/bar`, eg: `/blog/bar/a`,
`/blog/bar/b`, `/blog/bar/c/d/e`, `/blog/bar` etc.

#### 3. Match priority

Full match -> Deep prefix matching.

Here are the rules:

```
/blog/foo/*
/blog/foo/a/*
/blog/foo/c/*
/blog/foo/bar
```

| path | Match result |
|------|--------------|
|/blog/foo/bar | `/blog/foo/bar` |
|/blog/foo/a/b/c | `/blog/foo/a/*` |
|/blog/foo/c/d | `/blog/foo/c/*` |
|/blog/foo/gloo | `/blog/foo/*` |
|/blog/bar | not match |

#### 4. Different routes have the same `uri`

When different routes have the same `uri`, you can set the priority field of the route to determine which route to match first, or add other matching rules to distinguish different routes.

Note: In the matching rules, the `priority` field takes precedence over other rules except `uri`.

1. Different routes have the same `uri` and set the `priority` field

Create two routes with different `priority` values ​​(the larger the value, the higher the priority).

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
$ curl http://127.0.0.1:9080/apisix/admin/routes/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Test:

```shell
curl http://127.0.0.1:1980/hello
1980
```

All requests only hit the route of port `1980`.

2. Different routes have the same `uri` and set different matching conditions

Here is an example of setting host matching rules:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
$ curl http://127.0.0.1:9080/apisix/admin/routes/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Test:

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

The `host` rule matches, the request hits the corresponding upstream, and the `host` does not match, the request returns a 404 message.

#### 5. Parameter match

When `radixtree_uri_with_parameter` is used, we can match routes with parameters.

For example, with configuration:

```yaml
apisix:
    router:
        http: 'radixtree_uri_with_parameter'
```

route like

```
/blog/:name
```

will match both `/blog/dog` and `/blog/cat`.

For more details, see https://github.com/api7/lua-resty-radixtree/#parameters-in-path.

### How to filter route by Nginx builtin variable

Please take a look at [radixtree-new](https://github.com/iresty/lua-resty-radixtree#new),
here is an simple example:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
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
            "39.97.63.215:80": 1
        }
    }
}'
```

This route will require the request header `host` equal `iresty.com`, request cookie key `_device_id` equal `a66f0cdc4ba2df8c096f74c9110163a9` etc.

### How to filter route by graphql attributes

APISIX supports filtering route by some attributes of graphql. Currently we support:

* graphql_operation
* graphql_name
* graphql_root_fields

For instance, with graphql like this:

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

* The `graphql_operation` is `query`
* The `graphql_name` is `getRepo`,
* The `graphql_root_fields` is `["owner", "repo"]`

We can filter such route out with:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "methods": ["POST"],
    "uri": "/_graphql",
    "vars": [
        ["graphql_operation", "==", "query"],
        ["graphql_name", "==", "getRepo"],
        ["graphql_root_fields", "has", "owner"]
    ],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

To prevent spending too much time reading invalid graphql request body, we only read the first 1 MiB
data from the request body. This limitation is configured via:

```yaml
graphql:
  max_size: 1048576

```

If you need to pass a graphql body which is larger than the limitation, you can increase the value in `conf/config.yaml`.
