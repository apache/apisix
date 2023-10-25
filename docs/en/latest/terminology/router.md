---
title: Router
keywords:
  - API Gateway
  - Apache APISIX
  - Router
description: This article describes how to choose a router for Apache APISIX.
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

## Description

A distinguishing feature of Apache APISIX from other API gateways is that it allows you to choose different Routers to better match free services, giving you the best choices for performance and freedom.

You can set the Router that best suits your needs in your configuration file `conf/config.yaml`.

## Configuration

A Router can have the following configurations:

- `apisix.router.http`: The HTTP request route. It can take the following values:

  - `radixtree_uri`: Only use the `uri` as the primary index. To learn more about the support for full and deep prefix matching, check [How to use router-radixtree](../router-radixtree.md).
    - `Absolute match`: Match completely with the given `uri` (`/foo/bar`, `/foo/glo`).
    - `Prefix match`: Match with the given prefix. Use `*` to represent the given `uri` for prefix matching. For example, `/foo*` can match with `/foo/`, `/foo/a` and `/foo/b`.
    - `match priority`: First try an absolute match, if it didn't match, try prefix matching.
    - `Any filter attribute`: This allows you to specify any Nginx built-in variable as a filter, such as URL request parameters, request headers, and cookies.
  - `radixtree_uri_with_parameter`: Like `radixtree_uri` but also supports parameter match.
  - `radixtree_host_uri`: (Default) Matches both host and URI of the request. Use `host + uri` as the primary index (based on the `radixtree` engine).

:::note

In version 3.2 and earlier, APISIX used `radixtree_uri` as the default Router. `radixtree_uri` has better performance than `radixtree_host_uri`, so if you have higher performance requirements and can live with the fact that `radixtree_uri` only use the `uri` as the primary index, consider continuing to use `radixtree_uri` as the default Router.

:::

- `apisix.router.ssl`: SSL loads the matching route.
  - `radixtree_sni`: (Default) Use `SNI` (Server Name Indication) as the primary index (based on the radixtree engine).
