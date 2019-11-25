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
## APISIX

[![Build Status](https://travis-ci.org/apache/incubator-apisix.svg?branch=master)](https://travis-ci.org/apache/incubator-apisix)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/apache/incubator-apisix/blob/master/LICENSE)

- **QQ 交流群**: 552030619
- 邮件列表: 发邮件到 dev-subscribe@apisix.apache.org, 然后跟着回复邮件操作即可
- [![Gitter](https://badges.gitter.im/apisix/community.svg)](https://gitter.im/apisix/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
APISIX 是一个云原生、高性能、可扩展的微服务 API 网关。

它是基于 OpenResty 和 etcd 来实现，和传统 API 网关相比，APISIX 具备动态路由和插件热加载，特别适合微服务体系下的 API 管理。

## 为什么选择 APISIX？

如果你正在构建网站、移动设备或 IoT（物联网）的应用，那么你可能需要使用 API 网关来处理接口流量。

APISIX 是基于云原生的微服务 API 网关，可以处理传统的南北向流量，也可以处理服务间的东西向流量。

APISIX 通过插件机制，提供动态负载平衡、身份验证、限流限速等功能，并且支持你自己开发的插件。

更多详细的信息，可以查阅[ APISIX 的白皮书](https://www.iresty.com/download/%E4%BC%81%E4%B8%9A%E7%94%A8%E6%88%B7%E5%A6%82%E4%BD%95%E9%80%89%E6%8B%A9%E5%BE%AE%E6%9C%8D%E5%8A%A1%20API%20%E7%BD%91%E5%85%B3.pdf)

![](doc/images/apisix.png)

## 功能

- **运行环境**: OpenResty 和 Tengine 都支持。
- **云原生**: 平台无关，没有供应商锁定，无论裸机还是 Kubernetes，APISIX 都可以运行。
- **[热更新和热插件](doc/plugins-cn.md)**: 无需重启服务，就可以持续更新配置和插件。
- **动态负载均衡**：动态支持有权重的 round-robin 负载平衡。
- **支持一致性 hash 的负载均衡**：动态支持一致性 hash 的负载均衡。
- **[SSL](doc/https-cn.md)**：动态加载 SSL 证书。
- **HTTP(S) 反向代理**
- **[健康检查](doc/health-check.md)**：启用上游节点的健康检查，将在负载均衡期间自动过滤不健康的节点，以确保系统稳定性。
- **熔断器**: 智能跟踪不健康上游服务。
- **身份认证**: [key-auth](doc/plugins/key-auth-cn.md), [JWT](doc/plugins/jwt-auth-cn.md)。
- **[限制速率](doc/plugins/limit-req-cn.md)**
- **[限制请求数](doc/plugins/limit-count-cn.md)**
- **[限制并发](doc/plugins/limit-conn-cn.md)**
- **[代理请求重写](doc/plugins/proxy-rewrite.md)**: 支持重写请求上游的`host`、`uri`、`schema`、`enable_websocket`、`headers`信息。
- **[输出内容重写](doc/plugins/response-rewrite.md)**: 支持自定义修改返回内容的 `status code`、`body`、`headers`。
- **OpenTracing: [支持 Apache Skywalking 和 Zipkin](doc/plugins/zipkin.md)**
- **监控和指标**: [Prometheus](doc/plugins/prometheus-cn.md)
- **[gRPC 代理](doc/grpc-proxy-cn.md)**：通过 APISIX 代理 gRPC 连接，并使用 APISIX 的大部分特性管理你的 gRPC 服务。
- **[gRPC 协议转换](doc/plugins/grpc-transcoding-cn.md)**：支持协议的转换，这样客户端可以通过 HTTP/JSON 来访问你的 gRPC API。
- **[Serverless](doc/plugins/serverless-cn.md)**: 在 APISIX 的每一个阶段，你都可以添加并调用自己编写的函数。
- **自定义插件**: 允许挂载常见阶段，例如`rewrite`，`access`，`header filer`，`body filter`和`log`，还允许挂载 `balancer` 阶段。
- **控制台**: 内置控制台来操作 APISIX 集群。
- **版本控制**：支持操作的多次回滚。
- **CLI**: 使用命令行来启动、关闭和重启 APISIX。
- **REST API**
- **Websocket 代理**
- **IPv6**：支持使用 IPv6 格式匹配路由。
- **集群**：APISIX 节点是无状态的，创建配置中心集群请参考 [etcd Clustering Guide](https://github.com/etcd-io/etcd/blob/master/Documentation/v2/clustering.md)。
- **可扩展**：简单易用的插件机制方便扩展。
- **高性能**：在单核上 QPS 可以达到 24k，同时延迟只有 0.6 毫秒。
- **防御 ReDoS(正则表达式拒绝服务)**
- **IP 黑名单**
- **IdP 支持**: 支持外部的身份认证服务，比如 Auth0，Okta，Authing 等，用户可以借此来对接 Oauth2.0 等认证方式。
- **[单机模式](doc/stand-alone-cn.md)**: 支持从本地配置文件中加载路由规则，在 kubernetes(k8s) 等环境下更友好。
- **全局规则**：允许对所有请求执行插件，比如黑白名单、限流限速等。
- **[TCP/UDP 代理](doc/stream-proxy-cn.md)**: 动态 TCP/UDP 代理。
- **[动态 MQTT 代理](doc/plugins/mqtt-proxy-cn.md)**: 支持用 `client_id` 对 MQTT 进行负载均衡，同时支持 MQTT [3.1.*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) 和 [5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html) 两个协议标准。

## 在线演示版本
我们部署了一个在线的 [dashboard](http://apisix.iresty.com) ，方便您了解 APISIX。

## 安装

APISIX 在以下操作系统中可顺利安装并做过运行测试，需要注意的是：OpenResty 的版本必须 >= 1.15.8.1：

CentOS 7, Ubuntu 16.04, Ubuntu 18.04, Debian 9, Debian 10, macOS, **ARM64** Ubuntu 18.04

安装 APISIX 的步骤：
1. 安装运行时依赖：OpenResty 和 etcd，参考[依赖安装文档](doc/install-dependencies.md).
2. 有以下几种方式来安装 Apache APISIX:
    - 通过[源码候选版本](doc/how-to-build-cn.md#通过源码候选版本安装);
    - 如果你在使用 CentOS 7，可以使用 [RPM 包安装](doc/how-to-build-cn.md#通过-rpm-包安装centos-7)；
    - 其它 Linux 操作系统，可以使用 [Luarocks 安装方式](doc/how-to-build-cn.md#通过-luarocks-安装-不支持-macos)；
    - 你也可以使用 [Docker 镜像](https://github.com/apache/incubator-apisix-docker) 来安装。

## 快速上手

1. 启动 APISIX

```shell
sudo apisix start
```

2. 测试限流插件

你可以测试限流插件，来上手体验 APISIX，按照[限流插件文档](doc/plugins/limit-count-cn.md)的步骤即可。

更进一步，你可以跟着文档来尝试更多的[插件](doc/README_CN.md#插件)。

## 控制台
APISIX 内置了 dashboard，使用浏览器打开 `http://127.0.0.1:9080/apisix/dashboard/` 即可使用，
不用填写用户名和密码，直接登录。

Dashboard 默认允许任何 IP 访问。你可以自行修改 `conf/config.yaml` 中的 `allow_admin` 字段，指定允许访问 dashboard 的 IP 列表。

## 性能测试

使用 AWS 的 8 核心服务器来压测 APISIX，QPS 可以达到 140000，同时延时只有 0.2 毫秒。

## 文档

[文档](doc/README_CN.md)

## 视频和文章

- 2019.10.30 [Apache APISIX 微服务架构极致性能架构解析](https://www.upyun.com/opentalk/440.html)
- 2019.8.31 [APISIX 技术选型、测试和持续集成](https://www.upyun.com/opentalk/433.html)
- 2019.8.31 [APISIX 高性能实战2](https://www.upyun.com/opentalk/437.html)
- 2019.7.6 [APISIX 高性能实战](https://www.upyun.com/opentalk/429.html)

## APISIX 的用户有哪些？
有很多公司和组织把 APISIX 用户学习、研究、生产环境和商业产品中，包括：

1. dasouche.com 大搜车
1. haieruplus.com 海尔优家
1. ke.com 贝壳找房
1. meizu.com 魅族
1. taikang.com 泰康云
1. tangdou.com 糖豆网
1. Tencent Cloud 腾讯云
1. zuzuche.com 租租车

欢迎用户把自己加入到 [Powered By](doc/powered-by.md) 页面。

## 全景图
<p align="left">
<img src="https://landscape.cncf.io/images/left-logo.svg" width="150">&nbsp;&nbsp;<img src="https://landscape.cncf.io/images/right-logo.svg" width="200">
<br/><br/>
APISIX 被纳入 <a href="https://landscape.cncf.io/category=api-gateway&format=card-mode&grouping=category"> 云原生软件基金会 API 网关全景图</a>
</p>

## 参与社区

如果你对 APISIX 的开发和使用感兴趣，欢迎加入我们的 QQ 群来交流:

<img src="doc/images/qq-group.png" width="302" height="302">

## 致谢

灵感来自 Kong 和 Orange。
