---
title: 安装依赖
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

## 注意

- Apache APISIX 从 v2.0 开始不再支持 `v2` 版本的 etcd，并且 etcd 最低支持版本为 v3.4.0，因此请使用 etcd 3.4.0+。更重要的是，因为 etcd v3 使用 gRPC 作为消息传递协议，而 Apache APISIX 使用 HTTP(S) 与 etcd 集群通信，因此请确保启用 [etcd gRPC gateway](https://etcd.io/docs/v3.4.0/dev-guide/api_grpc_gateway/) 功能。

- 目前 Apache APISIX 默认使用 HTTP 协议与 etcd 集群通信，这并不安全，如果希望保障数据的安全性和完整性。请为您的 etcd 集群配置证书及对应私钥，并在您的 Apache APISIX etcd endpoints 配置列表中明确使用 `https` 协议前缀。请查阅 `conf/config.yaml.example` 中 `etcd` 一节相关的配置来了解更多细节。

- 如果是 OpenResty 1.19，APISIX 会使用 OpenResty 内置的 LuaJIT 来运行 `bin/apisix`；否则会使用 Lua 5.1。如果运行过程中遇到 `luajit: lj_asm_x86.h:2819: asm_loop_fixup: Assertion '((intptr_t)target & 15) == 0' failed`，这是低版本 OpenResty 内置的 LuaJIT 在特定编译条件下的问题。

- 在某些平台上，通过包管理器安装 LuaRocks 会导致 Lua 被升级为 Lua 5.3，所以我们建议通过源代码的方式安装 LuaRocks。如果你通过官方仓库安装 OpenResty 和 OpenResty 的 OpenSSL 开发库（rpm 版本：openresty-openssl111-devel，deb 版本：openresty-openssl111-dev），那么 [我们提供了自动安装的脚本](https://github.com/apache/apisix/tree/master/utils/linux-install-luarocks.sh)。如果你是自己编译的 OpenResty，可以参考上述脚本并修改里面的路径。如果编译时没有指定 OpenSSL 库的路径，那么无需配置 LuaRocks 内跟 OpenSSL 相关的变量，因为默认都是用的系统自带的 OpenSSL。如果编译时指定了 OpenSSL 库，那么需要保证 LuaRocks 的 OpenSSL 配置跟 OpenResty 的相一致。

- OpenResty 是 APISIX 的一个依赖项，如果是第一次部署 APISIX 并且不需要使用 OpenResty 部署其他服务，可以在 OpenResty 安装完成后停止并禁用 OpenResty，这不会影响 APISIX 的正常工作，请根据自己的业务谨慎操作。例如 Ubuntu：`systemctl stop openresty && systemctl disable openresty`。

## 安装

在支持的操作系统上运行以下指令即可安装 Apache APISIX dependencies。

支持的操作系统版本：Debian 11/12, Ubuntu 20.04/22.04/24.04 等。

注意，对于 Arch Linux 来说，我们使用 AUR 源中的 `openresty`，所以需要 AUR Helper 才能正常安装。目前支持 `yay` 和 `pacaur`。

```
curl https://raw.githubusercontent.com/apache/apisix/master/utils/install-dependencies.sh -sL | bash -
```

如果你已经克隆了 Apache APISIX 仓库，在根目录运行以下指令安装 Apache APISIX dependencies。

```
bash utils/install-dependencies.sh
```
