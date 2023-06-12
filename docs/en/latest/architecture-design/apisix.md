---
title: Architecture
keywords:
  - API Gateway
  - Apache APISIX
  - APISIX architecture
description: Architecture of Apache APISIX—the Cloud Native API Gateway.
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

APISIX is built on top of Nginx and [ngx_lua](https://github.com/openresty/lua-nginx-module) leveraging the power offered by LuaJIT. See [Why Apache APISIX chose Nginx and Lua to build API Gateway?](https://apisix.apache.org/blog/2021/08/25/why-apache-apisix-chose-nginx-and-lua/).

![flow-software-architecture](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/flow-software-architecture.png)

APISIX has two main parts:

1. APISIX core, Lua plugin, multi-language Plugin runtime, and the WASM plugin runtime.
2. Built-in Plugins that adds features for observability, security, traffic control, etc.

The APISIX core handles the important functions like matching Routes, load balancing, service discovery, configuration management, and provides a management API. It also includes APISIX Plugin runtime supporting Lua and multilingual Plugins (Go, Java , Python, JavaScript, etc) including the experimental WASM Plugin runtime.

APISIX also has a set of [built-in Plugins](https://apisix.apache.org/docs/apisix/plugins/batch-requests) that adds features like authentication, security, observability, etc. They are written in Lua.

## Request handling process

The diagram below shows how APISIX handles an incoming request and applies corresponding Plugins:

![flow-load-plugin](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/flow-load-plugin.png)

## Plugin hierarchy

The chart below shows the order in which different types of Plugin are applied to a request:

![flow-plugin-internal](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/flow-plugin-internal.png)
