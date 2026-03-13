---
id: building-apisix
title: Building APISIX from source
keywords:
  - API Gateway
  - Apache APISIX
  - Code Contribution
  - Building APISIX
description: Guide for building and running APISIX locally for development.
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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

If you are looking to setup a development environment or contribute to APISIX, this guide is for you.

If you are looking to quickly get started with APISIX, check out the other [installation methods](./installation-guide.md).

:::note

To build an APISIX docker image from source code, see [build image from source code](https://apisix.apache.org/docs/docker/build/#build-an-image-from-customizedpatched-source-code).

To build and package APISIX for a specific platform, see [apisix-build-tools](https://github.com/api7/apisix-build-tools) instead.

:::

## Building APISIX from source

First of all, we need to specify the branch to be built:

```shell
APISIX_BRANCH='release/3.14'
```

Then, you can run the following command to clone the APISIX source code from Github:

```shell
git clone --depth 1 --branch ${APISIX_BRANCH} https://github.com/apache/apisix.git apisix-${APISIX_BRANCH}
```

Alternatively, you can also download the source package from the [Downloads](https://apisix.apache.org/downloads/) page. Note that source packages here are not distributed with test cases.

Before installation, install [OpenResty](https://openresty.org/en/installation.html).

Next, navigate to the directory, install dependencies, and build APISIX.

```shell
cd apisix-${APISIX_BRANCH}
make deps
make install
```

This will install the runtime-dependent Lua libraries and `apisix-runtime` the `apisix` CLI tool.

:::note

If you get an error message like `Could not find header file for LDAP/PCRE/openssl` while running `make deps`, use this solution.

`luarocks` supports custom compile-time dependencies (See: [Config file format](https://github.com/luarocks/luarocks/wiki/Config-file-format)). You can use a third-party tool to install the missing packages and add its installation directory to the `luarocks`' variables table. This method works on macOS, Ubuntu, CentOS, and other similar operating systems.

The solution below is for macOS but it works similarly for other operating systems:

1. Install `openldap` by running:

   ```shell
   brew install openldap
   ```

2. Locate the installation directory by running:

   ```shell
   brew --prefix openldap
   ```

3. Add this path to the project configuration file by any of the two methods shown below:
   1. You can use the `luarocks config` command to set `LDAP_DIR`:

      ```shell
      luarocks config variables.LDAP_DIR /opt/homebrew/cellar/openldap/2.6.1
      ```

   2. You can also change the default configuration file of `luarocks`. Open the file `~/.luaorcks/config-5.1.lua` and add the following:

      ```shell
      variables = { LDAP_DIR = "/opt/homebrew/cellar/openldap/2.6.1", LDAP_INCDIR = "/opt/homebrew/cellar/openldap/2.6.1/include", }
      ```

      `/opt/homebrew/cellar/openldap/` is default path `openldap` is installed on Apple Silicon macOS machines. For Intel machines, the default path is  `/usr/local/opt/openldap/`.

:::

To uninstall the APISIX runtime, run:

```shell
make uninstall
make undeps
```

:::danger

This operation will remove the files completely.

:::

## Installing etcd

APISIX uses [etcd](https://github.com/etcd-io/etcd) to save and synchronize configuration. Before running APISIX, you need to install etcd on your machine. Installation methods based on your operating system are mentioned below.

<Tabs
  groupId="os"
  defaultValue="linux"
  values={[
    {label: 'Linux', value: 'linux'},
    {label: 'macOS', value: 'mac'},
  ]}>
<TabItem value="linux">

```shell
ETCD_VERSION='3.4.18'
wget https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
tar -xvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz && \
  cd etcd-v${ETCD_VERSION}-linux-amd64 && \
  sudo cp -a etcd etcdctl /usr/bin/
nohup etcd >/tmp/etcd.log 2>&1 &
```

</TabItem>

<TabItem value="mac">

```shell
brew install etcd
brew services start etcd
```

</TabItem>
</Tabs>

## Running and managing APISIX server

To initialize the configuration file, within the APISIX directory, run:

```shell
apisix init
```

:::tip

You can run `apisix help` to see a list of available commands.

:::

You can then test the created configuration file by running:

```shell
apisix test
```

Finally, you can run the command below to start APISIX:

```shell
apisix start
```

To stop APISIX, you can use either the `quit` or the `stop` subcommand.

`apisix quit` will gracefully shutdown APISIX. It will ensure that all received requests are completed before stopping.

```shell
apisix quit
```

Where as, the `apisix stop` command does a force shutdown and discards all pending requests.

```shell
apisix stop
```

## Building runtime for APISIX

Some features of APISIX requires additional Nginx modules to be introduced into OpenResty.

To use these features, you need to build a custom distribution of OpenResty (apisix-runtime). See [apisix-build-tools](https://github.com/api7/apisix-build-tools) for setting up your build environment and building it.

## Running tests

The steps below show how to run the test cases for APISIX:

1. Install [cpanminus](https://metacpan.org/pod/App::cpanminus#INSTALLATION), the package manager for Perl.
2. Install the [test-nginx](https://github.com/openresty/test-nginx) dependencies with `cpanm`:

   ```shell
   sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)
   ```

3. Clone the test-nginx source code locally:

   ```shell
   git clone https://github.com/openresty/test-nginx.git
   ```

4. Append the current directory to Perl's module directory by running:

   ```shell
   export PERL5LIB=.:$PERL5LIB
   ```

   You can specify the Nginx binary path by running:

   ```shell
   TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t
   ```

5. Run the tests by running:

   ```shell
   make test
   ```

:::note

Some tests rely on external services and system configuration modification. See [ci/linux_openresty_common_runner.sh](https://github.com/apache/apisix/blob/master/ci/linux_openresty_common_runner.sh) for a complete test environment build.

:::

### Troubleshooting

These are some common troubleshooting steps for running APISIX test cases.

#### Configuring Nginx path

For the error `Error unknown directive "lua_package_path" in /API_ASPIX/apisix/t/servroot/conf/nginx.conf`, ensure that OpenResty is set to the default Nginx and export the path as follows:

- Linux default installation path:

  ```shell
  export PATH=/usr/local/openresty/nginx/sbin:$PATH
  ```

#### Running a specific test case

To run a specific test case, use the command below:

```shell
prove -Itest-nginx/lib -r t/plugin/openid-connect.t
```

See [testing framework](./internal/testing-framework.md) for more details.
