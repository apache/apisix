---
title: 如何构建 Apache APISIX
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

## 步骤1：安装 Apache APISIX

你可以通过 RPM 仓库、Docker、Helm Chart、源码包、源码包（LTS 版本）等多种方式来安装 Apache APISIX。请在以下选项中选择其中一种执行。

### 通过 RPM 仓库安装（CentOS 7）

这种安装方式适用于 CentOS 7 操作系统。

如果尚未安装 OpenResty 的官方 RPM 仓库，请使用以下命令自动安装 OpenResty 和 Apache APISIX 的 RPM 仓库。

```shell
sudo yum install -y https://repos.apiseven.com/packages/centos/apache-apisix-repo-1.0-1.noarch.rpm
```

如果已安装 OpenResty 的官方 RPM 仓库，请使用以下命令自动安装 Apache APISIX 的 RPM 仓库。

```shell
sudo yum-config-manager --add-repo https://repos.apiseven.com/packages/centos/apache-apisix.repo
```

请运行以下命令安装 Apache APISIX。

```shell
# 查看仓库中最新的 apisix 软件包的信息
sudo yum info -y apisix

# 显示仓库中现有的 apisix 软件包
sudo yum --showduplicates list apisix

# 安装最新的 apisix 软件包
sudo yum install apisix

# 安装指定版本（本例中为2.10.3版本）的 apisix 软件包
sudo yum install apisix-2.10.3-0.el7
```

### 通过 RPM 包离线安装（CentOS 7）

下载 APISIX 离线 RPM 包到 `./apisix` 文件夹

```shell
sudo mkdir -p apisix
sudo yum install -y https://repos.apiseven.com/packages/centos/apache-apisix-repo-1.0-1.noarch.rpm
sudo yum clean all && yum makecache
sudo yum install -y --downloadonly --downloaddir=./apisix apisix
```

拷贝 `./apisix` 文件夹到目标主机，使用以下命令安装 Apache APISIX。

```shell
sudo yum install ./apisix/*.rpm
```

### 通过 Docker 安装

详情请参考：[使用 Docker 安装 Apache APISIX](https://hub.docker.com/r/apache/apisix)。

### 通过 Helm Chart 安装

详情请参考：[使用 Helm Chart 安装 Apache APISIX](https://github.com/apache/apisix-helm-chart)。

### 通过源码包安装

注意：如果你想针对特定平台打包 Apache APISIX，请更新 https://github.com/api7/apisix-build-tools。
以下步骤仅用于设置 Apache APISIX 的开发环境。

1. 安装依赖

  ```shell
  curl https://raw.githubusercontent.com/apache/apisix/master/utils/install-dependencies.sh -sL | bash -
  ```

2. 创建一个名为 `apisix-2.13.3` 的目录。

  ```shell
  APISIX_VERSION='2.13.3'
  mkdir apisix-${APISIX_VERSION}
  ```

3. 下载 Apache APISIX Release 源码包：

  ```shell
  wget https://downloads.apache.org/apisix/${APISIX_VERSION}/apache-apisix-${APISIX_VERSION}-src.tgz
  ```

  您也可以通过 Apache APISIX 官网下载 Apache APISIX Release 源码包。 Apache APISIX 官网也提供了 Apache APISIX、APISIX Dashboard 和 APISIX Ingress Controller 的源码包，详情请参考 [Apache APISIX 官网-下载页](https://apisix.apache.org/zh/downloads)。

4. 解压 Apache APISIX Release 源码包：

  ```shell
  tar zxvf apache-apisix-${APISIX_VERSION}-src.tgz -C apisix-${APISIX_VERSION}
  ```

5. 安装运行时依赖的 Lua 库：

  ```shell
  # 切换到 apisix-${APISIX_VERSION} 目录
  cd apisix-${APISIX_VERSION}
  # 安装依赖
  LUAROCKS_SERVER=https://luarocks.cn make deps
  # 安装 apisix 命令
  make install
  ```

   **注意**：使用 `make deps` 安装 `lualdap`、`PCRE`、`openssl` 等依赖包失败，错误信息如： `Could not find header file for LDAP/PCRE/openssl`，可使用本方法解决。

   解决思路：`luarocks` 支持自定义编译时依赖目录（来自此[链接](https://github.com/luarocks/luarocks/wiki/Config-file-format))，使用第三方工具安装缺失的依赖，并将其文件路径添加到 `luarocks` 的变量表中。这是一种通用的解决方法，适用于在各种常见操作系统（包括但不仅限于 Ubuntu、Centos、macOS）遇到的“缺失头文件式安装依赖包失败”问题。

   这边暂给出 macOS 上的具体解决步骤，其他操作系统的解决方案类似：

     1. 使用 `brew install openldap` 命令将 `openldap` 安装到本地；
     2. 使用 `brew --prefix openldap` 命令找到本地安装目录；
     3. 将路径添加到项目配置文件中（选择两种方法中的一种即可）：
         1. 方法一：通过 `luarocks config` 手动设置 `LDAP_DIR` 变量, 比如 `luarocks config variables.LDAP_DIR /opt/homebrew/cellar/openldap/2.6.1`；
         2. 方法二：当然你也可以选择直接更改 luarocks 的默认配置文件，执行 `cat ~/.luarocks/config-5.1.lua` 命令，然后在文件中添加 `openldap` 的安装目录；
         3. 参考配置文件示例如下：
             variables = {
                 LDAP_DIR = "/opt/homebrew/cellar/openldap/2.6.1",
                 LDAP_INCDIR = "/opt/homebrew/cellar/openldap/2.6.1/include",
             }

     `/opt/homebrew/cellar/openldap/` 是 `brew` 在 macOS(Apple Silicon) 上安装 `openldap` 的默认位置。
     `/usr/local/opt/openldap/` 是 `brew` 在 macOS(Intel) 上安装 `openldap` 的默认位置。

5. 如果您不再需要 Apache APISIX 运行时，您可以执行卸载，如：

```shell
  # 卸载 apisix 命令
  make uninstall
  # 卸载依赖
  make undeps
```

  请注意，该操作将完整**删除**相关文件。

#### 通过源码包安装 LTS 版本

目前 Apache APISIX 的 LTS 版本为 `2.13.3`，将“[通过源码包安装](#通过源码包安装)”中的 `APISIX_VERSION` 设置成该版本号，其他步骤按顺序进行即可。

## 步骤2：安装 etcd

如果你只通过 RPM、Docker 或源代码安装了 Apache APISIX，而没有安装 etcd，则需要这一步。

你可以通过 Docker 或者二进制等方式安装 etcd。以下命令通过二进制方式在 Linux 上安装 etcd。

```shell
ETCD_VERSION='3.4.13'
wget https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
tar -xvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz && \
  cd etcd-v${ETCD_VERSION}-linux-amd64 && \
  sudo cp -a etcd etcdctl /usr/bin/
nohup etcd >/tmp/etcd.log 2>&1 &
```

以下命令在 Mac 上安装 etcd:

```shell
brew install etcd
# start etcd server
brew services start etcd
```

## 步骤3：管理 Apache APISIX 服务

我们可以在 Apache APISIX 的目录下使用命令初始化依赖、启动服务和停止服务，也可以通过 `apisix help` 命令查看所有命令和对应的功能。

### 初始化依赖

运行以下命令初始化 NGINX 配置文件和 etcd。

```shell
# initialize NGINX config file and etcd
apisix init
```

### 测试配置文件

运行以下命令测试配置文件。 APISIX 将根据 `config.yaml` 生成 `nginx.conf`，并检查 `nginx.conf` 的语法是否正确。

```shell
# generate `nginx.conf` from `config.yaml` and test it
apisix test
```

### 启动 Apache APISIX

运行以下命令启动 Apache APISIX。

```shell
# start Apache APISIX server
apisix start
```

### 停止运行 Apache APISIX

优雅停机 `apisix quit` 和强制停机 `apisix stop` 都可以停止运行 Apache APISIX。建议您优先选择优雅停机的方式停止 Apache APISIX，因为这种停止方式能够保证 Apache APISIX 完成了已经接受到的请求之后再停止；而强制停机则是立即停止 Apache APISIX，在这种情况下，Apache APISIX 接收到但未完成的请求会随着强制停机一并停止。

执行优雅停机的命令如下所示：

```shell
# stop Apache APISIX server gracefully
apisix quit
```

执行强制停机的命令如下所示：

```shell
# stop Apache APISIX server immediately
apisix stop
```

### 查看其他操作

运行 `apisix help` 命令，查看返回结果，获取其他操作的命令和描述。

```shell
# more actions find by `help`
apisix help
```

## 步骤4：运行测试案例

1. 安装 `perl` 的包管理器 `cpanminus`。

详情请参考：[安装包管理器 `cpanmius`](https://metacpan.org/pod/App::cpanminus#INSTALLATION)。

2. 然后通过 `cpanm` 来安装 test-nginx 的依赖：

  ```shell
  sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)
  ```

3. 运行 `git clone` 命令，将最新的源码克隆到本地，请使用我们 fork 出来的版本：

  ```shell
  git clone https://github.com/openresty/test-nginx.git
  ```

4. 有两种方法运行测试：

  - 追加当前目录到perl模块目录： `export PERL5LIB=.:$PERL5LIB`，然后运行 `make test` 命令。

  - 或指定 NGINX 二进制路径：`TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`。

  <!--
  #
  #    In addition to the basic Markdown syntax, we use remark-admonitions
  #    alongside MDX to add support for admonitions. Admonitions are wrapped
  #    by a set of 3 colons.
  #    Please refer to https://docusaurus.io/docs/next/markdown-features/admonitions
  #    for more detail.
  #
  -->

  :::note 说明
  部分测试需要依赖外部服务和修改系统配置。如果想要完整地构建测试环境，可以参考 `ci/linux_openresty_common_runner.sh`。
  :::

### 问题排查

**配置 NGINX 路径**

出现 `Error unknown directive "lua_package_path" in /API_ASPIX/apisix/t/servroot/conf/nginx.conf` 报错的解决方法如下：

确保将 OpenResty 设置为默认的 NGINX，并按如下所示导出路径：

* `export PATH=/usr/local/openresty/nginx/sbin:$PATH`
  * Linux 默认安装路径：
    * `export PATH=/usr/local/openresty/nginx/sbin:$PATH`
  * MacOS 通过 homebrew 默认安装路径：
    * `export PATH=/usr/local/opt/openresty/nginx/sbin:$PATH`

**运行单个测试用例**

使用以下命令运行指定的测试用例：

```shell
prove -Itest-nginx/lib -r t/plugin/openid-connect.t
```

关于测试用例的更多细节，参见 [测试框架](https://github.com/apache/apisix/blob/master/docs/en/latest/internal/testing-framework.md)

## 步骤5：修改 Admin API key

您需要修改 Admin API 的 key，以保护 Apache APISIX。

请修改 `conf/config.yaml` 中的 `apisix.admin_key` 并重启服务，如下所示：

```yaml
apisix:
  # ... ...
  admin_key
    -
      name: "admin"
      key: abcdefghabcdefgh # 将原有的 key 修改为abcdefghabcdefgh
      role: admin
```

当我们需要访问 Admin API 时，就可以使用上面记录的 key 了，如下所示：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes?api_key=abcdefghabcdefgh -i
```

返回结果中的状态码 200 说明访问成功，如下所示：

```shell
HTTP/1.1 200 OK
Date: Fri, 28 Feb 2020 07:48:04 GMT
Content-Type: text/plain
... ...
{"node":{...},"action":"get"}
```

在这个时候，如果您输入的 key 与 `conf/config.yaml` 中 `apisix.admin_key` 的值不匹配，例如，我们已知正确的 key 是 `abcdefghabcdefgh`，但是我们选择输入一个错误的 key，例如 `wrong-key`，如下所示：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes?api_key=wrong-key -i
```

返回结果中的状态码 `401` 说明访问失败，原因是输入的 `key` 有误，未通过认证，触发 `Unauthorized` 错误，如下所示：

```shell
HTTP/1.1 401 Unauthorized
Date: Fri, 28 Feb 2020 08:17:58 GMT
Content-Type: text/html
... ...
{"node":{...},"action":"get"}
```

## 步骤6：为 Apache APISIX 构建 OpenResty

有些功能需要引入额外的 NGINX 模块到 OpenResty 当中。
如果您需要这些功能，您可以构建 APISIX OpenResty。
您可以根据 [api7/apisix-build-tools](https://github.com/api7/apisix-build-tools) 里面的代码，配置自己的构建环境，并完成 APISIX OpenResty 的构建。

## 步骤7：为 Apache APISIX 添加 systemd 配置文件

如果您使用的操作系统是 CentOS 7，且在步骤 2 中通过 RPM 包安装 Apache APISIX，配置文件已经自动安装到位，你可以直接运行以下命令：

```shell
systemctl start apisix
systemctl stop apisix
```

如果通过其他方法安装，可以参考 [配置文件模板](https://github.com/api7/apisix-build-tools/blob/master/usr/lib/systemd/system/apisix.service) 进行修改，并将其放置在 `/usr/lib/systemd/system/apisix.service` 路径下。
