---
title: nacos
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

The performance of this module needs to be improved:

1. send the request parallelly.

### Configuration for Nacos

Add following configuration in `conf/config.yaml` :

```yaml
discovery:
  nacos:
    host:
      - "http://${username}:${password}@${host1}:${port1}"
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

And you can config it in short by default value:

```yaml
discovery:
  nacos:
    host:
      - "http://192.168.33.1:8848"
```

### Upstream setting

#### L7

Here is an example of routing a request with an URI of "/nacos/*" to a service which named "http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS" and use nacos discovery client in the registry:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacos/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos"
    }
}'
```

The formatted response as below:

```json
{
  "node": {
    "key": "\/apisix\/routes\/1",
    "value": {
      "id": "1",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos"
      },
      "priority": 0,
      "uri": "\/nacos\/*"
    }
  }
}
```

#### L4

Nacos service discovery also supports use in L4, the configuration method is similar to L7.

```shell
$ curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
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

| Name         | Type   | Requirement | Default | Valid | Description                                                  |
| ------------ | ------ | ----------- | ------- | ----- | ------------------------------------------------------------ |
| namespace_id | string | optional    | public     |       | This parameter is used to specify the namespace of the corresponding service |
| group_name   | string | optional    | DEFAULT_GROUP       |       | This parameter is used to specify the group of the corresponding service |

#### Specify the namespace

Example of routing a request with an URI of "/nacosWithNamespaceId/*" to a service with name, namespaceId "http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS&namespaceId=test_ns" and use nacos discovery client in the registry:

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/2 -H "X-API-KEY: $admin_key" -X PUT -i -d '
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

The formatted response as below:

```json
{
  "node": {
    "key": "\/apisix\/routes\/2",
    "value": {
      "id": "2",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "namespace_id": "test_ns"
        }
      },
      "priority": 0,
      "uri": "\/nacosWithNamespaceId\/*"
    }
  }
}
```

#### Specify the group

Example of routing a request with an URI of "/nacosWithGroupName/*" to a service with name, groupName "http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS&groupName=test_group" and use nacos discovery client in the registry:

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/3 -H "X-API-KEY: $admin_key" -X PUT -i -d '
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

The formatted response as below:

```json
{
  "node": {
    "key": "\/apisix\/routes\/3",
    "value": {
      "id": "3",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "group_name": "test_group"
        }
      },
      "priority": 0,
      "uri": "\/nacosWithGroupName\/*"
    }
  }
}
```

#### Specify the namespace and group

Example of routing a request with an URI of "/nacosWithNamespaceIdAndGroupName/*" to a service with name, namespaceId, groupName "http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS&namespaceId=test_ns&groupName=test_group" and use nacos discovery client in the registry:

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/4 -H "X-API-KEY: $admin_key" -X PUT -i -d '
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

The formatted response as below:

```json
{
  "node": {
    "key": "\/apisix\/routes\/4",
    "value": {
      "id": "4",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "namespace_id": "test_ns",
          "group_name": "test_group"
        }
      },
      "priority": 0,
      "uri": "\/nacosWithNamespaceIdAndGroupName\/*"
    }
  }
}
```
