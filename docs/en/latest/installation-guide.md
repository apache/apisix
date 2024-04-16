---
title: Installation
keywords:
  - APISIX
  - Installation
description: This document walks you through the different Apache APISIX installation methods.
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

This guide walks you through how you can install and run Apache APISIX in your environment.

Refer to the [Getting Started](./getting-started/README.md) guide for a quick walk-through on running Apache APISIX.

## Installing etcd

APISIX uses [etcd](https://github.com/etcd-io/etcd) to save and synchronize configuration. Before installing APISIX, you need to install etcd on your machine.

It would be installed automatically if you choose the Docker or Helm install method while installing APISIX. If you choose a different method or you need to install it manually, follow the steps shown below:

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


## Installing APISIX

APISIX can be installed by the different methods listed below:

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

First clone the [apisix-docker](https://github.com/apache/apisix-docker) repository:

```shell
git clone https://github.com/apache/apisix-docker.git
cd apisix-docker/example
```

Now, you can use `docker-compose` to start APISIX.

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

To install APISIX via Helm, run:

```shell
helm repo add apisix https://charts.apiseven.com
helm repo update
helm install apisix apisix/apisix --create-namespace  --namespace apisix
```

You can find other Helm charts on the [apisix-helm-chart](https://github.com/apache/apisix-helm-chart) repository.

</TabItem>

<TabItem value="rpm">

This installation method is suitable for CentOS 7 and Centos 8. If you choose this method to install APISIX, you need to install etcd first. For the specific installation method, please refer to [Installing etcd](#installing-etcd).

### Installation via RPM repository

If OpenResty is **not** installed, you can run the command below to install both OpenResty and APISIX repositories:

```shell
sudo yum install -y https://repos.apiseven.com/packages/centos/apache-apisix-repo-1.0-1.noarch.rpm
```

If OpenResty is installed, the command below will install the APISIX repositories:

```shell
sudo yum-config-manager --add-repo https://repos.apiseven.com/packages/centos/apache-apisix.repo
```

Then, to install APISIX, run:

```shell
sudo yum install apisix
```

:::tip

You can also install a specific version of APISIX by specifying it:

```shell
sudo yum install apisix-3.8.0
```

:::

### Installation via RPM offline package

First, download APISIX RPM offline package to an `apisix` folder:

```shell
sudo mkdir -p apisix
sudo yum install -y https://repos.apiseven.com/packages/centos/apache-apisix-repo-1.0-1.noarch.rpm
sudo yum clean all && yum makecache
sudo yum install -y --downloadonly --downloaddir=./apisix apisix
```

Then copy the `apisix` folder to the target host and run:

```shell
sudo yum install ./apisix/*.rpm
```

### Managing APISIX server

Once APISIX is installed, you can initialize the configuration file and etcd by running:

```shell
apisix init
```

To start APISIX server, run:

```shell
apisix start
```

:::tip

Run `apisix help` to get a list of all available operations.

:::

</TabItem>

<TabItem value="deb">

### Installation via DEB repository

Currently the only DEB repository supported by APISIX is Debian 11 (Bullseye) and supports both amd64 and arm64 architectures.

```shell
# amd64
wget -O - http://repos.apiseven.com/pubkey.gpg | sudo apt-key add -
echo "deb http://repos.apiseven.com/packages/debian bullseye main" | sudo tee /etc/apt/sources.list.d/apisix.list

# arm64
wget -O - http://repos.apiseven.com/pubkey.gpg | sudo apt-key add -
echo "deb http://repos.apiseven.com/packages/arm64/debian bullseye main" | sudo tee /etc/apt/sources.list.d/apisix.list
```

Then, to install APISIX, run:

```shell
sudo apt update
sudo apt install -y apisix=3.8.0-0
```

### Managing APISIX server

Once APISIX is installed, you can initialize the configuration file and etcd by running:

```shell
sudo apisix init
```

To start APISIX server, run:

```shell
sudo apisix start
```

:::tip

Run `apisix help` to get a list of all available operations.

:::

</TabItem>

<TabItem value="source code">

If you want to build APISIX from source, please refer to [Building APISIX from source](./building-apisix.md).

</TabItem>
</Tabs>

## Next steps

### Configuring APISIX

You can configure your APISIX deployment in two ways:

1. By directly changing your configuration file (`conf/config.yaml`).
2. By using the `--config` or the `-c` flag to pass the path to your configuration file while starting APISIX.

   ```shell
   apisix start -c <path to config file>
   ```

APISIX will use the configurations added in this configuration file and will fall back to the default configuration if anything is not configured. Generally, APISIX gets installed at `/usr/local/apisix/` directory, so your configuration file will be present at `/usr/local/apisix/conf/` path.

In case you get the Port binding logs when trying to run the APISIX server using `apisix start` command, it is most likely that the ports are being used by certain processes running on your machine. Try deleting the process using the port or configure the default listening port to other available port on your local machine.

In order to configure the default listening port to be `8000` without changing other configurations, your configuration file could look like this:

```yaml title="conf/config.yaml"
apisix:
  node_listen: 8000
```

Now, if you decide you want to change the etcd address to `http://foo:2379`, you can add it to your configuration file. This will not change other configurations.

```yaml title="conf/config.yaml"
apisix:
  node_listen: 8000

deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "http://foo:2379"
```

:::warning

APISIX's default configuration can be found in `conf/config-default.yaml` file and it should not be modified. It is bound to the source code and the configuration should only be changed by the methods mentioned above.

:::

:::warning

The `conf/nginx.conf` file is automatically generated and should not be modified.

:::

### APISIX deployment modes

APISIX has three different deployment modes for different use cases. To learn more and configure deployment modes, see the [documentation](./deployment-modes.md).

### Updating Admin API key

It is recommended to modify the Admin API key to ensure security.

You can update your configuration file as shown below:

```yaml title="conf/config.yaml"
deployment:
  admin:
    admin_key
      -
        name: "admin"
        key: newsupersecurekey
        role: admin
```

Now, to access the Admin API, you can use the new key:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes?api_key=newsupersecurekey -i
```

### Adding APISIX systemd unit file

If you installed APISIX via RPM, the APISIX unit file will already be configured and you can start APISIX by:

```shell
systemctl start apisix
systemctl stop apisix
```

If you installed APISIX through other methods, you can create `/usr/lib/systemd/system/apisix.service` and add the [configuration from the template](https://github.com/api7/apisix-build-tools/blob/master/usr/lib/systemd/system/apisix.service).

See the [Getting Started](./getting-started/README.md) guide for a quick walk-through of using APISIX.
