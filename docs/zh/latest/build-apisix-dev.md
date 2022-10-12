---
title: 快速构建开发环境
keywords:
  - API 网关
  - 快速构建开发环境
  - Docker
description: 本文介绍了如何通过 Docker 快速构建 Apache APISIX 的开发环境，并运行测试案例。
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

## 描述

本文介绍了如何通过 Docker 快速构建 Apache APISIX 的开发环境，并运行测试案例。

## 原理简介

通过使用 Docker 运行 APISIX 开发环境，通过挂载 APISIX 项目目录，在 APISIX 开发环境的容器中运行测试案例。实现原理如下：

![Schematic](https://static.apiseven.com/2022/10/12/63465cd4698ba.jpg)

## 前提条件

- 请确保已经安装 [Docker](https://docs.docker.com/get-docker/)。
- 请确保已经安装 [make](https://docs.gitea.io/zh-cn/make/) 命令。
- 请确保已经安装 [Git](https://git-scm.com/downloads)。

## 平台支持

- x86、ARM 架构
- RHEL、CentOS、Ubuntu、macOS（包括 M1、M2）、Windows 等操作系统。

## 操作步骤

通过以下步骤，你可以在当前主机中启动 APISIX 的开发环境并运行 APISIX 测试案例。

### 环境准备

1. 下载 APISIX ，并进入 APISIX 目录。

    ```shell
    git clone https://github.com/apache/apisix.git
    cd apisix
    ```

2. 下载依赖子项目。

    ```
    git submodule update --init --recursive
    ```

    :::note 注意

    请执行以上命令，否则会导致无法正常运行测试案例。

    :::

3. 根据需要创建一个新的分支。

    以下命令将会创建一个名为 `apisix-dev-test` 的分支。

    ```
    git checkout -b apisix-dev-test upstream/master
    ```

    完成上述步骤后，你可以开始构建 APISIX 开发环境的镜像。

### 构建开发环境镜像

你可以通过以下命令构建 APISIX 开发环境的 Docker 镜像。

- x86 架构主机请运行以下命令：

    ```shell
    make build-dev
    ```

- ARM 架构主机请运行以下命令：

    ```shell
    make build-dev-arm
    ```

    :::tip 提示

    以上命令执行结束后，将会在当前主机中创建一个名为 `apisix-dev:latest` 镜像。在同一台主机上，该命令仅需运行一次。

    :::

返回以下结果则表示构建成功：

```shell
......
Successfully built 3224b25e55db
Successfully tagged apisix-dev:latest
```

:::note 注意

在 Windows 系统中，执行 make 命令可能会有如下错误，可忽略该提示。

```
系统找不到指定的路径。
系统找不到指定的路径。
'uname' 不是内部或外部命令，也不是可运行的程序或批处理文件。
```

:::

### 启动开发环境

使用以下命令将会启动一个 APISIX 开发环境的容器和 etcd 容器，并且将会下载相关依赖。

    ```shell
    make run-dev
    ```
返回结果如下则表示正常启动：

```
....

lua-resty-ldap 0.1.0-0 is now installed in /usr/local/apisix/deps (license: Apache License 2.0)

Stopping after installing dependencies for apisix master-0
```

### 运行测试案例

在运行测试案例时，你需要指定需要运行的测试用例，可以是一个目录，也可以是一个单独的文件。

你可以通过以下命令运行单个 APISIX 测试案例：

```shell
make test-dev files=t/admin/routes.t
```

你也可以通过以下命令运行一个目录内的测试案例：

```shell
make test-dev files=t/admin/
```

### 关闭开发环境

当运行完成测试案例后，如果你暂时不需要使用该开发环境，你可以运行以下命令停止 APISIX 开发环境的容器。

```shell
make stop-dev
```

:::warning 警告

该命令会删除 etcd 和 apisix-dev 容器。如果你正在使用该容器，请谨慎执行。

:::

## 更多信息

通过以上步骤，相信你已经知道如何快速构建 APISIX 开发环境，你可以参考如下文档开发 APISIX：

- [APISIX 插件开发](https://apisix.apache.org/docs/apisix/plugin-develop/)
- [External Plugin](https://apisix.apache.org/zh/docs/apisix/external-plugin/)
- [APISIX 测试框架](https://apisix.apache.org/zh/docs/apisix/internal/testing-framework/)
