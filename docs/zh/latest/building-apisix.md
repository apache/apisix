---
id: building-apisix
title: 源码安装 APISIX
keywords:
  - API 网关
  - Apache APISIX
  - 贡献代码
  - 构建 APISIX
  - 源码安装 APISIX
description: 本文介绍了如何在本地使用源码安装 API 网关 Apache APISIX 来构建开发环境。
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

如果你希望为 APISIX 做出贡献或配置开发环境，你可以参考本教程。

如果你想通过其他方式安装 APISIX，你可以参考[安装指南](./installation-guide.md)。

:::note

如果你想为特定的环境或打包 APISIX，请参考 [apisix-build-tools](https://github.com/api7/apisix-build-tools)。

:::

## 源码安装 APISIX

首先，我们需要指定需要安装的版本`APISIX_VERSION`:

```shell
APISIX_BRANCH='release/3.13'
```

然后，你可以运行以下命令，从 Github 克隆 APISIX 源码：

```shell
git clone --depth 1 --branch ${APISIX_BRANCH} https://github.com/apache/apisix.git apisix-${APISIX_BRANCH}
```

你可以从[下载页面](https://apisix.apache.org/downloads/)下载源码包。但是官网的源码包缺少测试用例，可能会对你后续操作产生困扰。

另外，你也可以在该页面找到 APISIX Dashboard 和 APISIX Ingress Controller 的源码包。

安装之前，请安装[OpenResty](https://openresty.org/en/installation.html)。

然后切换到 APISIX 源码的目录，创建依赖项并安装 APISIX，命令如下所示：

```shell
cd apisix-${APISIX_BRANCH}
make deps
make install
```

该命令将安装 APISIX 运行时依赖的 Lua 库以及 `apisix-runtime` 和 `apisix` 命令。

:::note

如果你在运行 `make deps` 时收到类似 `Could not find header file for LDAP/PCRE/openssl` 的错误消息，请使用此解决方案。

`luarocks` 支持自定义编译时依赖项（请参考：[配置文件格式](https://github.com/luarocks/luarocks/wiki/Config-file-format)）。你可以使用第三方工具安装缺少的软件包并将其安装目录添加到 `luarocks` 变量表中。此方法适用于 macOS、Ubuntu、CentOS 和其他类似操作系统。

此处仅给出 macOS 的具体解决步骤，其他操作系统的解决方案类似：

1. 安装 `openldap`：

   ```shell
   brew install openldap
   ```

2. 使用以下命令命令找到本地安装目录：

   ```shell
   brew --prefix openldap
   ```

3. 将路径添加到项目配置文件中（选择两种方法中的一种即可）：
   1. 你可以使用 `luarocks config` 命令设置 `LDAP_DIR`：

      ```shell
      luarocks config variables.LDAP_DIR /opt/homebrew/cellar/openldap/2.6.1
      ```

   2. 你还可以更改 `luarocks` 的默认配置文件。打开 `~/.luaorcks/config-5.1.lua` 文件并添加以下内容：

      ```shell
      variables = { LDAP_DIR = "/opt/homebrew/cellar/openldap/2.6.1", LDAP_INCDIR = "/opt/homebrew/cellar/openldap/2.6.1/include", }
      ```

      `/opt/homebrew/cellar/openldap/` 是 `brew` 在 macOS(Apple Silicon) 上安装 `openldap` 的默认位置。`/usr/local/opt/openldap/` 是 brew 在 macOS(Intel) 上安装 openldap 的默认位置。

:::

如果你不再需要 APISIX，可以执行以下命令卸载：

```shell
make uninstall && make undeps
```

:::danger

该操作将删除所有相关文件。

:::

## 安装 etcd

APISIX 默认使用 [etcd](https://github.com/etcd-io/etcd) 来保存和同步配置。在运行 APISIX 之前，你需要在你的机器上安装 etcd。

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

## 管理 APISIX 服务

运行以下命令初始化 NGINX 配置文件和 etcd。

```shell
apisix init
```

:::tip

你可以运行 `apisix help` 命令，查看返回结果，获取其他操作命令及其描述。

:::

运行以下命令测试配置文件，APISIX 将根据 `config.yaml` 生成 `nginx.conf`，并检查 `nginx.conf` 的语法是否正确。

```shell
apisix test
```

最后，你可以使用以下命令运行 APISIX。

```shell
apisix start
```

如果需要停止 APISIX，你可以使用 `apisix quit` 或者 `apisix stop` 命令。

`apisix quit` 将正常关闭 APISIX，该指令确保在停止之前完成所有收到的请求。

```shell
apisix quit
```

`apisix stop` 命令会强制关闭 APISIX 并丢弃所有请求。

```shell
apisix stop
```

## 为 APISIX 构建 APISIX-Runtime

APISIX 的一些特性需要在 OpenResty 中引入额外的 NGINX 模块。

如果要使用这些功能，你需要构建一个自定义的 OpenResty 发行版（APISIX-Runtime）。请参考 [apisix-build-tools](https://github.com/api7/apisix-build-tools) 配置你的构建环境并进行构建。

## 运行测试用例

以下步骤展示了如何运行 APISIX 的测试用例：

1. 安装 `perl` 的包管理器 [cpanminus](https://metacpan.org/pod/App::cpanminus#INSTALLATION)。
2. 通过 `cpanm` 来安装 [test-nginx](https://github.com/openresty/test-nginx) 的依赖：

   ```shell
   sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)
   ```

3. 将 `test-nginx` 源码克隆到本地：

   ```shell
   git clone https://github.com/openresty/test-nginx.git
   ```

4. 运行以下命令将当前目录添加到 Perl 的模块目录：

   ```shell
   export PERL5LIB=.:$PERL5LIB
   ```

   你可以通过运行以下命令指定 NGINX 二进制路径：

   ```shell
   TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t
   ```

5. 运行测试：

   ```shell
   make test
   ```

:::note

部分测试需要依赖外部服务和修改系统配置。如果想要完整地构建测试环境，请参考 [ci/linux_openresty_common_runner.sh](https://github.com/apache/apisix/blob/master/ci/linux_openresty_common_runner.sh)。

:::

### 故障排查

以下是运行 APISIX 测试用例的常见故障排除步骤。

出现 `Error unknown directive "lua_package_path" in /API_ASPIX/apisix/t/servroot/conf/nginx.conf` 报错，是因为默认的 NGINX 安装路径未找到，解决方法如下：

- Linux 默认安装路径：

  ```shell
  export PATH=/usr/local/openresty/nginx/sbin:$PATH
  ```

### 运行指定的测试用例

使用以下命令运行指定的测试用例：

```shell
prove -Itest-nginx/lib -r t/plugin/openid-connect.t
```

如果你想要了解更多信息，请参考 [testing framework](../../en/latest/internal/testing-framework.md)。
