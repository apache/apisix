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

# Build Apache APISIX

## 1. Install dependencies
The runtime environment for Apache APISIX requires Nginx and etcd.

So before installation, please follow the different operating systems [install Dependencies](install-dependencies.md).

## 2. Install Apache APISIX

You can install Apache APISIX in a variety of ways, including source code packages, Docker, and Luarocks.

### Installation via source release

You need to download the Apache source release first:

```shell
wget http://www.apache.org/dist/incubator/apisix/1.1/apache-apisix-1.1-incubating-src.tar.gz
tar zxvf apache-apisix-1.1-incubating-src.tar.gz
```

Install the Lua libraries that the runtime depends on:
```shell
cd apache-apisix-1.1-incubating
make deps
```

### Installation via RPM package (CentOS 7)

```shell
sudo yum install -y https://github.com/apache/incubator-apisix/releases/download/1.1/apisix-1.1-0.el7.noarch.rpm
```

### Installation via Luarocks (macOS not supported)

Execute the following command in the terminal to complete the installation of APISIX (only recommended for developers):

> Install the code for the master branch via a script

```shell
sudo sh -c "$(curl -fsSL https://raw.githubusercontent.com/apache/incubator-apisix/master/utils/install-apisix.sh)"
```

> Install the specified version via Luarocks:

```shell
# Install version 1.1
sudo luarocks install --lua-dir=/path/openresty/luajit apisix 1.1

# old luarocks not support the `lua-dir` parameter, you can remove this option
sudo luarocks install apisix 1.1
```

## Manage (start/stop) APISIX Server

We can start the APISIX server by command `make run` in APISIX home folder,
or we can stop APISIX server by command `make stop`.

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

## Test

1. Install perl's package manager `cpanminus` first
2. Then install `test-gninx` via `cpanm`:：`sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)`
3. Clone source code：`git clone https://github.com/openresty/test-nginx.git`;
4. Load the `test-nginx` library with perl's `prove` command and run the test cases in the `/t` directory:
    * Run the test cases: `prove -Itest-nginx/lib -r t`
    * To set the path of nginx to run the test cases: `TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`
