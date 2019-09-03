# libradixtree

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


### How to filter route by Nginx builtin variable

Please take a look at [radixtree-new](https://github.com/iresty/lua-resty-radixtree#new),
here is an example:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -X PUT -i -d '
{
    "uri": "/index.html",
    "vars": ["http_host", "iresty.com", "cookie__device_id", "a66f0cdc4ba2df8c096f74c9110163a9", "arg_name", "jack"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

This route will require the request header `host` equal `iresty.com`, request cookie key `_device_id` equal `a66f0cdc4ba2df8c096f74c9110163a9` etc.
