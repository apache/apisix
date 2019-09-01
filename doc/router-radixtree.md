# libradixtree

### what's libradixtree?
[libradixtree](https://github.com/iresty/lua-resty-radixtree), adaptive radix trees implemented in Lua for OpenResty.

APISIX using [libradixtree](https://github.com/iresty/lua-resty-radixtree) as route dispatching library.

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
