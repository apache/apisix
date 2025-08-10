---
title: APISIX 安装指南
keywords:
  - APISIX
  - APISIX 安装教程
  - 部署 APISIX
description: 本文档主要介绍了 APISIX 多种安装方法。
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

本文将介绍如何在你的环境中安装并运行 APISIX。

关于如何快速运行 Apache APISIX，请参考[入门指南](./getting-started/README.md)。

## 安装 APISIX

你可以选择以下任意一种方式安装 APISIX：

<Tabs
  groupId="install-method"
  defaultValue="docker"
  values={[
    {label: 'Docker', value: 'docker'},
    {label: 'Helm', value: 'helm'},
    {label: 'RPM', value: 'rpm'},
    {label: 'DEB', value: 'deb'},
    {label: 'Source Code', value: 'source code'},
  ]}>
<TabItem value="docker">

使用此方法安装 APISIX，你需要安装 [Docker](https://www.docker.com/) 和 [Docker Compose](https://docs.docker.com/compose/)。

首先下载 [apisix-docker](https://github.com/apache/apisix-docker) 仓库。

```shell
git clone https://github.com/apache/apisix-docker.git
cd apisix-docker/example
```

然后，使用 `docker-compose` 启用 APISIX。

<Tabs
  groupId="cpu-arch"
  defaultValue="x86"
  values={[
    {label: 'x86', value: 'x86'},
    {label: 'ARM/M1', value: 'arm'},
  ]}>
<TabItem value="x86">

```shell
docker-compose -p docker-apisix up -d
```

</TabItem>

<TabItem value="arm">

```shell
docker-compose -p docker-apisix -f docker-compose-arm64.yml up -d
```

</TabItem>
</Tabs>

</TabItem>

<TabItem value="helm">

通过 Helm 安装 APISIX，请执行以下命令：

```shell
helm repo add apisix https://charts.apiseven.com
helm repo update
helm install apisix apisix/apisix --create-namespace  --namespace apisix
```

你可以从 [apisix-helm-chart](https://github.com/apache/apisix-helm-chart) 仓库找到其他组件。

</TabItem>

<TabItem value="rpm">

该安装方法适用于 CentOS 7 和 CentOS 8。如果你选择该方法安装 APISIX，需要先安装 etcd。具体安装方法请参考 [安装 etcd](#安装-etcd)。

### 通过 RPM 仓库安装

```shell
sudo yum-config-manager --add-repo https://repos.apiseven.com/packages/redhat/apache-apisix.repo
```

完成上述操作后使用以下命令安装 APISIX：

```shell
sudo yum install apisix
```

:::tip

你也可以安装指定版本的 APISIX（本示例为 APISIX v3.8.0 版本）：

```shell
sudo yum install apisix-3.8.0
```

:::

### 通过 RPM 包离线安装：

将 APISIX 离线 RPM 包下载到 `apisix` 文件夹：

```shell
sudo mkdir -p apisix
sudo yum install -y https://repos.apiseven.com/packages/redhat/8/x86_64/apisix-3.13.0-0.ubi8.6.x86_64.rpm
sudo yum clean all && yum makecache
sudo yum install -y --downloadonly --downloaddir=./apisix apisix
```

然后将 `apisix` 文件夹复制到目标主机并运行以下命令：

```shell
sudo yum install ./apisix/*.rpm
```

### 管理 APISIX 服务

APISIX 安装完成后，你可以运行以下命令初始化 NGINX 配置文件和 etcd：

```shell
apisix init
```

使用以下命令启动 APISIX：

```shell
apisix start
```

:::tip

你可以运行 `apisix help` 命令，通过查看返回结果，获取其他操作的命令及描述。

:::

</TabItem>

<TabItem value="deb">

### 通过 DEB 仓库安装

目前 APISIX 支持的 DEB 仓库仅支持 Debian 11（Bullseye），并且支持 amd64 和 arm64 架构。

```shell
# amd64
wget -O - http://repos.apiseven.com/pubkey.gpg | sudo apt-key add -
echo "deb http://repos.apiseven.com/packages/debian bullseye main" | sudo tee /etc/apt/sources.list.d/apisix.list

# arm64
wget -O - http://repos.apiseven.com/pubkey.gpg | sudo apt-key add -
echo "deb http://repos.apiseven.com/packages/arm64/debian bullseye main" | sudo tee /etc/apt/sources.list.d/apisix.list
```

完成上述操作后使用以下命令安装 APISIX：

```shell
sudo apt update
sudo apt install -y apisix=3.8.0-0
```

### 管理 APISIX 服务

APISIX 安装完成后，你可以运行以下命令初始化 NGINX 配置文件和 etcd：

```shell
sudo apisix init
```

使用以下命令启动 APISIX：

```shell
sudo apisix start
```

:::tip

你可以运行 `apisix help` 命令，通过查看返回结果，获取其他操作的命令及描述。

:::

</TabItem>

<TabItem value="source code">

如果你想要使用源码构建 APISIX，请参考 [源码安装 APISIX](./building-apisix.md)。

</TabItem>
</Tabs>

## 安装 etcd

APISIX 使用 [etcd](https://github.com/etcd-io/etcd) 作为配置中心进行保存和同步配置。在安装 APISIX 之前，需要在你的主机上安装 etcd。

如果你在安装 APISIX 时选择了 Docker 或 Helm 安装，那么 etcd 将会自动安装；如果你选择其他方法或者需要手动安装 APISIX，请参考以下步骤安装 etcd：

<Tabs
  groupId="os"
  defaultValue="linux"
  values={[
    {label: 'Linux', value: 'linux'},
    {label: 'macOS', value: 'mac'},
  ]}>
<TabItem value="linux">

```shell
ETCD_VERSION='3.5.4'
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

## 后续操作

### 配置 APISIX

通过修改本地 `./conf/config.yaml` 文件，或者在启动 APISIX 时使用 `-c` 或 `--config` 添加文件路径参数 `apisix start -c <path string>`，完成对 APISIX 服务本身的基本配置。默认配置不应修改，可以在 `apisix/cli/config.lua` 中找到。

比如将 APISIX 默认监听端口修改为 8000，其他配置保持默认，在 `./conf/config.yaml` 中只需这样配置：

```yaml title="./conf/config.yaml"
apisix:
  node_listen: 8000 # APISIX listening port
```

比如指定 APISIX 默认监听端口为 8000，并且设置 etcd 地址为 `http://foo:2379`，其他配置保持默认。在 `./conf/config.yaml` 中只需这样配置：

```yaml title="./conf/config.yaml"
apisix:
  node_listen: 8000 # APISIX listening port

deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "http://foo:2379"
```

:::warning

请不要手动修改 APISIX 安装目录下的 `./conf/nginx.conf` 文件。当 APISIX 启动时，会根据 `config.yaml` 的配置自动生成新的 `nginx.conf` 并自动启动服务。

:::

### 更新 Admin API key

建议修改 Admin API 的 key，保护 APISIX 的安全。

请参考如下信息更新配置文件：

```yaml title="./conf/config.yaml"
deployment:
  admin:
    admin_key:
      - name: "admin"
        key: newsupersecurekey  # 请修改 key 的值
        role: admin
```

更新完成后，你可以使用新的 key 访问 Admin API：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes?api_key=newsupersecurekey -i
```

### 为 APISIX 添加 systemd 配置文件

如果你是通过 RPM 包安装 APISIX，配置文件已经自动安装，你可以直接使用以下命令：

```shell
systemctl start apisix
systemctl stop apisix
```

如果你是通过其他方法安装的 APISIX，可以参考[配置文件模板](https://github.com/api7/apisix-build-tools/blob/master/usr/lib/systemd/system/apisix.service)进行修改，并将其添加在 `/usr/lib/systemd/system/apisix.service` 路径下。

如需了解 APISIX 后续使用，请参考[入门指南](./getting-started/README.md)获取更多信息。
