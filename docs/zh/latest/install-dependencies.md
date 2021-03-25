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

- [注意](#注意)
- [CentOS 7](#centos-7)
- [Fedora 31 & 32](#fedora-31--32)
- [Ubuntu 16.04 & 18.04](#ubuntu-1604--1804)
- [Debian 9 & 10](#debian-9--10)
- [Mac OSX](#mac-osx)

## 注意

- Apache APISIX 从 v2.0 开始不再支持 `v2` 版本的 etcd，并且 etcd 最低支持版本为 v3.4.0，因此请使用 etcd 3.4.0+。更重要的是，因为 etcd v3 使用 gPRC 作为消息传递协议，而 Apache APISIX 使用 HTTP(S) 与 etcd 集群通信，因此请确保启用 [etcd gRPC gateway](https://etcd.io/docs/v3.4.0/dev-guide/api_grpc_gateway/) 功能。

- 目前 Apache APISIX 默认使用 HTTP 协议与 etcd 集群通信，这并不安全，如果希望保障数据的安全性和完整性。 请为您的 etcd 集群配置证书及对应私钥，并在您的 Apache APISIX etcd endpoints 配置列表中明确使用 `https` 协议前缀。请查阅 `conf/config-default.yaml` 中 etcd 一节相关的配置来了解更多细节。

- 如果你要想使用 Tengine 替代 OpenResty，请参考 [Install Tengine at Ubuntu](https://github.com/apache/apisix/blob/master/.travis/linux_tengine_runner.sh)。

- 如果是 OpenResty 1.19，APISIX 会使用 OpenResty 内置的 LuaJIT 来运行 `bin/apisix`；否则会使用 Lua 5.1。如果运行过程中遇到 `luajit: lj_asm_x86.h:2819: asm_loop_fixup: Assertion '((intptr_t)target & 15) == 0' failed`，这是低版本 OpenResty 内置的 LuaJIT 在特定编译条件下的问题。

- 在某些平台上，通过包管理器安装 LuaRocks 会导致 Lua 被升级为 Lua 5.3，所以我们建议通过源代码的方式安装 LuaRocks。如果你通过官方仓库安装 OpenResty 和 OpenResty 的 OpenSSL 开发库（rpm 版本：openresty-openssl111-devel，deb 版本：openresty-openssl111-dev），那么 [我们提供了自动安装的脚本](https://github.com/apache/apisix/tree/master/utils/linux-install-luarocks.sh)。如果你是自己编译的 OpenResty，可以参考上述脚本并修改里面的路径。如果编译时没有指定 OpenSSL 库的路径，那么无需配置 LuaRocks 内跟 OpenSSL 相关的变量，因为默认都是用的系统自带的 OpenSSL。如果编译时指定了 OpenSSL 库，那么需要保证 LuaRocks 的 OpenSSL 配置跟 OpenResty 的相一致。

- 警告：如果你正在使用低于 `1.17.8` 的 OpenResty 版本，请安装 openresty-openssl-devel，而不是 openresty-openssl111-devel。

## CentOS 7

```shell
# 安装 etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
tar -xvf etcd-v3.4.13-linux-amd64.tar.gz && \
    cd etcd-v3.4.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# 添加 OpenResty 源
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo

# 安装 OpenResty 和 编译工具
sudo yum install -y openresty curl git gcc openresty-openssl111-devel unzip

# 安装 LuaRocks
curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -

# 开启 etcd server
nohup etcd &
```

## Fedora 31 & 32

```shell
# 添加 OpenResty 源
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/fedora/openresty.repo

# 安装 etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
tar -xvf etcd-v3.4.13-linux-amd64.tar.gz && \
    cd etcd-v3.4.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# 安装 OpenResty 和 编译工具
sudo yum install -y openresty curl git gcc openresty-openssl111-devel

# 安装 LuaRocks
curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -

# 开启 etcd server
nohup etcd &
```

## Ubuntu 16.04 & 18.04

```shell
# 添加 OpenResty 源
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
sudo apt-get update

# 安装 etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
tar -xvf etcd-v3.4.13-linux-amd64.tar.gz && \
    cd etcd-v3.4.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# 安装 OpenResty 和 编译工具
sudo apt-get install -y git openresty curl openresty-openssl111-dev

# 安装 LuaRocks
curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -

# 开启 etcd server
nohup etcd &
```

## Debian 9 & 10

```shell
# 可选
sed -i 's|^deb http://deb.debian.org/debian|deb http://mirrors.huaweicloud.com/debian|g' /etc/apt/sources.list
sed -i 's|^deb http://security.debian.org/debian-security|deb http://mirrors.huaweicloud.com/debian-security|g' /etc/apt/sources.list
apt update
apt install wget gnupg -y

# 添加 OpenResty 源
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/debian $(lsb_release -sc) openresty"
sudo apt-get update

# 安装 etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
tar -xvf etcd-v3.4.13-linux-amd64.tar.gz && \
    cd etcd-v3.4.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# 安装 OpenResty 和 编译工具
sudo apt-get install -y git openresty curl make openresty-openssl111-dev

# 安装 LuaRocks
curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -

# 开启 etcd server
nohup etcd &
```

## Mac OSX

```shell
# 安装 OpenResty, etcd 和 编译工具
brew install openresty/brew/openresty luarocks lua@5.1 etcd curl git

# 开启 etcd server
brew services start etcd

# 为 etcd 服务启用 TLS
etcd --cert-file=/path/to/cert --key-file=/path/to/pkey --advertise-client-urls https://127.0.0.1:2379
```
