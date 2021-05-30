---
title: Apache APISIX
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

<img src="https://svn.apache.org/repos/asf/comdev/project-logos/originals/apisix.svg" alt="APISIX logo" height="150px" align="right" />

[![Build Status](https://github.com/apache/apisix/workflows/build/badge.svg?branch=master)](https://github.com/apache/apisix/actions)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/apache/apisix/blob/master/LICENSE)

**Apache APISIX** 是一个动态、实时、高性能的 API 网关，
提供负载均衡、动态上游、灰度发布、服务熔断、身份认证、可观测性等丰富的流量管理功能。

你可以使用 Apache APISIX 来处理传统的南北向流量，以及服务间的东西向流量，
也可以当做 [k8s ingress controller](https://github.com/apache/apisix-ingress-controller) 来使用。

Apache APISIX 的技术架构如下图所示：

![Apache APISIX 的技术架构](../../assets/images/apisix.png)

## 社区

- 邮件列表 - 发送任意内容到 dev-subscribe@apisix.apache.org 后，根据回复以订阅邮件列表。
- QQ 群 - 578997126
- [Slack](http://s.apache.org/slack-invite) - 加入 `#apisix` 频道以便与成员交流。
- ![Twitter Follow](https://img.shields.io/twitter/follow/ApacheAPISIX?style=social) - 使用标签 `#ApacheAPISIX` 关注我们并与我们互动。
- [哔哩哔哩](https://space.bilibili.com/551921247)
- **新手任务列表**
  - [Apache APISIX](https://github.com/apache/apisix/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [Apache APISIX ingress controller](https://github.com/apache/apisix-ingress-controller/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [Apache APISIX dashboard](https://github.com/apache/apisix-dashboard/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [Apache APISIX Helm Chart](https://github.com/apache/apisix-helm-chart/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [Docker distribution for APISIX](https://github.com/apache/apisix-docker/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [Apache APISIX Website](https://github.com/apache/apisix-website/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  - [The Control-Plane for APISIX](https://github.com/apache/apisix-control-plane/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
- **微信公众号**
   ![](../../assets/images/OA.jpg)
- **微信视频号**
   ![](../../assets/images/MA.jpeg)

## 特性

你可以把 Apache APISIX 当做流量入口，来处理所有的业务数据，包括动态路由、动态上游、动态证书、
A/B 测试、金丝雀发布(灰度发布)、蓝绿部署、限流限速、抵御恶意攻击、监控报警、服务可观测性、服务治理等。

- **全平台**

  - 云原生: 平台无关，没有供应商锁定，无论裸机还是 Kubernetes，APISIX 都可以运行。
  - 运行环境: OpenResty 和 Tengine 都支持。
  - 支持 ARM64: 不用担心底层技术的锁定。

- **多协议**

  - [TCP/UDP 代理](stream-proxy.md): 动态 TCP/UDP 代理。
  - [Dubbo 代理](plugins/dubbo-proxy.md): 动态代理 HTTP 请求到 Dubbo 后端。
  - [动态 MQTT 代理](plugins/mqtt-proxy.md): 支持用 `client_id` 对 MQTT 进行负载均衡，同时支持 MQTT [3.1.\*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) 和 [5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html) 两个协议标准。
  - [gRPC 代理](grpc-proxy.md)：通过 APISIX 代理 gRPC 连接，并使用 APISIX 的大部分特性管理你的 gRPC 服务。
  - [gRPC 协议转换](plugins/grpc-transcode.md)：支持协议的转换，这样客户端可以通过 HTTP/JSON 来访问你的 gRPC API。
  - Websocket 代理
  - Proxy Protocol
  - Dubbo 代理：基于 Tengine，可以实现 Dubbo 请求的代理。
  - HTTP(S) 反向代理
  - [SSL](https.md)：动态加载 SSL 证书。

- **全动态能力**

  - [热更新和热插件](plugins.md): 无需重启服务，就可以持续更新配置和插件。
  - [代理请求重写](plugins/proxy-rewrite.md): 支持重写请求上游的`host`、`uri`、`schema`、`enable_websocket`、`headers`信息。
  - [输出内容重写](plugins/response-rewrite.md): 支持自定义修改返回内容的 `status code`、`body`、`headers`。
  - [Serverless](plugins/serverless.md): 在 APISIX 的每一个阶段，你都可以添加并调用自己编写的函数。
  - 动态负载均衡：动态支持有权重的 round-robin 负载平衡。
  - 支持一致性 hash 的负载均衡：动态支持一致性 hash 的负载均衡。
  - [健康检查](health-check.md)：启用上游节点的健康检查，将在负载均衡期间自动过滤不健康的节点，以确保系统稳定性。
  - 熔断器: 智能跟踪不健康上游服务。
  - [代理镜像](plugins/proxy-mirror.md): 提供镜像客户端请求的能力。
  - [流量拆分](plugins/traffic-split.md): 允许用户逐步控制各个上游之间的流量百分比。

- **精细化路由**

  - [支持全路径匹配和前缀匹配](../../en/latest/router-radixtree.md#how-to-use-libradixtree-in-apisix)
  - [支持使用 Nginx 所有内置变量做为路由的条件](../../en/latest/router-radixtree.md#how-to-filter-route-by-nginx-builtin-variable)，所以你可以使用 `cookie`, `args` 等做为路由的条件，来实现灰度发布、A/B 测试等功能
  - 支持[各类操作符做为路由的判断条件](https://github.com/iresty/lua-resty-radixtree#operator-list)，比如 `{"arg_age", ">", 24}`
  - 支持[自定义路由匹配函数](https://github.com/iresty/lua-resty-radixtree/blob/master/t/filter-fun.t#L10)
  - IPv6：支持使用 IPv6 格式匹配路由
  - 支持路由的[自动过期(TTL)](admin-api.md#route)
  - [支持路由的优先级](../../en/latest/router-radixtree.md#3-match-priority)
  - [支持批量 Http 请求](plugins/batch-requests.md)

- **安全防护**

  - 多种身份认证方式: [key-auth](plugins/key-auth.md), [JWT](plugins/jwt-auth.md), [basic-auth](plugins/basic-auth.md), [wolf-rbac](plugins/wolf-rbac.md)。
  - [IP 黑白名单](plugins/ip-restriction.md)
  - [Referer 白名单](plugins/referer-restriction.md)
  - [IdP 支持](plugins/openid-connect.md): 支持外部的身份认证服务，比如 Auth0，Okta，Authing 等，用户可以借此来对接 Oauth2.0 等认证方式。
  - [限制速率](plugins/limit-req.md)
  - [限制请求数](plugins/limit-count.md)
  - [限制并发](plugins/limit-conn.md)
  - 防御 ReDoS(正则表达式拒绝服务)：内置策略，无需配置即可抵御 ReDoS。
  - [CORS](plugins/cors.md)：为你的 API 启用 CORS。
  - [URI 拦截器](plugins/uri-blocker.md)：根据 URI 拦截用户请求。
  - [请求验证器](plugins/request-validation.md)。

- **运维友好**

  - OpenTracing 可观测性: 支持 [Apache Skywalking](plugins/skywalking.md) 和 [Zipkin](plugins/zipkin.md)。
  - 对接外部服务发现：除了内置的 etcd 外，还支持 [Consul](../../en/latest/discovery/consul_kv.md) 和 [Nacos](../../en/latest/discovery/nacos.md)，以及 [Eureka](discovery.md)。
  - 监控和指标: [Prometheus](plugins/prometheus.md)
  - 集群：APISIX 节点是无状态的，创建配置中心集群请参考 [etcd Clustering Guide](https://etcd.io/docs/v3.4.0/op-guide/clustering/)。
  - 高可用：支持配置同一个集群内的多个 etcd 地址。
  - [控制台](https://github.com/apache/apisix-dashboard): 操作 APISIX 集群。
  - 版本控制：支持操作的多次回滚。
  - CLI: 使用命令行来启动、关闭和重启 APISIX。
  - [单机模式](stand-alone.md): 支持从本地配置文件中加载路由规则，在 kubernetes(k8s) 等环境下更友好。
  - [全局规则](architecture-design/global-rule.md)：允许对所有请求执行插件，比如黑白名单、限流限速等。
  - 高性能：在单核上 QPS 可以达到 18k，同时延迟只有 0.2 毫秒。
  - [故障注入](plugins/fault-injection.md)
  - [REST Admin API](admin-api.md): 使用 REST Admin API 来控制 Apache APISIX，默认只允许 127.0.0.1 访问，你可以修改 `conf/config.yaml` 中的 `allow_admin` 字段，指定允许调用 Admin API 的 IP 列表。同时需要注意的是，Admin API 使用 key auth 来校验调用者身份，**在部署前需要修改 `conf/config.yaml` 中的 `admin_key` 字段，来保证安全。**
  - 外部日志记录器：将访问日志导出到外部日志管理工具。([HTTP Logger](plugins/http-logger.md), [TCP Logger](plugins/tcp-logger.md), [Kafka Logger](plugins/kafka-logger.md), [UDP Logger](plugins/udp-logger.md))
  - [Helm charts](https://github.com/apache/apisix-helm-chart)

- **高度可扩展**
  - [自定义插件](plugin-develop.md): 允许挂载常见阶段，例如`init`, `rewrite`，`access`，`balancer`,`header filter`，`body filter` 和 `log` 阶段。
  - 自定义负载均衡算法：可以在 `balancer` 阶段使用自定义负载均衡算法。
  - 自定义路由: 支持用户自己实现路由算法。

## 立刻开始

### 编译和安装

APISIX 在以下操作系统中可顺利安装并做过测试：

CentOS 7, Ubuntu 16.04, Ubuntu 18.04, Debian 9, Debian 10, macOS, **ARM64** Ubuntu 18.04

有以下几种方式来安装 APISIX 的 Apache Release 版本:

1. 源码编译（适用所有系统）

   - 安装运行时依赖：OpenResty 和 etcd，以及编译的依赖：luarocks。参考[依赖安装文档](install-dependencies.md)
   - 下载最新的源码发布包：

     ```shell
     $ mkdir apisix-2.6
     $ wget https://downloads.apache.org/apisix/2.6/apache-apisix-2.6-src.tgz
     $ tar zxvf apache-apisix-2.6-src.tgz -C apisix-2.6
     ```

   - 安装运行时依赖的 Lua 库：

     ```shell
     $ make deps
     ```

   - 检查 APISIX 的版本号：

     ```shell
     $ ./bin/apisix version
     ```

   - 启动 APISIX:

     ```shell
     $ ./bin/apisix start
     ```

2. [Docker 镜像](https://hub.docker.com/r/apache/apisix)（适用所有系统）

   默认会拉取最新的 Apache 发布包：

   ```shell
   $ docker pull apache/apisix
   ```

   Docker 镜像中并不包含 etcd，你可以参考 [docker compose 的示例](https://github.com/apache/apisix-docker/tree/master/example)来启动一个测试集群。

3. RPM 包（只适用于 CentOS 7）

   - 安装依赖：OpenResty, etcd 和 OpenSSL develop library，参考[依赖安装文档](install-dependencies.md#centos-7)
   - 安装 APISIX：

   ```shell
   $ sudo yum install -y https://github.com/apache/apisix/releases/download/2.6/apisix-2.6-0.x86_64.rpm
   ```

   - 检查 APISIX 的版本号：

     ```shell
     $ apisix version
     ```

   - 启动 APISIX:

     ```shell
     $ apisix start
     ```

**注意**：Apache APISIX 从 v2.0 开始不再支持 etcd v2 协议，并且 etcd 最低支持版本为 v3.4.0，如果有需要请进行升级。如果需要将数据迁移至 etcd v3，请按照 [etcd 迁移指南](https://etcd.io/docs/v3.4.0/op-guide/v2-migration/) 进行迁移。

### 针对开发者

1. 对于开发者而言，可以使用最新的 master 分支来体验更多功能

   - 源码编译

   ```shell
   $ git clone git@github.com:apache/apisix.git
   $ cd apisix
   $ make deps
   ```

   - Docker 镜像

   ```shell
   $ git clone https://github.com/apache/apisix-docker.git
   $ cd apisix-docker
   $ sudo docker build -f alpine-dev/Dockerfile .
   ```

2. 入门指南

   入门指南是学习 APISIX 基础知识的好方法。按照 [入门指南](getting-started.md)的步骤即可。

   更进一步，你可以跟着文档来尝试更多的[插件](README.md#插件)。

3. Admin API

   Apache APISIX 提供了 [REST Admin API](admin-api.md)，方便动态控制 Apache APISIX 集群。

4. 插件二次开发

   可以参考[插件开发指南](plugin-develop.md)，以及[示例插件 echo](plugins/echo.md) 的文档和代码实现。

   请注意，Apache APISIX 的插件新增、更新、删除等都是热加载的，不用重启服务。

更多文档请参考 [Apache APISIX 文档索引](README.md)。

## 性能测试

使用 AWS 的 8 核心服务器来压测 APISIX，QPS 可以达到 140000，同时延时只有 0.2 毫秒。

[性能测试脚本](https://github.com/apache/apisix/blob/master/benchmark/run.sh)，以及[测试方法和过程](https://gist.github.com/membphis/137db97a4bf64d3653aa42f3e016bd01)已经开源，欢迎补充。

## Apache APISIX 和 Kong 的比较

#### API 网关核心功能点，两者均已覆盖

| **功能**             | **Apache APISIX** | **KONG** |
| :------------------- | :---------------- | :------- |
| **动态上游**         | 支持              | 支持     |
| **动态路由**         | 支持              | 支持     |
| **健康检查和熔断器** | 支持              | 支持     |
| **动态 SSL 证书**    | 支持              | 支持     |
| **七层和四层代理**   | 支持              | 支持     |
| **分布式追踪**       | 支持              | 支持     |
| **自定义插件**       | 支持              | 支持     |
| **REST API**         | 支持              | 支持     |
| **CLI**              | 支持              | 支持     |

#### Apache APISIX 的优势

| **功能**                               | **Apache APISIX**                       | **KONG**               |
| :------------------------------------ | :-------------------------------------- | :--------------------- |
| 项目归属                               | Apache 软件基金会                         | Kong Inc.              |
| 技术架构                               | Nginx + etcd                            | Nginx + postgres       |
| 交流渠道                               | 微信群、QQ 群、邮件列表、[GitHub](https://github.com/apache/apisix/issues)、[Slack](https://join.slack.com/t/the-asf/shared_invite/zt-nggtva4i-hDCsW1S35MuZ2g_2DgVDGg)、meetup | GitHub、论坛、freenode |
| 单核 QPS (开启限流和 prometheus 插件)    | 18000                                   | 1700                   |
| 平均延迟                               | 0.2 毫秒                                 | 2 毫秒                 |
| 支持 Dubbo 代理                        | 是                                      | 否                     |
| 配置回滚                               | 是                                      | 否                     |
| 支持生命周期的路由                       | 是                                      | 否                     |
| 插件热更新                             | 是                                      | 否                     |
| 用户自定义：负载均衡算法、路由             | 是                                      | 否                     |
| resty <--> gRPC 转码                  | 是                                      | 否                     |
| 支持 Tengine 作为运行时                 | 是                                      | 否                     |
| MQTT 协议支持                          | 是                                      | 否                     |
| 配置生效时间                            | 事件通知，低于 1 毫秒更新                  | 定期轮询，5 秒           |
| 自带控制台                             | 是                                      | 否                     |
| 对接外部身份认证服务                     | 是                                      | 否                     |
| 配置中心高可用(HA)                      | 是                                      | 否                     |
| 指定时间窗口的限速                      | 是                                      | 否                     |
| 支持任何 Nginx 变量做路由条件            | 是                                      | 否                     |

性能对比测试[详细内容如下](https://gist.github.com/membphis/137db97a4bf64d3653aa42f3e016bd01)。

### 贡献者变化

![contributor-over-time](../../assets/images/contributor-over-time.png)

## 视频和文章

- 2020.10.16 [Apache APISIX: How to implement plugin orchestration in API Gateway](https://www.youtube.com/watch?v=iEegNXOtEhQ)
- 2020.10.16 [Improve Apache APISIX observability with Apache Skywalking](https://www.youtube.com/watch?v=DleVJwPs4i4)
- 2020.1.17 [API 网关 Apache APISIX 和 Kong 的选型对比](https://mp.weixin.qq.com/s/c51apneVj0O9yxiZAHF34Q)
- 2019.12.14 [从 0 到 1：Apache APISIX 的 Apache 之路](https://zhuanlan.zhihu.com/p/99620158)
- 2019.12.14 [基于 Apache APISIX 的下一代微服务架构](https://www.upyun.com/opentalk/445.html)
- 2019.10.30 [Apache APISIX 微服务架构极致性能架构解析](https://www.upyun.com/opentalk/440.html)
- 2019.9.27 [想把 APISIX 运行在 ARM64 平台上？只要三步](https://zhuanlan.zhihu.com/p/84467919)
- 2019.8.31 [APISIX 技术选型、测试和持续集成](https://www.upyun.com/opentalk/433.html)
- 2019.8.31 [APISIX 高性能实战 2](https://www.upyun.com/opentalk/437.html)
- 2019.7.6 [APISIX 高性能实战](https://www.upyun.com/opentalk/429.html)

## 用户实际使用案例

- [欧盟数字工厂平台: API Security Gateway – Using APISIX in the eFactory Platform](https://www.efactory-project.eu/post/api-security-gateway-using-apisix-in-the-efactory-platform)
- [贝壳找房：如何基于 Apache APISIX 搭建网关](https://mp.weixin.qq.com/s/yZl9MWPyF1-gOyCp8plflA)
- [360：Apache APISIX 在基础运维平台项目中的实践](https://mp.weixin.qq.com/s/zHF_vlMaPOSoiNvqw60tVw)
- [HelloTalk：基于 OpenResty 和 Apache APISIX 的全球化探索之路](https://www.upyun.com/opentalk/447.html)
- [腾讯云：为什么选择 Apache APISIX 来实现 k8s ingress controller?](https://www.upyun.com/opentalk/448.html)
- [思必驰：为什么我们重新写了一个 k8s ingress controller?](https://mp.weixin.qq.com/s/bmm2ibk2V7-XYneLo9XAPQ)

## APISIX 的用户有哪些？

有很多公司和组织把 APISIX 用于学习、研究、生产环境和商业产品中，包括：

<img src="https://user-images.githubusercontent.com/40708551/109484046-f7c4e280-7aa5-11eb-9d71-aab90830773a.png" width="725" height="1700" />

欢迎用户把自己加入到 [Powered By](https://github.com/apache/apisix/blob/master/powered-by.md) 页面。

## 全景图

<p align="left">
<img src="https://landscape.cncf.io/images/left-logo.svg" width="150" />&nbsp;&nbsp;<img src="https://landscape.cncf.io/images/right-logo.svg" width="200" />
<br /><br />
APISIX 被纳入 <a href="https://landscape.cncf.io/card-mode?category=api-gateway&grouping=category"> 云原生软件基金会 API 网关全景图</a>
</p>

## Logo

- [Apache APISIX logo(PNG)](../../../logos/apache-apisix.png)
- [Apache APISIX logo 源文件](https://apache.org/logos/#apisix)

## 贡献

我们欢迎来自开源社区、个人和合作伙伴的各种贡献。

- [贡献指南](../../../CONTRIBUTING.md)

## 致谢

灵感来自 Kong 和 Orange。

## 协议

[Apache 2.0 License](../../../LICENSE)
