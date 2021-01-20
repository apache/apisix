#!/usr/bin/env bash
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

#!/bin/bash

set -ex

export PATH=/usr/local/openresty-debug/nginx/sbin:/usr/local/openresty-debug/bin:$PATH
yum install -y wget tar curl git which

# install lua-devel
wget http://mirror.centos.org/altarch/7/os/aarch64/Packages/lua-devel-5.1.4-15.el7.aarch64.rpm
yum install -y lua-devel-5.1.4-15.el7.aarch64.rpm

# install lua and luarocks
yum install -y libtermcap-devel ncurses-devel libevent-devel readline-devel
wget http://www.lua.org/ftp/lua-5.3.5.tar.gz
tar -zxf lua-5.3.5.tar.gz
cd lua-5.3.5
make linux
make install

wget https://luarocks.org/releases/luarocks-3.3.1.tar.gz
tar zxpf luarocks-3.3.1.tar.gz
cd luarocks-3.3.1
./configure --with-lua-include=/usr/local/include
make install

# install openresty-debug
wget https://openresty.org/package/centos/openresty.repo
mv openresty.repo /etc/yum.repos.d/
yum check-update || true
yum install -y openresty-debug

# install etcdctl
export RELEASE="3.4.13"
wget https://github.com/etcd-io/etcd/releases/download/v${RELEASE}/etcd-v${RELEASE}-linux-arm64.tar.gz
tar xvf etcd-v${RELEASE}-linux-arm64.tar.gz
cd etcd-v${RELEASE}-linux-arm64
mv etcd etcdctl /usr/local/bin
export ETCD_UNSUPPORTED_ARCH=arm64
nohup etcd &

# install test::nginx
yum install -y cpanminus perl
cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)

# install apisix
export PATH=/usr/local/openresty-debug/nginx/sbin:/usr/local/openresty-debug/bin:$PATH
mkdir -p /usr
cd /usr
git clone https://github.com/apache/apisix.git
cd apisix
git submodule update --init --recursive
make deps
make init
git clone https://github.com/iresty/test-nginx.git test-nginx

# run test cases
prove -Itest-nginx/lib -I./ -r t/
