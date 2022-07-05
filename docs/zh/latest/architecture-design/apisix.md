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

## 软件架构

![软件架构](../../../assets/images/flow-software-architecture.png)

Apache APISIX 是一个动态、实时、高性能的云原生 API 网关。它构建于 NGINX + ngx_lua 的技术基础之上，充分利用了 LuaJIT 所提供的强大性能。 [为什么 Apache APISIX 选择 NGINX+Lua 技术栈？](https://apisix.apache.org/zh/blog/2021/08/25/why-apache-apisix-chose-nginx-and-lua/)。

APISIX 主要分为两个部分：

1. APISIX 核心：包括 Lua 插件、多语言插件运行时（Plugin Runner）、Wasm 插件运行时等；
2. 功能丰富的各种内置插件：包括可观测性、安全、流量控制等。

APISIX 在其核心中，提供了路由匹配、负载均衡、服务发现、API 管理等重要功能，以及配置管理等基础性模块。除此之外，APISIX 插件运行时也包含其中，提供原生 Lua 插件的运行框架和多语言插件的运行框架，以及实验性的 Wasm 插件运行时等。APISIX 多语言插件运行时提供多种开发语言的支持，比如 Golang、Java、Python、JS 等。

APISIX 目前也内置了各类插件，覆盖了 API 网关的各种领域，如认证鉴权、安全、可观测性、流量管理、多协议接入等。当前 APISIX 内置的插件使用原生 Lua 实现，关于各个插件的介绍与使用方式，可以查看相关[插件文档](https://apisix.apache.org/docs/apisix/plugins/batch-requests)。

## 插件加载流程

![插件加载流程](../../../assets/images/flow-load-plugin.png)

## 插件内部结构

![插件内部结构](../../../assets/images/flow-plugin-internal.png)

## 配置 APISIX

通过修改本地 `conf/config.yaml` 文件，或者在启动 APISIX 时使用 `-c` 或 `--config` 添加文件路径参数 `apisix start -c <path string>`，完成对 APISIX 服务本身的基本配置。

比如修改 APISIX 默认监听端口为 8000，其他配置保持默认，在 `config.yaml` 中只需这样配置：

```yaml
apisix:
  node_listen: 8000 # APISIX listening port
```

比如指定 APISIX 默认监听端口为 8000，并且设置 etcd 地址为 `http://foo:2379`，
其他配置保持默认。在 `config.yaml` 中只需这样配置：

```yaml
apisix:
  node_listen: 8000 # APISIX listening port

etcd:
  host: "http://foo:2379" # etcd address
```

其他默认配置，可以在 `conf/config-default.yaml` 文件中看到，该文件是与 APISIX 源码强绑定，
**永远不要**手工修改 `conf/config-default.yaml` 文件。如果需要自定义任何配置，都应在 `config.yaml` 文件中完成。

_注意_ 不要手工修改 APISIX 自身的 `conf/nginx.conf` 文件，当服务每次启动时，`apisix`
会根据 `config.yaml` 配置自动生成新的 `conf/nginx.conf` 并自动启动服务。
