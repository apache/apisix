---
title: 升级指南
keywords:
  - APISIX
  - APISIX 升级指南
  - APISIX 版本升级
description: 本文档将引导你了解如何升级 APISIX 版本。
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

## APISIX 的版本升级方式

APISIX 的版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)，版本号格式为：主版本号.次版本号.修订号，例如：2.15.0。

升级到 APISIX 3.0.0 是一个重大的版本升级，我们建议您先升级到 2.15.0，然后再升级到 3.0.0。

## 升级到 2.15.0

从 2.x 升级到 2.15.0，你可以参考 [ChangeLog](./CHANGELOG.md#2150)，主要包括以下内容：

- Change：不兼容的修改
- Core：核心功能更新
- Plugin：插件更新
- Bugfix：修复 bug

其中尤其需要关注的是 Change 部分，这里列出了一些重要的修改：

- grpc 状态码 OUT_OF_RANGE 如今会在 grpc-transcode 插件中作为 http 状态码 400: [#7419](https://github.com/apache/apisix/pull/7419)
- 重命名 `etcd.health_check_retry` 配置项为 `startup_retry`。 [#7304](https://github.com/apache/apisix/pull/7304)
- 移除 `upstream.enable_websocket`。该配置已于 2020 年标记成已过时。 [#7222](https://github.com/apache/apisix/pull/7222)
- 为了适应 OpenTelemetry 规范的变化，OTLP/HTTP 的默认端口改为 4318: [#7007](https://github.com/apache/apisix/pull/7007)
- 更正 syslog 插件的配置 [#6551](https://github.com/apache/apisix/pull/6551)
- server-info 插件使用新方法来上报 DP 面信息 [#6202](https://github.com/apache/apisix/pull/6202)
- Admin API 返回的空 nodes 应当被编码为数组 [#6384](https://github.com/apache/apisix/pull/6384)
- 更正 prometheus 统计指标 apisix_nginx_http_current_connections{state="total"} [#6327](https://github.com/apache/apisix/pull/6327)
- 不再默认暴露 public API 并移除 plugin interceptor [#6196](https://github.com/apache/apisix/pull/6196)
- 重命名 serverless 插件的 "balancer" phase 为 "before_proxy" [#5992](https://github.com/apache/apisix/pull/5992)
- 不再承诺支持 Tengine [#5961](https://github.com/apache/apisix/pull/5961)
- 当 L4 支持 和 Admin API 都启用时，自动开启 HTTP 支持 [#5867](https://github.com/apache/apisix/pull/5867)
- wolf-rbac 插件变更默认端口，并在文档中增加 authType 参数 [#5477](https://github.com/apache/apisix/pull/5477)
- 将 enable_debug 配置从 config.yaml 移到 debug.yaml [#5046](https://github.com/apache/apisix/pull/5046)
- 更改自定义 lua_shared_dict 配置的名称 [#5030](https://github.com/apache/apisix/pull/5030)
- 不再提供 APISIX 安装 shell 脚本 [#4985](https://github.com/apache/apisix/pull/4985)

### 如何根据 Change 来升级

你需要理解 ChangeLog 中的内容，然后根据你的实际情况来决定是否需要修改你的配置。

#### 更新配置文件

以 [#7304](https://github.com/apache/apisix/pull/7304) 为例，你可以在你的当前版本的配置文件中搜索 `etcd.health_check_retry`，如果有对应的配置，那么在升级 APISIX 的版本到 2.15.0 后，你需要将这个配置项改为 `startup_retry`。如果你的配置文件中没有对应的配置，那么你就不需要做任何修改。

#### 更新动态数据

以 [#6551](https://github.com/apache/apisix/pull/6551) 为例，如果你使用了 syslog 插件，并且配置了 `max_retry_times` 和 `retry_interval` 属性，那么升级到 2.15.0 后，你需要将 `syslog` 插件的配置中的 `max_retry_times` 字段改为 `max_retry_times`，并将 `retry_interval` 字段改为 `retry_delay`。如果你在很多路由中使用了 syslog 插件，那么你需要手动更新这些配置，或者自己编写脚本来统一修改。目前，我们还没有提供脚本来帮助你完成这个工作。

#### 更新业务逻辑

以 [#6196](https://github.com/apache/apisix/pull/6196) 为例，如果你基于 Admin API 开发了契合自己业务系统的管理界面，或者使用开源插件的 public API，或者开发自己的私有插件且使用了 public API，那么你需要理解这个 Change，然后根据你的实际情况来决定是否需要修改你的代码。

比如你使用了 jwt-auth 插件，并且使用了其 public API（默认为 `/apisix/plugin/jwt/sign`） 来签发 jwt，那么升级到 2.15.0 后，你需要为 jwt-auth 插件的 public API 配置一个路由，然后将你的代码中的请求地址修改为这个路由的地址。具体参考 [注册公共接口](./plugin-develop.md#注册公共接口)。

## 升级到 3.0.0

### 升级注意事项和重大更新

在升级之前，请查看 [3.0.0-beta](./CHANGELOG.md#300-beta) 和 [3.0.0](./CHANGELOG.md#300) 中的 Change 部分以了解 3.0.0 版本的不兼容的修改与重大更新。

#### 部署

基于 alpine 的镜像已不再支持，如果你使用了 alpine 的镜像，那么你需要将镜像替换为基于 debian/centos 的镜像。

目前，我们提供了：

- 基于 debian/centos 的镜像，你可以在 [DockerHub](https://hub.docker.com/r/apache/apisix/tags?page=1&ordering=last_updated) 上找到它们；
- CentOS 7 和 CentOS 8 的 RPM 包，支持 amd64 和 arm64 架构，参考 [通过 RPM 仓库安装](./installation-guide.md#通过-rpm-仓库安装)；
- Debian 11(bullseye) 的 DEB 包，支持 amd64 和 arm64 架构，参考 [通过 DEB 仓库安装](./installation-guide.md#通过-deb-仓库安装)。

部署相关的配置被移动到了顶级目录 `deployment` 下，具体参考 [移动 config_center、etcd 和 Admin API 的配置到 deployment 下面](./CHANGELOG.md#移动-config_centeretcd-和-admin-api-的配置到-deployment-下面)。

3.0.0 对部署模式做了重大更新，具体如下：

- 支持数据面与控制面分离的部署模式，请参考 [Decoupled](../../en/latest/deployment-modes.md#decoupled)；
- 如果需要继续使用原来的部署模式，那么可以使用部署模式中的 `traditional` 模式，并且更新配置文件，请参考 [Traditional](../../en/latest/deployment-modes.md#traditional)；
- 继续支持 Standalone 模式，需要更新配置文件，请参考 [Standalone](../../en/latest/deployment-modes.md#standalone)。

#### 依赖项

如果你使用提供的二进制包（Debian 和 RHEL），或者镜像，则它们已经捆绑了 APISIX 所有必要的依赖项，你可以跳过本节。

APISIX 的一些特性需要在 OpenResty 中引入额外的 NGINX 模块。如果要使用这些功能，你需要构建一个自定义的 OpenResty 发行版（APISIX-Base）。你可以参考 [api7/apisix-build-tools](https://github.com/api7/apisix-build-tools) 中的代码，构建自己的 APISIX-Base 环境。

如果你希望 APISIX 运行在原生的 OpenResty 上，那么只支持 OpenResty 1.19.3.2 及以上的版本。

#### 迁移

我们并未提供数据备份和迁移的工具，如果你需要备份与恢复数据，可以利用 ETCD 的备份与恢复功能，参考 [etcdctl snapshot](https://etcd.io/docs/v3.5/op-guide/maintenance/#snapshot-backup)。
