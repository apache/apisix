---
title: 入门指南
description: 本教程使用脚本在本地环境快速安装 Apache APISIX，并且通过管理 API 来验证是否安装成功。
---

<head>
  <link rel="canonical" href="https://docs.api7.ai/apisix/getting-started/" />
</head>

> 本教程由 [API7.ai](https://api7.ai/) 编写。

Apache APISIX 是 Apache 软件基金会下的[顶级项目](https://projects.apache.org/project.html?apisix)，由 API7.ai 开发并捐赠。它是一个具有动态、实时、高性能等特点的云原生 API 网关。

你可以使用 APISIX 网关作为所有业务的流量入口，它提供了动态路由、动态上游、动态证书、A/B 测试、灰度发布（金丝雀发布）、蓝绿部署、限速、防攻击、收集指标、监控报警、可观测、服务治理等功能。

本教程使用脚本在本地环境快速安装 Apache APISIX，并且通过管理 API 来验证是否安装成功。

## 前置条件

快速启动脚本需要以下条件：

* 已安装 [Docker](https://docs.docker.com/get-docker/)，用于部署  **etcd** 和 **APISIX**。
* 已安装 [curl](https://curl.se/)，用于验证 APISIX 是否安装成功。

## 安装 APISIX

:::caution

为了提供更好的体验，管理 API 默认无需授权，请在生产环境中打开授权开关。

:::
APISIX 可以借助 quickstart 脚本快速安装并启动：

```shell
curl -sL https://run.api7.ai/apisix/quickstart | sh
```

该命令启动 _apisix-quickstart_ 和 _etcd_ 两个容器，APISIX 使用 etcd 保存和同步配置。APISIX 和 etcd 容器使用 Docker 的 [**host**](https://docs.docker.com/network/host/) 网络模式，因此可以从本地直接访问。

如果一切顺利，将输出如下信息：

```text
✔ APISIX is ready!
```

## 验证

你可以通过 curl 来访问正在运行的 APISIX 实例。比如，你可以发送一个简单的 HTTP 请求来验证 APISIX 运行状态是否正常：

```shell
curl "http://127.0.0.1:9080" --head | grep Server
```

如果一切顺利，将输出如下信息：

```text
Server: APISIX/Version
```

这里的 `Version` 是指你已经安装的 APISIX 版本，比如 `APISIX/3.3.0`。

现在，你已经成功安装并运行了 APISIX！

APISIX 提供内置的 Dashboard UI，可访问 `http://127.0.0.1:9180/ui` 使用。更多指南请阅读 [Apache APISIX Dashboard](../dashboard.md)。

## 下一步

如果你已经成功地安装了 APISIX 并且正常运行，那么你可以继续进行下面的教程。

* [配置路由](configure-routes.md)
* [负载均衡](load-balancing.md)
* [限速](rate-limiting.md)
* [密钥验证](key-authentication.md)
