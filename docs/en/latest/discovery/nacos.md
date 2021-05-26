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

This is experimental discovery module for Nacos.

The performance of this module needs to be improved:

1. avoid synchroning configuration in each workers. You can refer the implementation in `consul_kv.lua`.
2. send the request parallelly.

### Configuration for Nacos

Add following configuration in `conf/config.yaml` :

```yaml
discovery:
  nacos:
    host:
      - "http://${username}:${password}@${host1}:${port1}"
    prefix: "/nacos/v1/"
    fetch_interval: 30    # default 30 sec
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

Here is an example of routing a request with a URL of "/nacos/*" to a service which named "http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS" and use nacos discovery client in the registry :

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/nacos/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos"
    }
}'
```

The format response as below:

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
  },
  "action": "set"
}
```

example of routing a request with a URL of "/nacosWithNamespaceIdAndGroupId/*" to a service which name, namespaceId, groupName "http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS&groupName=test&namespaceId=test" and use nacos discovery client in the registry :

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/2 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/nacosWithNamespaceIdAndGroupId/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "namespace_id": "test",
        "group_name":"test"
    }
}'
```

The format response as below:

```json
{
  "node": {
    "key": "\/apisix\/routes\/2",
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
        "discovery_type": "nacos",
        "namespace_id": "test",
        "group_name": "test"
      },
      "priority": 0,
      "uri": "\/nacosWithNamespaceIdAndGroupId\/*"
    }
  },
  "action": "set"
}
```

example to use other nacos host

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/3 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/nacosWithOtherHost/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "namespace_id": "test",
        "group_name":"test",
        "discovery_host": ["http://nacos:nacos@$192.168.33.1:8848"]
    }
}'
```

The format response as below:

```json
{
  "node": {
    "key": "\/apisix\/routes\/3",
    "value": {
      "id": "1",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "discovery_host": [
          "http://nacos:nacos@192.168.33.1:8848"
        ],
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "namespace_id": "test",
        "group_name": "test"
      },
      "priority": 0,
      "uri": "\/nacosWithOtherHost\/*"
    }
  },
  "action": "set"
}
```