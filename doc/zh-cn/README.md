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
[English](../README.md)

参考文档
==================

* [APISIX 说明](../../README_CN.md)
* [架构设计](architecture-design.md)
* [压力测试](benchmark.md)
* [如何构建 Apache APISIX](how-to-build.md)
* [健康检查](health-check.md): 支持对上游节点的主动和被动健康检查，在负载均衡时自动过滤掉不健康的节点。
* Router(路由)
    * [radixtree](../router-radixtree.md)
    * [r3](router-r3.md)
* [独立运行模型](stand-alone.md): 支持从本地 yaml 格式的配置文件启动，更适合 Kubernetes(k8s) 体系。
* [TCP/UDP 动态代理](stream-proxy.md)
* [管理 API](admin-api.md)
* [变更日志](../../CHANGELOG_CN.md)
* [代码风格](../CODE_STYLE.md)
* [常见问答](../../FAQ_CN.md)

插件
===

* [插件热加载](plugins.md)：无需重启服务，完成插件热加载或卸载。
* [HTTPS](https.md)：根据 TLS 扩展字段 SNI(Server Name Indication) 动态加载证书。
* [动态负载均衡](architecture-design.md#upstream)：跨多个上游服务的动态负载均衡，目前已支持 round-robin 和一致性哈希算法。
* [key-auth](plugins/key-auth.md)：基于 Key Authentication 的用户认证。
* [JWT-auth](plugins/jwt-auth.md)：基于 [JWT](https://jwt.io/) (JSON Web Tokens) Authentication 的用户认证。
* [basic-auth](plugins/basic-auth.md)：基于 basic auth 的用户认证。
* [wolf-rbac](plugins/wolf-rbac.md) 基于 *RBAC* 的用户认证及授权。
* [limit-count](plugins/limit-count.md)：基于“固定窗口”的限速实现。
* [limit-req](plugins/limit-req.md)：基于漏桶原理的请求限速实现。
* [limit-conn](plugins/limit-conn.md)：限制并发请求（或并发连接）。
* [proxy-rewrite](plugins/proxy-rewrite.md): 支持自定义修改 proxy 到上游的信息。
* [prometheus](plugins/prometheus.md)：以 Prometheus 格式导出 APISIX 自身的状态信息，方便被外部 Prometheus 服务抓取。
* [OpenTracing](plugins/zipkin.md)：支持 Zikpin 和 Apache SkyWalking。
* [grpc-transcode](plugins/grpc-transcode.md)：REST <--> gRPC 转码。
* [serverless](plugins/serverless.md)：允许在 APISIX 中的不同阶段动态运行 Lua 代码。
* [ip-restriction](plugins/ip-restriction.md): IP 黑白名单。
* [openid-connect](plugins/oauth.md)
* [redirect](plugins/redirect.md): URI 重定向。
* [response-rewrite](plugins/response-rewrite.md): 支持自定义修改返回内容的 `status code`、`body`、`headers`。
* [fault-injection](plugins/fault-injection.md)：故障注入，可以返回指定的响应体、响应码和响应时间，从而提供了不同的失败场景下处理的能力，例如服务失败、服务过载、服务高延时等。
* [proxy-cache](plugins/proxy-cache.md)：代理缓存插件提供缓存后端响应数据的能力。
* [proxy-mirror](plugins/proxy-mirror.md)：代理镜像插件提供镜像客户端请求的能力。
* [udp-logger](plugins/udp-logger.md): 将请求记录到 UDP 服务器
* [tcp-logger](plugins/tcp-logger.md): 将请求记录到 TCP 服务器
* [kafka-logger](plugins/kafka-logger.md): 将请求记录到外部 Kafka 服务器。
* [cors](plugins/cors.md): 为你的API启用 CORS
* [batch-requests](plugins/batch-requests.md): 以 **http pipeline** 的方式在网关一次性发起多个 `http` 请求。
* [authz-keycloak](plugins/authz-keycloak-cn.md): 支持 Keycloak 身份认证服务器
* [uri-blocker](plugins/uri-blocker.md): 根据 URI 拦截用户请求。
* [oauth](plugins/oauth.md): 提供 OAuth 2 身份验证和自省。
