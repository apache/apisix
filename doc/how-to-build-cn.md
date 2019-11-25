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
# 构建 Apache APISIX

## 1. 安装依赖
Apache APISIX 的运行环境需要 Nginx 和 etcd，

所以在安装前，请根据不同的操作系统来[安装依赖](install-dependencies.md)。

## 2. 安装 Apache APISIX

你可以通过源码包、Docker、Luarocks 等多种方式来安装 Apache APISIX。

### 通过源码候选版本安装

你需要先下载源码候选版本：

```shell
wget https://dist.apache.org/repos/dist/dev/incubator/apisix/0.9-RC1/apache-apisix-0.9-rc1-incubating-src.tar.gz
tar zxvf apache-apisix-0.9-rc1-incubating-src.tar.gz
```

安装运行时依赖的 Lua 库：
```
cd apache-apisix-0.9-rc1-incubating
make deps
```

### 通过 RPM 包安装（CentOS 7）

```shell
sudo yum install -y https://github.com/apache/incubator-apisix/releases/download/v0.8/apisix-0.8-0.el7.noarch.rpm
```

### 通过 Luarocks 安装 （不支持 macOS）

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

## 3. 管理（启动、关闭等）APISIX 服务

我们可以在 apisix 的目录下用 `make run` 命令来启动服务，或者用 `make stop` 方式关闭服务。

```shell
# init nginx config file and etcd
$ make init

# start APISIX server
$ make run

# stop APISIX server
$ make stop

# more actions find by `help`
$ make help
Makefile rules:

    help:          Show Makefile rules.
    deps:          Installation dependencies
    utils:         Installation tools
    lint:          Lint Lua source code
    init:          Initialize the runtime environment
    run:           Start the apisix server
    stop:          Stop the apisix server
    clean:         Remove generated files
    reload:        Reload the apisix server
    install:       Install the apisix
    test:          Run the test case
    license-check: Check lua souce code for Apache License
```

## 4. 运行测试案例

1. 先安装 perl 的包管理器 cpanminus
2. 然后通过 cpanm 来安装 test-gninx：`sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)`
3. 然后 clone 最新的源码：`git clone https://github.com/openresty/test-nginx.git`
4. 通过 perl 的 `prove` 命令来加载 test-nginx 的库，并运行 `/t` 目录下的测试案例集：
    * 直接运行：`prove -Itest-nginx/lib -r t`
    * 指定 nginx 二进制路径：`TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`
