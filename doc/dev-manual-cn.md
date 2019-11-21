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

#  开发者手册

## 在开发环境搭建 APISIX

不同系统有不同依赖，查看[安装依赖](install-dependencies.md)完成依赖项安装。

如果你是开发人员，可以在完成上面安装依赖项后，通过下面的命令快速搭建本地开发环境。

```shell
# clone project
git clone git@github.com:iresty/apisix.git
cd apisix

# init submodule
git submodule update --init --recursive

# install dependency
make deps
```

如果一切顺利，你会在最后看到这样的信息：

> Stopping after installing dependencies for apisix

下面是预期的开发环境目录结构：

```shell
$ tree -L 2 -d apisix
apisix
├── benchmark
│   ├── fake-apisix
│   └── server
├── bin
├── conf
│   └── cert
├── dashboard
│   ├── css
│   ├── fonts
│   ├── img
│   ├── js
│   └── tinymce
├── deps                    # 依赖的 Lua 和动态库，放在了这里
│   ├── lib64
│   └── share
├── doc
│   ├── images
│   └── plugins
├── logs
├── lua
│   └── apisix
├── rockspec
├── t
│   ├── admin
│   ├── config-center-yaml
│   ├── core
│   ├── lib
│   ├── node
│   ├── plugin
│   ├── router
│   └── servroot
└── utils
```

## 管理（启动、关闭等）APISIX 服务

我们可以在 apisix 的目录下用 `make run` 命令来启动服务，或者用 `make stop` 方式关闭服务。

```shell
# init nginx config file and etcd
$ make init
./bin/apisix init
./bin/apisix init_etcd

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

## 运行测试案例

1. 先安装 perl 的包管理器 cpanminus
2. 然后通过 cpanm 来安装 test-gninx：`sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)`
3. 然后 clone 最新的源码：`git clone https://github.com/openresty/test-nginx.git`
4. 通过 perl 的 `prove` 命令来加载 test-nginx 的库，并运行 `/t` 目录下的测试案例集：
    * 直接运行：`prove -Itest-nginx/lib -r t`
    * 指定 nginx 二进制路径：`TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`
