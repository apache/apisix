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

# 安装依赖
- [CentOS 6](#centos-6)
- [CentOS 7](#centos-7)
- [Fedora 31 & 32](#fedora-31--32)
- [Ubuntu 16.04 & 18.04](#ubuntu-1604--1804)
- [Debian 9 & 10](#debian-9--10)
- [Mac OSX](#mac-osx)
- [如何编译 Openresty](#如何编译-openresty)
- [注意](#注意)

CentOS 6
========

```shell
# 添加 OpenResty 源
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo

# 安装 OpenResty, etcd 和 编译工具
sudo yum install -y openresty curl git gcc luarocks lua-devel make

wget https://github.com/etcd-io/etcd/releases/download/v3.3.13/etcd-v3.3.13-linux-amd64.tar.gz
tar -xvf etcd-v3.3.13-linux-amd64.tar.gz && \
    cd etcd-v3.3.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# 开启 etcd server
nohup etcd &
```

CentOS 7
========

```shell
# 安装 epel, `luarocks` 需要它
wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo rpm -ivh epel-release-latest-7.noarch.rpm

# 添加 OpenResty 源
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo

# 安装 OpenResty, etcd 和 编译工具
sudo yum install -y etcd openresty curl git gcc luarocks lua-devel

# 开启 etcd server
sudo service etcd start
```

Fedora 31 & 32
==============

```shell
# add OpenResty source
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/fedora/openresty.repo

# install OpenResty, etcd and some compilation tools
sudo yum install -y etcd openresty curl git gcc luarocks lua-devel

# start etcd server
sudo etcd --enable-v2=true &
```

Ubuntu 16.04 & 18.04
====================

```shell
# 添加 OpenResty 源
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
sudo apt-get update

# 安装 OpenResty, etcd 和 编译工具
sudo apt-get install -y git etcd openresty curl luarocks

# 开启 etcd server
sudo service etcd start
```

Debian 9 & 10
=============

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
wget https://github.com/etcd-io/etcd/releases/download/v3.3.13/etcd-v3.3.13-linux-amd64.tar.gz
tar -xvf etcd-v3.3.13-linux-amd64.tar.gz && \
    cd etcd-v3.3.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# 安装 OpenResty, etcd 和 编译工具
sudo apt-get install -y git openresty curl luarocks make

# 开启 etcd server
nohup etcd &
```

Mac OSX
=======

```shell
# 安装 OpenResty, etcd 和 编译工具
brew install openresty/brew/openresty etcd luarocks curl git

# 开启 etcd server 并启用 v2 的功能
etcd --enable-v2=true &
```

如何编译 Openresty
============================

编译 Openresty 是一件比较复杂的事情，没办法简单地说明白。所以我们推荐你直接参考官方的安装文档。

http://openresty.org/en/linux-packages.html

注意
====
- Apache APISIX 目前只支持 `v2` 版本的 etcd，但是最新版的 etcd (从 3.4 起)已经默认关闭了 `v2` 版本的功能。所以你需要添加启动参数 `--enable-v2=true` 来开启 `v2` 的功能，目前对 `v3` etcd 的开发工作已经启动，不久后便可投入使用。

- 如果你要想使用 Tengine 替代 OpenResty，请参考 [Install Tengine at Ubuntu](../../.travis/linux_tengine_runner.sh)。
