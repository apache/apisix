---
title: Installing Apache APISIX
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

This guide walks you through how you can build and get Apache APISIX running on your environment. Please refer the [Getting Started](./getting-started.md) guide for a quick walkthrough on running Apache APISIX.

## Step 1: Install Apache APISIX

Apache APISIX can be installed via the [RPM package](#installation-via-rpm-repository-centos-7), [Docker image](#installation-via-docker), [Helm Chart](#installation-via-helm-chart) or the [source release package](#installation-via-source-release-package). You can install via any one of these options.

### Installation via RPM Repository (CentOS 7)

This installation method is suitable for CentOS 7.

If the official OpenResty repository is **not installed yet**, the following command will help you automatically install both OpenResty and Apache APISIX repositories.

```shell
sudo yum install -y https://repos.apiseven.com/packages/centos/apache-apisix-repo-1.0-1.noarch.rpm
```

If the official OpenResty repository **is installed**, the following command will help you automatically install the repositories of Apache APISIX.

```shell
sudo yum-config-manager --add-repo https://repos.apiseven.com/packages/centos/apache-apisix.repo
```

Run the following commands to install the repository and Apache APISIX.

```shell
# View the information of the latest apisix package
sudo yum info -y apisix

# Will show the existing apisix packages
sudo yum --showduplicates list apisix

# Will install the latest apisix package
sudo yum install apisix

# Will install a specified version (2.10.3 in this example) apisix package
sudo yum install apisix-2.10.3-0.el7
```

### Installation via RPM Offline Package (CentOS 7)

First, download Apache APISIX offline RPM package to `./apisix` folder.

```shell
sudo mkdir -p apisix
sudo yum install -y https://repos.apiseven.com/packages/centos/apache-apisix-repo-1.0-1.noarch.rpm
sudo yum clean all && yum makecache
sudo yum install -y --downloadonly --downloaddir=./apisix apisix
```

Then copy `./apisix` folder to the target host and run the following command to install.

```shell
sudo yum install ./apisix/*.rpm
```

### Installation via Docker

Please refer to [Installing Apache APISIX with Docker](https://hub.docker.com/r/apache/apisix).

### Installation via Helm Chart

Please refer to [Installing Apache APISIX with Helm Chart](https://github.com/apache/apisix-helm-chart).

### Installation via Source Release Package

Note: if you want to package Apache APISIX for a specific platform, please refer to https://github.com/api7/apisix-build-tools and add the support there.
The instruction here is only for people who want to setup their Apache APISIX development environment.

Follow the steps below to install Apache APISIX via the source release package.

1. Install dependencies

  ```shell
  curl https://raw.githubusercontent.com/apache/apisix/master/utils/install-dependencies.sh -sL | bash -
  ```

2. Create a directory named `apisix-2.13.3`.

  ```shell
  APISIX_VERSION='2.13.3'
  mkdir apisix-${APISIX_VERSION}
  ```

3. Download the Apache APISIX source release package.

  ```shell
  wget https://downloads.apache.org/apisix/${APISIX_VERSION}/apache-apisix-${APISIX_VERSION}-src.tgz
  ```

  You can also download the Apache APISIX source release package from the [Apache APISIX website](https://apisix.apache.org/downloads/). The website also provides source packages for Apache APISIX, APISIX Dashboard, and APISIX Ingress Controller.

4. Uncompress the Apache APISIX source release package.

  ```shell
  tar zxvf apache-apisix-${APISIX_VERSION}-src.tgz -C apisix-${APISIX_VERSION}
  ```

5. Install the runtime dependent Lua libraries.

  ```shell
  # Switch to the apisix-${APISIX_VERSION} directory
  cd apisix-${APISIX_VERSION}
  # Create dependencies
  make deps
  # Install apisix command
  make install
  ```

  **Note**: If you fail to install dependency packages using `make deps` and get an error message like `Could not find header file for LDAP/PCRE/openssl`, you can use this general method to solve problems.

  The general solution: `luarocks` supports custom compile-time dependency directories(from this [link](https://github.com/luarocks/luarocks/wiki/Config-file-format)). Use a third-party tool to install the missing package and add its installation directory to the `luarocks`'s variables table. This a general method which can be applied to macOS, Ubuntu, CentOS or other usual operating systems, and the specific solution for macOS are given here for reference only.

  The following is the solution of macOS, which is similar to that of other operating systems:

    1. Install `openldap` with `brew install openldap`;
    2. Locate installation directory with `brew --prefix openldap`;
    3. Add the path to the project configuration file(choose one of the following two methods):
       1. Solution A: You can set `LDAP_DIR` with `luarocks config` manually, for example `luarocks config variables.LDAP_DIR /opt/homebrew/cellar/openldap/2.6.1`;
       2. Solution B: Of course, you can also choose to change the default configuration file of luarocks directly, execute the 'cat ~/.luarocks/config-5.1.lua' command, and then add the installation directory of 'openldap' to the file;
       3. Example as follows:
          variables = {
              LDAP_DIR = "/opt/homebrew/cellar/openldap/2.6.1",
              LDAP_INCDIR = "/opt/homebrew/cellar/openldap/2.6.1/include",
          }

     `/opt/homebrew/cellar/openldap/` is default path to install openldap on macOS(Apple Silicon) using brew.
     `/usr/local/opt/openldap/` is default path to install openldap on macOS(Intel) using brew.

5. To uninstall the Apache APISIX runtime, run:

   ```shell
   # Uninstall apisix command
   make uninstall
   # Purge dependencies
   make undeps
   ```

   **Note**: This operation will remove the files completely.

#### LTS version installation via Source Release Package

The [current LTS version](https://apisix.apache.org/downloads/) of Apache APISIX is `2.13.3`.

To install this version, set `APISIX_VERSION` in [Installation via Source Release Package](#installation-via-source-release-package) to this version and continue with the other steps.

## Step 2: Install etcd

This step is required only if you haven't installed [etcd](https://github.com/etcd-io/etcd).

Run the command below to install etcd via the binary in Linux:

```shell
ETCD_VERSION='3.4.13'
wget https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
tar -xvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz && \
  cd etcd-v${ETCD_VERSION}-linux-amd64 && \
  sudo cp -a etcd etcdctl /usr/bin/
nohup etcd >/tmp/etcd.log 2>&1 &
```

Run the command below to install etcd in Mac:

```shell
brew install etcd
# start etcd server
brew services start etcd
```

## Step 3: Manage Apache APISIX Server

In the Apache APISIX directory, you can initialize dependencies, start service and stop service with commands. Run `apisix help` to get a full list of available commands.

### Initializing dependencies

Run the following command to initialize the NGINX configuration file and etcd.

```shell
# initialize NGINX config file and etcd
apisix init
```

### Test the configuration file

Run the following command to test the configuration file. APISIX will generate `nginx.conf` from `config.yaml` and check whether the syntax of `nginx.conf` is correct.

```shell
# generate `nginx.conf` from `config.yaml` and test it
apisix test
```

### Start Apache APISIX

Run the following command to start Apache APISIX.

```shell
# start Apache APISIX server
apisix start
```

### Stop Apache APISIX

Both `apisix quit` and `apisix stop` can stop Apache APISIX. The main difference is that `apisix quit` stops Apache APISIX gracefully, while `apisix stop` stops Apache APISIX immediately.

It is recommended to use the "gracefully stop" command `apisix quit` because it ensures that Apache APISIX will complete all the requests it has received before stopping. On the other hand, `apisix stop` will trigger a forced shutdown and will stop Apache APISIX immediately. This will cause the pending incoming requests to not be processed before shutdown.

To perform a graceful shutdown, run:

```shell
# stop Apache APISIX server gracefully
apisix quit
```

To perform a forced shutdown, run:

```shell
# stop Apache APISIX server immediately
apisix stop
```

### Other operations

You can get help and learn more about all the available operations in Apache APISIX by running the `help` command as shown below.

```shell
# show a list of available operations
apisix help
```

## Step 4: Run Test Cases

To run the test cases, run the steps outlined below.

1. [Install `cpanminus`](https://metacpan.org/pod/App::cpanminus#INSTALLATION), the package manager for `perl`.

2. Install the test-nginx dependencies via `cpanm` as shown below.

  ```shell
  sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)
  ```

3. Clone the latest source code locally by using the forked out version.

  ```shell
  git clone https://github.com/openresty/test-nginx.git
  ```

4. There are two ways to run the tests.

  1. Append the current directory to the perl module directory: `export PERL5LIB=.:$PERL5LIB` and then run `make test` command.

  2. Specify the NGINX binary path by running `TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`.

  <!--
  #
  #    In addition to the basic Markdown syntax, we use remark-admonitions
  #    alongside MDX to add support for admonitions. Admonitions are wrapped
  #    by a set of 3 colons.
  #    Please refer to https://docusaurus.io/docs/next/markdown-features/admonitions
  #    for more detail.
  #
  -->

  :::note Note
  Some of the tests rely on external services and system configuration modification. For a complete test environment build, you can refer to `ci/linux_openresty_common_runner.sh`.
  :::

### Troubleshoot testing

#### Configuring NGINX path

The solution to the `Error unknown directive "lua_package_path" in /API_ASPIX/apisix/t/servroot/conf/nginx.conf` error is as shown below.

Ensure that OpenResty is set to the default NGINX, and export the path as follows:

* `export PATH=/usr/local/openresty/nginx/sbin:$PATH`
  * Linux default installation path:
    * `export PATH=/usr/local/openresty/nginx/sbin:$PATH`
  * MacOS default installation path via homebrew:
    * `export PATH=/usr/local/opt/openresty/nginx/sbin:$PATH`

#### Running a single test case

To run a specific test case, use the command below.

```shell
prove -Itest-nginx/lib -r t/plugin/openid-connect.t
```

For more details on the test cases, see the [testing framework](https://github.com/apache/apisix/blob/master/docs/en/latest/internal/testing-framework.md) document.

## Step 5: Update Admin API token to Secure Apache APISIX

You can modify the Admin API key to secure your Apache APISIX deployment.

This can be done by modifying the `apisix.admin_key` in `conf/config.yaml` and restarting the service.

```yaml
apisix:
  # ... ...
  admin_key
    -
      name: "admin"
      key: abcdefghabcdefgh # Modify the original key to abcdefghabcdefgh
      role: admin
```

Then to access the Admin API, you can use the above key.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes?api_key=abcdefghabcdefgh -i
```

A status code of 200 in the returned result will indicate that the access was successful.

```shell
HTTP/1.1 200 OK
Date: Fri, 28 Feb 2020 07:48:04 GMT
Content-Type: text/plain
... ...
{"node":{...},"action":"get"}
```

If the key you entered does not match the value of `apisix.admin_key` in `conf/config.yaml`, a response with a status code 401 will indicate that the access failed.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes?api_key=wrong-key -i
```

```shell
HTTP/1.1 401 Unauthorized
Date: Fri, 28 Feb 2020 08:17:58 GMT
Content-Type: text/html
... ...
{"node":{...},"action":"get"}
```

## Step 6: Build OpenResty for Apache APISIX

Some features require additional NGINX modules to be introduced into OpenResty.

If you need these features, you can build APISIX OpenResty. You can refer to the source of [api7/apisix-build-tools](https://github.com/api7/apisix-build-tools) for setting up your build environment and building APISIX OpenResty.

## Step 7: Add Systemd unit file for Apache APISIX

If you are using CentOS 7 and you installed [Apache APISIX via the RPM package](#installation-via-rpm-repository-centos-7), the configuration file will already be in place and you can run the following command directly.

```shell
systemctl start apisix
systemctl stop apisix
```

If you installed Apache APISIX by other methods, please refer to the [configuration file template](https://github.com/api7/apisix-build-tools/blob/master/usr/lib/systemd/system/apisix.service) for a modification guide and copy it to the `/usr/lib/systemd/system/apisix.service` path.
