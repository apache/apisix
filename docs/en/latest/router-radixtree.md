---
Title: Router Radixtree
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

### What is Libradixtree?

[Libradixtree](https://github.com/api7/lua-resty-radixtree) is an adaptive radix tree that is implemented in Lua for OpenResty and it is based on FFI for [rax](https://github.com/antirez/rax). APISIX uses libradixtree as a route dispatching library.

### How to use Libradixtree in APISIX?

There are several ways to use Libradixtree in APISIX. Let's take a look at a few examples and have an intuitive understanding.

#### 1. Full match

```
/blog/foo
```

It will only match the full path `/blog/foo`.

#### 2. Prefix matching

```
/blog/bar*
```

It will match the path with the prefix `/blog/bar`. For example, `/blog/bar/a`,
`/blog/bar/b`, `/blog/bar/c/d/e`, `/blog/bar` etc.

#### 3. Match priority

Full match has a higher priority than deep prefix matching.

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

1. Different routes have the same `uri` but different `priority` field

Create two routes with different `priority` values ​​(the larger the value, the higher the priority).

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

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

Test:

```shell
curl http://127.0.0.1:1980/hello
1980
```

All requests will only hit the route of port `1980` because it has a priority of 3 while the route with the port of `1981` has a priority of 2.

2. Different routes have the same `uri` but different matching conditions

To understand this, look at the example of setting host matching rules:

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

If the `host` rule matches, the request hits the corresponding upstream, and if the `host` does not match, the request returns a 404 message.

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

By default, an URL-encoded slash (`%2F`) inside a parameter is decoded by Nginx
into a real `/` before route matching, so a request like `/blog/cat%2Fdog` is
treated as `/blog/cat/dog` and does not match `/blog/:name`. To keep `%2F`
encoded during matching (so it is treated as part of the parameter value rather
than a path separator), enable `match_uri_encoded_slash`:

```yaml
apisix:
    match_uri_encoded_slash: true
    router:
        http: 'radixtree_uri_with_parameter'
```

With this enabled, `/blog/cat%2Fdog` matches `/blog/:name` with `name` being
`cat%2Fdog`. The encoded slash is kept only for route matching and parameter
capture: plugins in the rewrite/access phases still read the normalized
(decoded) URI from `ctx.var.uri`. The request line nginx forwards to the
upstream is the original one, so the upstream receives `%2F` unchanged.

This option is global and changes how every route is matched. Because the
matching URI keeps `%2F` encoded, an exact route such as `/blog/cat/dog` will no
longer match a request like `/blog/cat%2Fdog` that used to match after Nginx
decoded the slash. Enable it only when you rely on `%2F` inside path parameters.

To stay safe, APISIX does not re-implement Nginx's URI normalization. It keeps
`%2F` encoded only when a plain full decode of the request path already equals
the normalized `$uri` — i.e. when Nginx applied nothing beyond percent-decoding.
If the request also required normalization (dot segments such as `..%2F..%2F` or
`%2e%2e`, merged consecutive slashes, an absolute-form request line, etc.), the
matching URI falls back to the normalized `$uri`. Such requests therefore never
become an encoded-slash match and cannot bypass route rules via path traversal.

The kept slash is always normalized to upper-case `%2F`, and radixtree compares
byte-for-byte, so a route whose URI is authored with a lower-case `%2f` (e.g.
`/blog/a%2fb`) will not match. Write the encoded slash as upper-case `%2F` in
route URIs.

This option gives way to `delete_uri_tail_slash` and `normalize_uri_like_servlet`:
the equivalence check compares against the URI those options already produced, so
when either actually rewrites the URI (a stripped trailing slash, a servlet-style
`;` parameter) the check no longer holds and the request falls back to normal
matching without keeping `%2F`. The fallback is safe; the encoded-slash match
simply does not apply to such requests.

### How to filter route by Nginx built-in variable?

Nginx provides a variety of built-in variables that can be used to filter routes based on certain criteria. Here is an example of how to filter routes by Nginx built-in variables:

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

This route will require the request header `host` equal `iresty.com`, request cookie key `_device_id` equal `a66f0cdc4ba2df8c096f74c9110163a9` etc. You can learn more at [radixtree-new](https://github.com/api7/lua-resty-radixtree#new).

### How to filter route by POST form attributes?

APISIX supports filtering route by POST form attributes with `Content-Type` = `application/x-www-form-urlencoded`.

We can define the following route:

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "methods": ["POST", "GET"],
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

The route will be matched when the POST form contains `name=json`.

### How to filter route by GraphQL attributes?

APISIX can handle HTTP GET and POST methods. At the same time, the request body can be a GraphQL query string or JSON-formatted content.

APISIX supports filtering routes by some attributes of GraphQL. Currently, we support:

* graphql_operation
* graphql_name
* graphql_root_fields

For instance, with GraphQL like this:

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

Where

* The `graphql_operation` is `query`
* The `graphql_name` is `getRepo`,
* The `graphql_root_fields` is `["owner", "repo"]`

We can filter such route with:

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

We can verify GraphQL matches in the following three ways:

1. GraphQL query strings

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

2. JSON format

```shell
$ curl -H 'content-type: application/json' -X POST \
http://127.0.0.1:9080/graphql --data '{"query": "query getRepo { owner {name } repo {created}}"}'
```

3. Try `GET` request match

```shell
$ curl -H 'content-type: application/graphql' -X GET \
"http://127.0.0.1:9080/graphql?query=query getRepo { owner {name } repo {created}}" -g
```

To prevent spending too much time reading invalid GraphQL request body, we only read the first 1 MiB
data from the request body. This limitation is configured via:

```yaml
graphql:
  max_size: 1048576

```

If you need to pass a GraphQL body which is larger than the limitation, you can increase the value in `conf/config.yaml`.

### How to filter route by POST request JSON body?

APISIX supports filtering route by POST form attributes with `Content-Type` = `application/json`.

We can define the following route:

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "methods": ["POST"],
    "uri": "/_post",
    "vars": [
        ["post_arg.name", "==", "xyz"]
    ],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

It will match the following POST request

```shell
curl -X POST http://127.0.0.1:9180/_post \
  -H "Content-Type: application/json" \
  -d '{"name":"xyz"}'
```

We can also filter by complex queries like the example below:

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "methods": ["POST"],
    "uri": "/_post",
    "vars": [
         ["post_arg.messages[*].content[*].type","has","image_url"]
    ],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

It will match the following POST request

```shell
curl -X POST http://127.0.0.1:9180/_post \
  -H "Content-Type: application/json" \
  -d '{
  "model": "deepseek",
  "messages": [
    {
      "role": "system",
      "content": [
        {
          "text": "You are a mathematician",
          "type": "text"
        },
        {
          "text": "You are a mathematician",
          "type": "image_url"
        }
      ]
    }
  ]
}'

```

:::note

Matching `post_arg.*` against JSON or multipart bodies requires APISIX to read and parse the
request body during route matching. To avoid exhausting worker memory on large bodies, the read
is capped by `apisix.max_post_args_readable_size` in `config.yaml` (default `64` MB). Bodies larger
than this cap are not matched. Set it to `0` to disable the limit.

:::
