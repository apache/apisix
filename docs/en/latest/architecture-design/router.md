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

A distinguishing feature of APISIX from other API gateways is that it allows users to choose different routers to better match free services, making the best choice between performance and freedom.

Set the route that best suits your business needs in the local configuration `conf/config.yaml`.

- `apisix.router.http`: HTTP Request Route。

  - `radixtree_uri`: (Default) only use `uri` as the primary index. Support for full and deep prefix matching based on the `radixtree` engine, see [How to use router-radixtree](router-radixtree.md).
    - `Absolute match`: Complete match for the given `uri`, such as `/foo/bar`,`/foo/glo`.
    - `Prefix match`: Use `*` at the end to represent the given `uri` as a prefix match. For example, `/foo*` allows matching `/foo/`, `/foo/a` and `/foo/b`.
    - `match priority`: first try absolute match, if you can't hit absolute match, try prefix match.
    - `Any filter attribute`: Allows you to specify any Nginx built-in variable as a filter, such as URL request parameters, request headers, cookies, and so on.
  - `radixtree_uri_with_parameter`: Like `radixtree_uri` but also support parameter match.
  - `radixtree_host_uri`: Use `host + uri` as the primary index (based on the `radixtree` engine), matching both host and URL for the current request.

- `apisix.router.ssl`: SSL loads the matching route.
  - `radixtree_sni`: (Default) Use `SNI` (Server Name Indication) as the primary index (based on the radixtree engine).
