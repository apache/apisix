---
title: Zookeeper
keywords:
  - API Gateway
  - Apache APISIX
  - ZooKeeper
  - Service Discovery
description: This documentation describes implementing service discovery through ZooKeeper on the API Gateway Apache APISIX.
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

## Service Discovery via ZooKeeper

Apache APISIX supports integrating with ZooKeeper for service discovery. This allows APISIX to dynamically fetch service instance information from ZooKeeper and route requests accordingly.

## Configuration for ZooKeeper

To enable ZooKeeper service discovery, add the following configuration to `conf/config.yaml`:

```yaml
discovery:
  zookeeper:
    connect_string: "127.0.0.1:2181,127.0.0.1:2182"  # ZooKeeper Cluster Addresses (separated by commas for multiple addresses)
    fetch_interval: 10     # Interval (in seconds) for fetching service data. Default: 10s
    weight: 100            # Default weight for service instances. Default value is 100, and the value range is 1-500.
    cache_ttl: 30          # The time after which service instance cache becomes expired. Default: 60s
    connect_timeout: 2000  # Connect timeout (in ms). Default: 5000ms
    session_timeout: 30000 # Session Timeout (in ms). Default: 30000ms
    root_path: "/apisix/discovery/zk"  # Root path for service registration in ZooKeeper, default: "/apisix/discovery/zk"
    auth:                  # ZooKeeper Authentication Information. Format requirement: "digest:{username}:{password}".
      type: "digest"
      creds: "username:password"
```

And you can config it in short by default value:

```yaml
discovery:
  zookeeper:
    connect_string: "127.0.0.1:2181"
```

### Upstream setting

#### L7 (HTTP/HTTPS)

Here is an example of routing requests with the URI `/zookeeper/*` to a service named `APISIX-ZOOKEEPER` registered in ZooKeeper:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
$ admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/zookeeper/*",
    "upstream": {
        "service_name": "APISIX-ZOOKEEPER",
        "type": "roundrobin",
        "discovery_type": "zookeeper"
    }
}'
```

The formatted response as below:

```json
{
  "node": {
    "key": "/apisix/routes/1",
    "value": {
      "id": "1",
      "create_time": 1690000000,
      "status": 1,
      "update_time": 1690000000,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-ZOOKEEPER",
        "type": "roundrobin",
        "discovery_type": "zookeeper"
      },
      "priority": 0,
      "uri": "/zookeeper/*"
    }
  }
}
```

#### L4 (TCP/UDP)

ZooKeeper service discovery also supports L4 proxy. Here's an example configuration for TCP:

```shell
$ curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "remote_addr": "127.0.0.1",
    "upstream": {
        "scheme": "tcp",
        "discovery_type": "zookeeper",
        "service_name": "APISIX-ZOOKEEPER-TCP",
        "type": "roundrobin"
    }
}'
```

### discovery_args

| Name         | Type   | Required | Default | Valid | Description                                                  |
| ------------ | ------ | ----------- | ------- | ----- | ------------------------------------------------------------ |
| root_path | string | optional   | "/apisix/discovery/zk"  |      | Custom root path for the service in ZooKeeper |

#### Specify Root Path

Example of routing to a service under a custom root path:

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/2 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/zookeeper/custom/*",
    "upstream": {
        "service_name": "APISIX-ZOOKEEPER",
        "type": "roundrobin",
        "discovery_type": "zookeeper",
        "discovery_args": {
            "root_path": "/custom/services"
        }
    }
}'

```

The formatted response as below:

```json
{
  "node": {
    "key": "/apisix/routes/2",
    "value": {
      "id": "2",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-ZOOKEEPER",
        "type": "roundrobin",
        "discovery_type": "zookeeper",
        "discovery_args": {
          "root_path": "/custom/services"
        }
      },
      "priority": 0,
      "uri": "/zookeeper/*"
    }
  }
}
```
