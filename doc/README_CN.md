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
[English](README.md)

Reference document
==================

* [APISIX 说明](../README_CN.md)
* [架构设计](architecture-design-cn.md)
* [压力测试](benchmark-cn.md)
* [搭建开发环境](dev-manua-cnl.md)
* [安装依赖](install-dependencies.md): How to install dependencies for different OS.
* [健康检查](health-check.md): Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability.
* Router(路由)
    * [radixtree](router-radixtree.md)
    * [r3](router-r3.md)
* [独立运行模型](stand-alone-cn.md): Supports to load route rules from local yaml file, it is more friendly such as under the kubernetes(k8s).
* [TCP/UDP 动态代理](stream-proxy-cn.md)
* [管理 API](admin-api-cn.md)
* [变更日志](../CHANGELOG_CN.md)
* [代码风格](../CODE_STYLE.md)
* [常见问答](../FAQ_CN.md)

插件
===

* [插件热加载](plugins-cn.md)：无需重启服务，完成插件热加载或卸载。
* [HTTPS](https-cn.md)：根据 TLS 扩展字段 SNI(Server Name Indication) 动态加载证书。
* [动态负载均衡](architecture-design-cn.md#upstream)：跨多个上游服务的动态负载均衡，目前已支持 round-robin 和一致性哈希算法。
* [key-auth](plugins/key-auth-cn.md)：基于 Key Authentication 的用户认证。
* [JWT-auth](plugins/jwt-auth-cn.md)：基于 [JWT](https://jwt.io/) (JSON Web Tokens) Authentication 的用户认证。
* [limit-count](plugins/limit-count-cn.md)：基于“固定窗口”的限速实现。
* [limit-req](plugins/limit-req-cn.md)：基于漏桶原理的请求限速实现。
* [limit-conn](plugins/limit-conn-cn.md)：限制并发请求（或并发连接）。
* [prometheus](plugins/prometheus-cn.md)：以 Prometheus 格式导出 APISIX 自身的状态信息，方便被外部 Prometheus 服务抓取。
* [OpenTracing](plugins/zipkin-cn.md)：支持 Zikpin 和 Apache SkyWalking。
* [grpc-transcode](plugins/grpc-transcoding-cn.md)：REST <--> gRPC 转码。
* [serverless](plugins/serverless-cn.md)：允许在 APISIX 中的不同阶段动态运行 Lua 代码。
* [ip-restriction](plugins/ip-restriction-cn.md): IP 黑白名单。
* openid-connect
* [redirect](plugins/redirect-cn.md): URI 重定向。
* [response-rewrite](plugins/response-rewrite-cn.md): 支持自定义修改返回内容的 `status code`、`body`、`headers`。
