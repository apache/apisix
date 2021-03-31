---
title: Router
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

APISIX 区别于其他 API 网关的一大特点是允许用户选择不同 Router 来更好匹配自由业务，在性能、自由之间做最适合选择。

在本地配置 `conf/config.yaml` 中设置最符合自身业务需求的路由。

- `apisix.router.http`: HTTP 请求路由。

  - `radixtree_uri`: （默认）只使用 `uri` 作为主索引。基于 `radixtree` 引擎，支持全量和深前缀匹配，更多见 [如何使用 router-radixtree](../../../zh/latest/router-radixtree.md)。
    - `绝对匹配`：完整匹配给定的 `uri` ，比如 `/foo/bar`，`/foo/glo`。
    - `前缀匹配`：末尾使用 `*` 代表给定的 `uri` 是前缀匹配。比如 `/foo*`，则允许匹配 `/foo/`、`/foo/a`和`/foo/b`等。
    - `匹配优先级`：优先尝试绝对匹配，若无法命中绝对匹配，再尝试前缀匹配。
    - `任意过滤属性`：允许指定任何 Nginx 内置变量作为过滤条件，比如 URL 请求参数、请求头、cookie 等。
  - `radixtree_uri_with_parameter`: 同 `radixtree_uri` 但额外有参数匹配的功能。
  - `radixtree_host_uri`: 使用 `host + uri` 作为主索引（基于 `radixtree` 引擎），对当前请求会同时匹配 host 和 uri，支持的匹配条件与 `radixtree_uri` 基本一致。

- `apisix.router.ssl`: SSL 加载匹配路由。
  - `radixtree_sni`: （默认）使用 `SNI` (Server Name Indication) 作为主索引（基于 radixtree 引擎）。
