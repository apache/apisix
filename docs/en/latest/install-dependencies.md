---
title: Install Dependencies
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

- [Note](#note)
- [CentOS 7](#centos-7)
- [Fedora 31 & 32](#fedora-31--32)
- [Ubuntu 16.04 & 18.04](#ubuntu-1604--1804)
- [Debian 9 & 10](#debian-9--10)
- [Mac OSX](#mac-osx)

## Note

- Since v2.0 Apache APISIX would not support the v2 protocol storage to etcd anymore, and the minimum etcd version supported is v3.4.0. What's more, etcd v3 uses gRPC as the messaging protocol, while Apache APISIX uses HTTP(S) to communicate with etcd cluster, so be sure the [etcd gRPC gateway](https://etcd.io/docs/v3.4.0/dev-guide/api_grpc_gateway/) is enabled.

- Now by default Apache APISIX uses HTTP protocol to talk with etcd cluster, which is insecure. Please configure certificate and corresponding private key for your etcd cluster, and use "https" scheme explicitly in the etcd endpoints list in your Apache APISIX configuration, if you want to keep the data secure and integral. See the etcd section in `conf/config-default.yaml` for more details.

- If you want use Tengine instead of OpenResty, please take a look at this installation step script [Install Tengine at Ubuntu](https://github.com/apache/apisix/blob/master/ci/linux_tengine_runner.sh).

- If it is OpenResty 1.19, APISIX will use OpenResty's built-in LuaJIT to run `bin/apisix`; otherwise it will use Lua 5.1. If you encounter `luajit: lj_asm_x86.h:2819: asm_loop_ fixup: Assertion '((intptr_t)target & 15) == 0' failed`, this is a problem with the low version of OpenResty's built-in LuaJIT under certain compilation conditions.

- On some platforms, installing LuaRocks via the package manager will cause Lua to be upgraded to Lua 5.3, so we recommend installing LuaRocks via source code. if you install OpenResty and its OpenSSL develop library (openresty-openssl111-devel for rpm and openresty-openssl111-dev for deb) via the official repository, then [we provide a script for automatic installation](https://github.com/apache/apisix/blob/master/utils/linux-install-luarocks.sh). If you compile OpenResty yourself, you can refer to the above script and change the path in it. If you don't specify the OpenSSL library path when you compile, you don't need to configure the OpenSSL variables in LuaRocks, because the system's OpenSSL is used by default. If the OpenSSL library is specified at compile time, then you need to ensure that LuaRocks' OpenSSL configuration is consistent with OpenResty's.

- WARNING: If you are using OpenResty which is older than `1.17.8`, please installing openresty-openss-devel instead of openresty-openssl111-devel.

- OpenResty is a dependency of APISIX. If it is your first time to deploy APISIX and you don't need to use OpenResty to deploy other services, you can stop and disable OpenResty after installation since it will not affect the normal work of APISIX. Please operate carefully according to your service. For example in Ubuntu: `systemctl stop openresty && systemctl disable openresty`.

## CentOS 7

```shell
# install etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
tar -xvf etcd-v3.4.13-linux-amd64.tar.gz && \
    cd etcd-v3.4.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# add OpenResty source
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo

# install OpenResty and some compilation tools
sudo yum install -y openresty curl git gcc openresty-openssl111-devel unzip

# install LuaRocks
curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -

# start etcd server
nohup etcd &
```

## Fedora 31 & 32

```shell
# add OpenResty source
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/fedora/openresty.repo

# install etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
tar -xvf etcd-v3.4.13-linux-amd64.tar.gz && \
    cd etcd-v3.4.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# install OpenResty and some compilation tools
sudo yum install -y openresty curl git gcc openresty-openssl111-devel

# install LuaRocks
curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -

# start etcd server
nohup etcd &
```

## Ubuntu 16.04 & 18.04

```shell
# add OpenResty source
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
sudo apt-get update

# install etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
tar -xvf etcd-v3.4.13-linux-amd64.tar.gz && \
    cd etcd-v3.4.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# install OpenResty and some compilation tools
sudo apt-get install -y git openresty curl openresty-openssl111-dev make gcc

# install LuaRocks
curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -

# start etcd server
nohup etcd &
```

## Debian 9 & 10

```shell
# optional
sed -i 's|^deb http://deb.debian.org/debian|deb http://mirrors.huaweicloud.com/debian|g' /etc/apt/sources.list
sed -i 's|^deb http://security.debian.org/debian-security|deb http://mirrors.huaweicloud.com/debian-security|g' /etc/apt/sources.list
apt update
apt install wget gnupg -y

# add OpenResty source
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/debian $(lsb_release -sc) openresty"
sudo apt-get update

# install etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
tar -xvf etcd-v3.4.13-linux-amd64.tar.gz && \
    cd etcd-v3.4.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# install OpenResty and some compilation tools
sudo apt-get install -y git openresty curl make openresty-openssl111-dev

# install LuaRocks
curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -

# start etcd server
nohup etcd &
```

## Mac OSX

```shell
# install OpenResty, etcd and some compilation tools
brew install openresty/brew/openresty luarocks lua@5.1 etcd curl git

# start etcd server
brew services start etcd

# enable TLS for etcd server
etcd --cert-file=/path/to/cert --key-file=/path/to/pkey --advertise-client-urls https://127.0.0.1:2379
```
