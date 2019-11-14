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

## 通过源码安装
你可以下载 Apache release 包（Apache APISIX 还没有发布 Apache release），
或者从 GitHub 下载源码：

```shell
git clone git@github.com:iresty/apisix.git
```

### install dependency
```
luarocks install --lua-dir=/usr/local/openresty/luajit rockspec/apisix-0.9-0.rockspec --tree=deps --only-deps --local
```

## 通过 RPM 包安装（CentOS 7）
```shell
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
sudo yum install -y openresty etcd
sudo service etcd start

sudo yum install -y https://github.com/apache/incubator-apisix/releases/download/v0.8/apisix-0.8-0.el7.noarch.rpm
```

## 通过 Luarocks 安装 （不支持 macOS）

在终端中执行下面命令完成 APISIX 的安装（只推荐开发者使用）：

> 通过脚本安装 master 分支的代码

```shell
sudo sh -c "$(curl -fsSL https://raw.githubusercontent.com/apache/incubator-apisix/master/utils/install-apisix.sh)"
```

> 通过 Luarocks 安装指定的版本:

```shell
# 安装 apisix 的 0.8 版本
sudo luarocks install --lua-dir=/path/openresty/luajit apisix 0.8

# 老版本 luarocks 可能不支持 `lua-dir` 参数，可以删除该选项
sudo luarocks install apisix 0.8
```

> 安装完成

```
    apisix 0.8-0 is now built and installed in /usr/local/apisix/deps (license: Apache License 2.0)

    + sudo rm -f /usr/local/bin/apisix
    + sudo ln -s /usr/local/apisix/deps/bin/apisix /usr/local/bin/apisix
```
