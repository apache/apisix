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
- 邮件列表: 发邮件到 dev-subscribe@apisix.apache.org, 然后跟着回复邮件操作即可。
- ![Twitter Follow](https://img.shields.io/twitter/follow/ApacheAPISIX?style=social)

APISIX 是一个云原生、高性能、可扩展的微服务 API 网关。

它是基于 OpenResty 和 etcd 来实现，和传统 API 网关相比，APISIX 具备动态路由和插件热加载，特别适合微服务体系下的 API 管理。

## 为什么选择 APISIX？

如果你正在构建网站、移动设备或 IoT（物联网）的应用，那么你可能需要使用 API 网关来处理接口流量。

APISIX 是基于云原生的微服务 API 网关，它是所有业务流量的入口，可以处理传统的南北向流量，也可以处理服务间的东西向流量，也可以当做 k8s ingress controller 来使用。

APISIX 通过插件机制，提供动态负载平衡、身份验证、限流限速等功能，并且支持你自己开发的插件。

更多详细的信息，可以查阅[ APISIX 的白皮书](https://www.iresty.com/download/%E4%BC%81%E4%B8%9A%E7%94%A8%E6%88%B7%E5%A6%82%E4%BD%95%E9%80%89%E6%8B%A9%E5%BE%AE%E6%9C%8D%E5%8A%A1%20API%20%E7%BD%91%E5%85%B3.pdf)

![](doc/images/apisix.png)

## 功能
你可以把 Apache APISIX 当做流量入口，来处理所有的业务数据，包括动态路由、动态上游、动态证书、
A/B 测试、金丝雀发布(灰度发布)、蓝绿部署、限流限速、抵御恶意攻击、监控报警、服务可观测性、服务治理等。

- **全平台**
    - 云原生: 平台无关，没有供应商锁定，无论裸机还是 Kubernetes，APISIX 都可以运行。
    - 运行环境: OpenResty 和 Tengine 都支持。
    - 支持 [ARM64](https://zhuanlan.zhihu.com/p/84467919): 不用担心底层技术的锁定。

- **多协议**
    - [TCP/UDP 代理](doc/stream-proxy-cn.md): 动态 TCP/UDP 代理。
    - [动态 MQTT 代理](doc/plugins/mqtt-proxy-cn.md): 支持用 `client_id` 对 MQTT 进行负载均衡，同时支持 MQTT [3.1.*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) 和 [5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html) 两个协议标准。
    - [gRPC 代理](doc/grpc-proxy-cn.md)：通过 APISIX 代理 gRPC 连接，并使用 APISIX 的大部分特性管理你的 gRPC 服务。
    - [gRPC 协议转换](doc/plugins/grpc-transcoding-cn.md)：支持协议的转换，这样客户端可以通过 HTTP/JSON 来访问你的 gRPC API。
    - Websocket 代理
    - Proxy Protocol
    - Dubbo 代理：基于 Tengine，可以实现 Dubbo 请求的代理。
    - HTTP(S) 反向代理
    - [SSL](doc/https-cn.md)：动态加载 SSL 证书。

- **全动态能力**
    - [热更新和热插件](doc/plugins-cn.md): 无需重启服务，就可以持续更新配置和插件。
    - [代理请求重写](doc/plugins/proxy-rewrite-cn.md): 支持重写请求上游的`host`、`uri`、`schema`、`enable_websocket`、`headers`信息。
    - [输出内容重写](doc/plugins/response-rewrite-cn.md): 支持自定义修改返回内容的 `status code`、`body`、`headers`。
    - [Serverless](doc/plugins/serverless-cn.md): 在 APISIX 的每一个阶段，你都可以添加并调用自己编写的函数。
    - 动态负载均衡：动态支持有权重的 round-robin 负载平衡。
    - 支持一致性 hash 的负载均衡：动态支持一致性 hash 的负载均衡。
    - [健康检查](doc/health-check.md)：启用上游节点的健康检查，将在负载均衡期间自动过滤不健康的节点，以确保系统稳定性。
    - 熔断器: 智能跟踪不健康上游服务。

- **精细化路由**
    - [支持全路径匹配和前缀匹配](doc/router-radixtree.md#how-to-use-libradixtree-in-apisix)
    - [支持使用 Nginx 所有内置变量做为路由的条件](/doc/router-radixtree.md#how-to-filter-route-by-nginx-builtin-variable)，所以你可以使用 `cookie`, `args` 等做为路由的条件，来实现灰度发布、A/B 测试等功能
    - 支持[各类操作符做为路由的判断条件](https://github.com/iresty/lua-resty-radixtree#operator-list)，比如 `{"arg_age", ">", 24}`
    - 支持[自定义路由匹配函数](https://github.com/iresty/lua-resty-radixtree/blob/master/t/filter-fun.t#L10)
    - IPv6：支持使用 IPv6 格式匹配路由
    - 支持路由的[自动过期(TTL)](doc/admin-api-cn.md#route)
    - [支持路由的优先级](doc/router-radixtree.md#3-match-priority)

- **安全防护**
    - 多种身份认证方式: [key-auth](doc/plugins/key-auth-cn.md), [JWT](doc/plugins/jwt-auth-cn.md), [basic-auth](doc/plugins/basic-auth-cn.md), [wolf-rbac](doc/plugins/wolf-rbac-cn.md)。
    - [IP 黑白名单](doc/plugins/ip-restriction-cn.md)
    - [IdP 支持](doc/plugins/oauth.md): 支持外部的身份认证服务，比如 Auth0，Okta，Authing 等，用户可以借此来对接 Oauth2.0 等认证方式。
    - [限制速率](doc/plugins/limit-req-cn.md)
    - [限制请求数](doc/plugins/limit-count-cn.md)
    - [限制并发](doc/plugins/limit-conn-cn.md)
    - 防御 ReDoS(正则表达式拒绝服务)：内置策略，无需配置即可抵御 ReDoS。
    - [CORS](doc/plugins/cors-cn.md)

- **运维友好**
    - OpenTracing 可观测性: [支持 Apache Skywalking 和 Zipkin](doc/plugins/zipkin-cn.md)。
    - 监控和指标: [Prometheus](doc/plugins/prometheus-cn.md)
    - 集群：APISIX 节点是无状态的，创建配置中心集群请参考 [etcd Clustering Guide](https://github.com/etcd-io/etcd/blob/master/Documentation/op-guide/clustering.md)。
    - 高可用：支持配置同一个集群内的多个 etcd 地址。
    - 控制台: 内置控制台来操作 APISIX 集群。
    - 版本控制：支持操作的多次回滚。
    - CLI: 使用命令行来启动、关闭和重启 APISIX。
    - [单机模式](doc/stand-alone-cn.md): 支持从本地配置文件中加载路由规则，在 kubernetes(k8s) 等环境下更友好。
    - [全局规则](doc/architecture-design-cn.md#Global-Rule)：允许对所有请求执行插件，比如黑白名单、限流限速等。
    - 高性能：在单核上 QPS 可以达到 18k，同时延迟只有 0.2 毫秒。
    - [故障注入](doc/plugins/fault-injection-cn.md)
    - [REST Admin API](doc/admin-api-cn.md)
    - [Python SDK](https://github.com/api7/apache-apisix-python-sdk)

- **高度可扩展**
    - [自定义插件](doc/plugin-develop-cn.md): 允许挂载常见阶段，例如`init`, `rewrite`，`access`，`balancer`,`header filer`，`body filter` 和 `log` 阶段。
    - 自定义负载均衡算法：可以在 `balancer` 阶段使用自定义负载均衡算法。
    - 自定义路由: 支持用户自己实现路由算法。

## 安装

APISIX 在以下操作系统中可顺利安装并做过运行测试，需要注意的是：OpenResty 的版本必须 >= 1.15.8.1：

CentOS 7, Ubuntu 16.04, Ubuntu 18.04, Debian 9, Debian 10, macOS, **[ARM64](https://zhuanlan.zhihu.com/p/84467919)** Ubuntu 18.04

安装 APISIX 的步骤：
1. 安装运行时依赖：OpenResty 和 etcd，参考[依赖安装文档](doc/install-dependencies.md)
2. 有以下几种方式来安装 Apache APISIX:
    - 通过[源码包安装](doc/how-to-build-cn.md#通过源码包安装);
    - 如果你在使用 CentOS 7，可以使用 [RPM 包安装](doc/how-to-build-cn.md#通过-rpm-包安装centos-7)；
    - 其它 Linux 操作系统，可以使用 [Luarocks 安装方式](doc/how-to-build-cn.md#通过-luarocks-安装-不支持-macos)；
    - 你也可以使用 [Docker 镜像](https://github.com/apache/incubator-apisix-docker) 来安装。

## 快速上手

1. 启动 APISIX

```shell
sudo apisix start
```

2. 入门指南

入门指南是学习 APISIX 基础知识的好方法。按照 [入门指南](doc/getting-started-cn.md)的步骤即可。

更进一步，你可以跟着文档来尝试更多的[插件](doc/README_CN.md#插件)。

## 控制台

APISIX 内置了对 Dashboard 的支持，使用步骤如下：

1. 确保你的运行环境中的 Node 版本 >= 8.12.0。

2. 下载 [Dashboard](https://github.com/apache/incubator-apisix-dashboard) 的源码：
```
git clone https://github.com/apache/incubator-apisix-dashboard.git
```

3. 安装 [yarn](https://yarnpkg.com/zh-Hans/docs/install)

4. 安装依赖并构建
```
git checkout <v1.0>  #这里的tag版本和你使用的apisix版本一致
yarn && yarn build:prod
```

5. 与 APISIX 集成
把编译后的在 `/dist` 目录下的所有文件，拷贝到 `apisix/dashboard` 目录下。
使用浏览器打开 `http://127.0.0.1:9080/apisix/dashboard/` 即可使用，
不用填写用户名和密码，直接登录。

Dashboard 默认允许任何 IP 访问。你可以自行修改 `conf/config.yaml` 中的 `allow_admin` 字段，指定允许访问 dashboard 的 IP 列表。

我们部署了一个在线的 [Dashboard](http://apisix.iresty.com) ，方便你了解 APISIX。

## 性能测试

使用 AWS 的 8 核心服务器来压测 APISIX，QPS 可以达到 140000，同时延时只有 0.2 毫秒。

## 文档

[Apache APISIX 文档索引](doc/README_CN.md)

## Apache APISIX 和 Kong 的比较

#### API 网关核心功能点，两者均已覆盖

| **功能**   | **Apache APISIX**   | **KONG**   |
|:----|:----|:----|
| **动态上游**  | 支持   | 支持   |
| **动态路由**  | 支持   | 支持   |
| **健康检查和熔断器**  | 支持   | 支持   |
| **动态SSL证书**  | 支持   | 支持   |
| **七层和四层代理**  | 支持   | 支持   |
| **分布式追踪**  | 支持   | 支持   |
| **自定义插件**  | 支持   | 支持   |
| **REST API**  | 支持   | 支持   |
| **CLI**  | 支持   | 支持   |

#### Apache APISIX 的优势

| **功能**   | **Apache APISIX**   | **KONG**   |
|:----|:----|:----|
| 项目归属   | Apache 软件基金会   | Kong Inc.   |
| 技术架构   | Nginx + etcd   | Nginx + postgres   |
| 交流渠道  | 微信群、QQ群、邮件列表、Github、meetup   | Github、论坛、freenode   |
| 单核 QPS (开启限流和prometheus插件)   | 18000   | 1700   |
| 平均延迟  | 0.2 毫秒   | 2 毫秒   |
| 支持 Dubbo 代理   | 是   | 否   |
| 配置回滚   | 是   | 否   |
| 支持生命周期的路由   | 是   | 否   |
| 插件热更新   | 是   | 否   |
| 用户自定义：负载均衡算法、路由   | 是   | 否   |
| resty <--> gRPC 转码   | 是   | 否   |
| 支持 Tengine 作为运行时   | 是   | 否   |
| MQTT 协议支持   | 是   | 否   |
| 配置生效时间   | 事件通知，低于1毫秒更新   | 定期轮询，5 秒   |
| 自带控制台   | 是   | 否   |
| 对接外部身份认证服务   | 是   | 否   |
| 配置中心高可用(HA)   | 是   | 否   |
| 指定时间窗口的限速   | 是   | 否   |
| 支持任何 Nginx 变量做路由条件 | 是   | 否   |


## 视频和文章
- 2020.1.17 [API 网关 Apache APISIX 和 Kong 的选型对比](https://mp.weixin.qq.com/s/c51apneVj0O9yxiZAHF34Q)
- 2019.12.14 [从 0 到 1：Apache APISIX 的 Apache 之路](https://zhuanlan.zhihu.com/p/99620158)
- 2019.12.14 [基于 Apache APISIX 的下一代微服务架构](https://www.upyun.com/opentalk/445.html)
- 2019.10.30 [Apache APISIX 微服务架构极致性能架构解析](https://www.upyun.com/opentalk/440.html)
- 2019.9.27 [想把 APISIX 运行在 ARM64 平台上？只要三步](https://zhuanlan.zhihu.com/p/84467919)
- 2019.8.31 [APISIX 技术选型、测试和持续集成](https://www.upyun.com/opentalk/433.html)
- 2019.8.31 [APISIX 高性能实战2](https://www.upyun.com/opentalk/437.html)
- 2019.7.6 [APISIX 高性能实战](https://www.upyun.com/opentalk/429.html)

## 用户实际使用案例
- [贝壳找房：如何基于 Apache APISIX 搭建网关](https://mp.weixin.qq.com/s/yZl9MWPyF1-gOyCp8plflA)
- [360：Apache APISIX 在基础运维平台项目中的实践](https://mp.weixin.qq.com/s/zHF_vlMaPOSoiNvqw60tVw)
- [HelloTalk：基于 OpenResty 和 Apache APISIX 的全球化探索之路](https://www.upyun.com/opentalk/447.html)
- [腾讯云：为什么选择 Apache APISIX 来实现 k8s ingress controller?](https://www.upyun.com/opentalk/448.html)
- [思必驰：为什么我们重新写了一个 k8s ingress controller?](https://mp.weixin.qq.com/s/bmm2ibk2V7-XYneLo9XAPQ)

## APISIX 的用户有哪些？
有很多公司和组织把 APISIX 用户学习、研究、生产环境和商业产品中，包括：

<img src="https://raw.githubusercontent.com/iresty/iresty.com/master/user-wall.jpg" width="900" height="500">

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
