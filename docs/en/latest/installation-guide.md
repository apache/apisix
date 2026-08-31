---
title: Installation
keywords:
  - APISIX
  - APISIX Installation
  - Install APISIX
description: Choose and verify an Apache APISIX installation with Docker Compose, Helm, Linux packages, or a source build, then configure its deployment mode.
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

This guide lists the supported installation paths for Apache APISIX and the checks to run before you configure routes. For a short local walkthrough, start with [Getting Started](./getting-started/README.md).

## Choose an installation method

| Method | Appropriate starting point |
| --- | --- |
| Docker Compose | Local evaluation or a reproducible container-based environment |
| Helm | Kubernetes deployment managed with the official APISIX chart |
| RPM or DEB | A supported Linux distribution managed by system packages |
| Source build | Development or a build that requires reviewed compile-time changes |

APISIX supports Linux for production. Confirm the supported architecture, distribution, and component versions for the release you intend to deploy. Do not copy a package filename or image tag from an older guide into production without verifying that release.

## Install APISIX

<Tabs
  groupId="install-method"
  defaultValue="docker"
  values={[
    {label: 'Docker Compose', value: 'docker'},
    {label: 'Helm', value: 'helm'},
    {label: 'RPM', value: 'rpm'},
    {label: 'DEB', value: 'deb'},
    {label: 'Source Code', value: 'source'},
  ]}>

<TabItem value="docker">

Clone the [apisix-docker](https://github.com/apache/apisix-docker) repository:

```shell
git clone https://github.com/apache/apisix-docker.git
cd apisix-docker/example
```

:::warning Local example only

The example configuration is not safe to expose on a shared or untrusted network. Before starting it, bind the published Admin API (`9180`) and Control API (`9092`) ports to `127.0.0.1` or remove those host-port mappings. Never expose the [Control API](./control-api.md) to public traffic. Restrict the metrics port (`9091`) to the intended monitoring path. If host access to etcd is required, bind `2379` to `127.0.0.1`; otherwise remove its host-port mapping. Also restrict `allow_admin` to the intended operator address and replace the example Admin API keys. The bundled etcd is configured for an isolated example, not as a secured production configuration store.

:::

Start the Compose file that matches the host architecture:

```shell title="x86_64"
docker compose -p docker-apisix up -d
```

```shell title="ARM64"
docker compose -p docker-apisix -f docker-compose-arm64.yml up -d
```

The example starts APISIX and its required configuration store. Review the Compose file, image tags, exposed ports, credentials, volumes, and network settings before every use and before adapting it to another environment.

</TabItem>

<TabItem value="helm">

Add the official chart repository and install APISIX in a dedicated namespace:

```shell
helm repo add apisix https://apache.github.io/apisix-helm-chart
helm repo update
helm install apisix apisix/apisix \
  --namespace ingress-apisix \
  --create-namespace
```

:::warning Production configuration

The chart's bundled etcd configuration is intended for development and testing,
not as a production configuration store. For production, use a supported,
version-pinned external etcd deployment with authentication, TLS, persistent
storage, backup and recovery, and network isolation; configure the chart to use
that deployment. Also review the rendered Services and network policies so the
Admin API is reachable only from the intended operator path.

:::

See the [apisix-helm-chart repository](https://github.com/apache/apisix-helm-chart) for current values, supported Kubernetes versions, upgrade notes, and optional components. Pin the chart and image versions used by your deployment.

</TabItem>

<TabItem value="rpm">

For a distribution supported by the APISIX RPM repository, add the repository and install the package:

```shell
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo \
  https://repos.apiseven.com/packages/redhat/apache-apisix.repo
sudo dnf install -y apisix
```

On releases that use `yum` rather than `dnf`, install the repository-management plugin supplied by that distribution before adding the repository. Do not start APISIX until you complete the configuration-source and Admin API steps below. Use `apisix help` to list the management commands available in the installed release.

</TabItem>

<TabItem value="deb">

The APISIX DEB repository supports selected Debian versions and architectures. Verify the current repository support before installation. The following example uses a dedicated keyring rather than the deprecated `apt-key` command:

```shell
sudo apt update
sudo apt install -y ca-certificates curl gnupg

curl -fsSL https://repos.apiseven.com/pubkey.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/apache-apisix.gpg

case "$(dpkg --print-architecture)" in
  amd64) repo_url="https://repos.apiseven.com/packages/debian" ;;
  arm64) repo_url="https://repos.apiseven.com/packages/arm64/debian" ;;
  *) echo "Unsupported architecture" >&2; exit 1 ;;
esac

echo "deb [signed-by=/usr/share/keyrings/apache-apisix.gpg] ${repo_url} debian12 main" \
  | sudo tee /etc/apt/sources.list.d/apache-apisix.list

sudo apt update
sudo apt install -y apisix
```

Do not start APISIX until you complete the configuration-source and Admin API steps below.

</TabItem>

<TabItem value="source">

Follow [Building APISIX from source](./building-apisix.md). Record the source commit, OpenResty version, dependencies, build options, and generated package or image so the build can be reproduced.

</TabItem>

</Tabs>

## Select the configuration source

Choose the [deployment mode](./deployment-modes.md) before starting a production node:

- **Traditional and decoupled modes** use etcd as the configuration store. Secure a networked etcd deployment with authentication, TLS, and network isolation.
- **Standalone file-driven mode** loads a full YAML or JSON configuration from the local filesystem and does not use etcd as its configuration center.
- **Standalone API-driven mode** stores full configuration in memory and is intended for defined integrations such as the APISIX Ingress Controller and ADC. Review its full-replacement and versioning behavior before use.

Docker Compose and Helm examples can provision an example etcd instance for you;
do not treat that as a production etcd design. For a production deployment or a
package or source installation in an etcd-backed mode, install a supported etcd
release by following the
[official etcd installation documentation](https://etcd.io/docs/). Confirm
connectivity and version compatibility before starting APISIX.

## Configure APISIX

APISIX reads `conf/config.yaml` by default. Use `--config` or `-c` to select another file when validating or running a management command:

```shell
apisix test -c /path/to/config.yaml
```

Only include values you need to override. APISIX uses its packaged defaults for other settings. Do not edit the generated `conf/nginx.conf` directly.

For example, an etcd-backed traditional node can set its listener and etcd endpoint as follows:

```yaml title="conf/config.yaml"
apisix:
  node_listen: 9080

deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "https://etcd.example:2379"
```

Configure etcd authentication and TLS fields for the selected environment. A URL beginning with `https://` alone is not sufficient proof that peer verification and credentials are correct.

## Protect the Admin API

Replace the documented development key, restrict `allow_admin` to operator networks, and deliver the key through the secret mechanism used by your deployment. The environment variable below must exist in the APISIX process environment; defining it only in an interactive shell does not configure a service managed by systemd or another supervisor.

For a local package evaluation, generate a key before writing the configuration:

```shell
export ADMIN_KEY="$(openssl rand -hex 32)"
```

Then reference that variable in `conf/config.yaml`:

```yaml title="conf/config.yaml"
deployment:
  admin:
    allow_admin:
      - 127.0.0.0/24
    admin_key:
      - name: admin
        key: ${{ADMIN_KEY}}
        role: admin
```

The data-plane rate-limiting plugins do not protect the Admin API. Keep the Admin API off untrusted networks and apply the operational controls described in the [Admin API documentation](./admin-api.md).

After configuring the selected mode and its actual configuration source, preserve the key across the first privileged APISIX commands:

```shell
sudo --preserve-env=ADMIN_KEY apisix init
sudo --preserve-env=ADMIN_KEY apisix test
sudo --preserve-env=ADMIN_KEY apisix start
```

For a managed installation, inject the same value through a restricted service environment file or secret manager instead of relying on a shell export. Configure and verify etcd first when using an etcd-backed mode. After any configuration change, run `apisix test` and then reload or restart APISIX in the same controlled environment.

Do not put an Admin API key in a URL. Once APISIX is running, send it in the required header:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" \
  -H "X-API-KEY: ${ADMIN_KEY}"
```

## Verify the installation

For a package or source installation, validate the generated NGINX configuration before start or reload:

```shell
apisix version
apisix test
curl -i "http://127.0.0.1:9080/"
```

Before a Route is configured, the data-plane request can return `404`; the purpose of this check is to confirm that the intended listener responds. Use the Admin API check above to confirm control-plane access.

For a container or Kubernetes installation, use the corresponding container and workload status commands, then inspect the APISIX logs. Verify all of the following before configuring production traffic:

- the expected APISIX version and image or package digest are running;
- the data-plane and Admin API ports are exposed only where intended;
- the selected configuration source is reachable and updates are applied;
- the Admin API rejects missing or invalid credentials; and
- a test Route reaches its intended upstream and fails safely when that upstream is unavailable.

Continue with [Getting Started](./getting-started/README.md) to create and verify a Route.
