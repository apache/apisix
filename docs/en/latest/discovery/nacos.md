---
title: Nacos Service Discovery
keywords:
  - Apache APISIX
  - Nacos
  - Service Discovery
description: Configure Apache APISIX to discover healthy L7 or L4 upstream nodes from Nacos, including namespace, group, refresh, and failover behavior.
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

## Service discovery via Nacos

The Nacos discovery client lets an APISIX Upstream reference a Nacos service by name instead of listing nodes statically. APISIX queries Nacos for healthy instances, converts the returned addresses and weights into upstream nodes, and refreshes the cached node set at `fetch_interval`.

Nacos discovery is available for HTTP and stream routes. Use `discovery_args` to select a non-default namespace or group. For an overview of the discovery interface and supported registries, see [Service Discovery](../discovery.md).

:::note

The client polls the referenced Nacos services sequentially. When multiple `host` entries are configured, APISIX starts from a randomized host and tries another host only if no referenced service was fetched successfully from the selected host. A partial refresh is accepted: services that failed are not retried against the next host, and their cached registry entries can be removed during cleanup. If every host fails completely, APISIX logs the failure and schedules the next refresh. Monitor per-service refresh errors and node freshness; multiple hosts do not provide per-service failover, and cached discovery data is not proof that a backend remains healthy between polls.

:::

### Configuration for Nacos

Add the following configuration in `conf/config.yaml`:

```yaml
discovery:
  nacos:
    host:
      - "https://${{NACOS_USERNAME}}:${{NACOS_PASSWORD}}@${{NACOS_HOST}}:${{NACOS_PORT}}"
    prefix: "/nacos/v1/"
    fetch_interval: 30    # default 30 sec
    # `weight` is the `default_weight` that will be attached to each discovered node that
    # doesn't have a weight explicitly provided in nacos results
    weight: 100           # default 100
    timeout:
      connect: 2000       # default 2000 ms
      send: 2000          # default 2000 ms
      read: 5000          # default 5000 ms
```

The minimal configuration below is only for an isolated local Nacos instance without authentication or TLS:

```yaml
discovery:
  nacos:
    host:
      - "http://192.168.33.1:8848"
```

Use the APISIX `${{VARIABLE}}` syntax for environment interpolation; `${name}` is only a literal string in this configuration. Supply the username and password as their original values: the Nacos client encodes them when it builds the login request, so pre-encoding the values can break authentication. For a private CA, configure the CA bundle with `apisix.ssl.ssl_trusted_certificate` and verify the effective TLS connection. Do not commit real usernames, passwords, access keys, or secret keys to the configuration repository. Supply them through the secret-delivery mechanism used by your deployment and verify the effective configuration before starting traffic. The optional `access_key` and `secret_key` fields are for Alibaba Cloud MSE Nacos request signing.

### Upstream setting

#### L7

The following example routes requests matching `/nacos/*` to healthy instances registered as `APISIX-NACOS` in the default Nacos namespace and group:

:::note
Reuse the resolved Admin API secret from the environment that starts APISIX:

```bash
admin_key="${ADMIN_KEY:?ADMIN_KEY is not set}"
```

If a local test configuration contains the actual key rather than an environment or secret reference, you can read that literal value with `admin_key="$(yq -r '.deployment.admin.admin_key[0].key' conf/config.yaml)"`. `yq` does not resolve `${{VARIABLE}}` templates or external secrets.

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacos/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos"
    }
}'
```

A successful response returns the saved Route in the current Admin API response format.

#### L4

Nacos supports L4 service discovery; the configuration is similar to L7.

```shell
curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "remote_addr": "127.0.0.1",
    "upstream": {
        "scheme": "tcp",
        "discovery_type": "nacos",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin"
    }
}'
```

### discovery_args

| Name           | Type   | Required | Default         | Description                                          |
| -------------- | ------ | -------- | --------------- | ---------------------------------------------------- |
| `namespace_id` | string | No       | `public`        | Nacos namespace containing the service.              |
| `group_name`   | string | No       | `DEFAULT_GROUP` | Nacos group containing the service in the namespace. |

#### Specify the namespace

The following Route selects service `APISIX-NACOS` in namespace `test_ns`:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/2 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacosWithNamespaceId/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "namespace_id": "test_ns"
        }
    }
}'
```

A successful response returns the saved Route in the current Admin API response format.

#### Specify the group

The following Route selects service `APISIX-NACOS` in group `test_group`:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/3 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacosWithGroupName/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "group_name": "test_group"
        }
    }
}'
```

A successful response returns the saved Route in the current Admin API response format.

#### Specify the namespace and group

The following Route selects service `APISIX-NACOS` in namespace `test_ns` and group `test_group`:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/4 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacosWithNamespaceIdAndGroupName/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "namespace_id": "test_ns",
          "group_name": "test_group"
        }
    }
}'
```

A successful response returns the saved Route in the current Admin API response format.
