---
title: APISIX
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

## Apache APISIX : Software Architecture

![flow-software-architecture](../../../assets/images/flow-software-architecture.png)

Apache APISIX is a dynamic, real-time, high-performance cloud-native API gateway. It is built on top of Nginx + ngx_lua technology and leverages the power offered by luajit.

APISIX is divided into two main parts, one is the APISIX core, including Lua plugin runtime, multi-language plugin runtime, WASM plug-in runtime, etc.; the other is a variety of feature-rich built-in plugins, including observability, security, traffic control, etc.

In the APISIX core, it's provide some important functions such as route matching, load balancing, service discovery, Admin API, and basic modules such as configuration management, etc. In addition, the APISIX plugin runtime is also included, providing a runtime framework for native Lua plugins, a runtime framework for multilingual plugins, and an experimental WASM plugin runtime, etc. The APISIX multilingual plugin runtime provides support for many different other languages, such as Golang, Java, Python, JS, etc.

APISIX also has various built-in plugins covering various areas of API gateways, such as authentication, security, observability, traffic management, multi-protocol access, etc. The current APISIX built-in plugins are implemented in native Lua. For their introduction and usage, please check their plugin documentation.

## Plugin Loading Process

![flow-load-plugin](../../../assets/images/flow-load-plugin.png)

## Plugin Hierarchy Structure

![flow-plugin-internal](../../../assets/images/flow-plugin-internal.png)
