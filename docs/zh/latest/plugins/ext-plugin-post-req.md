---
title: ext-plugin-post-req
keywords:
  - Apache APISIX
  - Plugin
  - ext-plugin-post-req
description: 本文介绍了关于 Apache APISIX `ext-plugin-post-req` 插件的基本信息及使用方法。
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

## 描述

`ext-plugin-post-req` 插件的功能与 `ext-plugin-pre-req` 插件的不同之处在于：`ext-plugin-post-req` 插件是在内置 Lua 插件执行之后且在请求到达上游之前工作。

你可以参考 [ext-plugin-pre-req](./ext-plugin-pre-req.md) 文档，学习如何配置和使用 `ext-plugin-post-req` 插件。
