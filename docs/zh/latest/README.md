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

## 参考文档

* [APISIX 说明](../../README_CN.md)
* [架构设计](architecture-design.md)
* [如何构建 Apache APISIX](how-to-build.md)
* [管理 API](admin-api.md)
* [控制 API](../control-api.md)
* [健康检查](health-check.md): 支持对上游节点的主动和被动健康检查，在负载均衡时自动过滤掉不健康的节点。
* [路由 radixtree](../router-radixtree.md)
* [独立运行模型](stand-alone.md): 支持从本地 yaml 格式的配置文件启动，更适合 Kubernetes(k8s) 体系。
* [TCP/UDP 动态代理](stream-proxy.md)
* [gRPC 代理](grpc-proxy.md)
* [自定义 Nginx 配置](./customize-nginx-configuration.md)
* [变更日志](../../CHANGELOG_CN.md)
* [压力测试](benchmark.md)
* [代码风格](../../CODE_STYLE_CN.md)
* [调试功能](./debug-function.md)
* [常见问答](../../FAQ_CN.md)

## 插件

### General

* [batch-requests](plugins/batch-requests.md): 以 **http pipeline** 的方式在网关一次性发起多个 `http` 请求。
* [插件热加载](plugins.md)：无需重启服务，完成插件热加载或卸载。
* [HTTPS/TLS](https.md)：根据 TLS 扩展字段 SNI(Server Name Indication) 动态加载证书。
* [serverless](plugins/serverless.md)：允许在 APISIX 中的不同阶段动态运行 Lua 代码。
* [redirect](plugins/redirect.md): URI 重定向。

### Transformation

* [response-rewrite](plugins/response-rewrite.md): 支持自定义修改返回内容的 `status code`、`body`、`headers`。
* [proxy-rewrite](plugins/proxy-rewrite.md): 支持自定义修改 proxy 到上游的信息。
* [grpc-transcode](plugins/grpc-transcode.md)：REST <--> gRPC 转码。
* [fault-injection](plugins/fault-injection.md)：故障注入，可以返回指定的响应体、响应码和响应时间，从而提供了不同的失败场景下处理的能力，例如服务失败、服务过载、服务高延时等。

### Authentication

* [authz-keycloak](plugins/authz-keycloak.md): 支持 Keycloak 身份认证服务器
* [wolf-rbac](plugins/wolf-rbac.md) 基于 *RBAC* 的用户认证及授权。
* [key-auth](plugins/key-auth.md)：基于 Key Authentication 的用户认证。
* [JWT-auth](plugins/jwt-auth.md)：基于 [JWT](https://jwt.io/) (JSON Web Tokens) Authentication 的用户认证。
* [basic-auth](plugins/basic-auth.md)：基于 basic auth 的用户认证。
* [oauth](plugins/openid-connect.md): 提供 OAuth 2 身份验证和自省。
* [openid-connect](plugins/openid-connect.md)

### Security

* [cors](plugins/cors.md): 为你的API启用 CORS
* [uri-blocker](plugins/uri-blocker.md): 根据 URI 拦截用户请求。

* [referer-restriction](plugins/referer-restriction.md): Referer 白名单。
* [ip-restriction](plugins/ip-restriction.md): IP 黑白名单。

### Traffic

* [limit-req](plugins/limit-req.md)：基于漏桶原理的请求限速实现。
* [limit-conn](plugins/limit-conn.md)：限制并发请求（或并发连接）。
* [limit-count](plugins/limit-count.md)：基于“固定窗口”的限速实现。
* [proxy-cache](plugins/proxy-cache.md)：代理缓存插件提供缓存后端响应数据的能力。
* [request-validation](plugins/request-validation.md): 请求验证。
* [proxy-mirror](plugins/proxy-mirror.md)：代理镜像插件提供镜像客户端请求的能力。
* [api-breaker](plugins/api-breaker.md): API的断路器，在状态不正常的情况下停止将请求转发到上游。
* [traffic-split](plugins/traffic-split.md)：允许用户逐步控制各个上游之间的流量百分比。

### Monitoring

* [prometheus](plugins/prometheus.md)：以 Prometheus 格式导出 APISIX 自身的状态信息，方便被外部 Prometheus 服务抓取。
* [OpenTracing](plugins/zipkin.md)：支持 Zikpin 和 Apache SkyWalking。
* [Skywalking](plugins/skywalking.md): Supports Apache SkyWalking.

### Loggers

* [http-logger](plugins/http-logger.md): 将请求记录到 HTTP 服务器。
* [tcp-logger](plugins/tcp-logger.md): 将请求记录到 TCP 服务器。
* [kafka-logger](plugins/kafka-logger.md): 将请求记录到外部 Kafka 服务器。
* [udp-logger](plugins/udp-logger.md): 将请求记录到 UDP 服务器。
* [sys-log](plugins/syslog.md): 将请求记录到 syslog 服务。
* [log-rotate](plugins/log-rotate.md): 日志文件定期切分。

## 部署

### AWS

推荐的方法是在 [AWS Fargate](https://aws.amazon.com/fargate/) 上使用  [AWS CDK](https://aws.amazon.com/cdk/) 部署 APISIX，这有助于将 APISIX 层和上游层分离到具有自动缩放功能的完全托管和安全的无服务器容器计算环境之上。

### Kubernetes

请参阅[指南](../../kubernetes/README.md)并了解如何在 Kubernetes 中部署 APISIX。
