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

# libr3

### what's libr3?
[libr3](https://github.com/c9s/r3) is a high-performance path dispatching library. It compiles your route paths into a prefix tree (trie).

APISIX using [lua-resty-libr3](https://github.com/iresty/lua-resty-libr3) as route dispatching library.

### How to use libr3 in APISIX?
libr3 supports PCRE(Perl Compatible Regular Expressions), so you can use route flexibly.

Let's take a look at a few examples and have an intuitive understanding.

1. default regular expression

`/blog/post/{id}`

there is not regular expression included, and `[^/]+` will be the default
regular expression of `id`.

So `/blog/post/{id}` is equivalent to `/blog/post/{id:[^/]+}`.

2. match all uris

`/{:.*}`

`/` matches root uri, and `.*` matches any character (except for line terminators).

`:` means is an anonymous match, for example the uri is `/blog/post/1`, the libr3 will return `[/blog/post/1]` if pattern is `/{:.*}`, and return `{"uri":"/blog/post/1"}` if pattern is `/{uri:.*}`.

3. match number

`/blog/post/{id:\d+}`

for example the uri is `/blog/post/1`, libr3 will return `{"id":"1"}`.

4. match characters

`/blog/post/{name:\w+}`

for example the uri is `/blog/post/foo`, libr3 will return `{"name":"foo"}`.

5. match multiple uri segments

`/blog/post/{name:\w+}/{id:\d+}`

for example the uri is `/blog/post/foo/12`, libr3 will return `{"name":"foo", "id":"12"}`.

`/blog/post/{:\w+}/{id:\d+}`

for example the uri is `/blog/post/foo/12`, libr3 will return `{"1":"foo", "id":"12"}`.

### How to filter route by Nginx builtin variable
libr3 can not support Nginx builtin variable, http headers and uri args now,
you can use [radixtree](route-radixtree.md) instead.

