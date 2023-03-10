---
id: get-data-planes-from-etcd
title: Get data planes from etcd
keywords:
  - API gateway
  - Apache APISIX
description: Get data planes from etcd
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

To query all data planes information from etcd, we move `server-info` plugin into the APISIX core, and use it to report data plane information.

The data plane information keeps the same format of `server-info` plugin output:

| Name         | Type    | Description                                                                                                            |
|--------------|---------|------------------------------------------------------------------------------------------------------------------------|
| boot_time    | integer | Bootstrap time (UNIX timestamp) of the APISIX instance. Resets when hot updating but not when APISIX is just reloaded. |
| id           | string  | APISIX instance ID.                                                                                                    |
| etcd_version | string  | Version of the etcd cluster used by APISIX. Will be `unknown` if the network to etcd is partitioned.                   |
| version      | string  | Version of APISIX instance.                                                                                            |
| hostname     | string  | Hostname of the machine/pod APISIX is deployed to.                                                                     |

## Admin API to query data planes

* `GET /apisix/admin/data_planes`

It returns a JSON array which contains all alive data planes.

```bash
curl http://127.0.0.1:9180/apisix/admin/data_planes \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X GET -s | jq
[
  {
    "value": {
      "etcd_version": "3.5.0",
      "hostname": "bar",
      "version": "3.2.0",
      "id": "de900110-a4b2-456a-9112-f3f76578657c",
      "boot_time": 1678095922
    },
    "key": "/apisix/data_plane/server_info/de900110-a4b2-456a-9112-f3f76578657c",
    "lease": "7587868007797608997",
    "create_revision": "2687091",
    "version": "1",
    "mod_revision": "2687091"
  },
  {
    "value": {
      "etcd_version": "3.5.0",
      "hostname": "foo",
      "version": "3.2.0",
      "id": "e16b5da2-1b5c-4cd3-866c-7bcea7b32ffe",
      "boot_time": 1678095822
    },
    "create_revision": "2687090",
    "key": "/apisix/data_plane/server_info/e16b5da2-1b5c-4cd3-866c-7bcea7b32ffe",
    "lease": "7587868007797608997",
    "version": "1",
    "mod_revision": "2687090"
  }
]
```

* `GET /apisix/admin/data_planes/<id>`

It returns a JSON object which contains the specific alive data plane.

```bash
curl http://127.0.0.1:9180/apisix/admin/data_planes/e16b5da2-1b5c-4cd3-866c-7bcea7b32ffe \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X GET -s | jq
{
  "value": {
    "etcd_version": "3.5.0",
    "hostname": "foo",
    "version": "3.2.0",
    "id": "e16b5da2-1b5c-4cd3-866c-7bcea7b32ffe",
    "boot_time": 1678095822
  },
  "create_revision": "2687090",
  "key": "/apisix/data_plane/server_info/e16b5da2-1b5c-4cd3-866c-7bcea7b32ffe",
  "lease": "7587868007797608997",
  "version": "1",
  "mod_revision": "2687090"
}
```
