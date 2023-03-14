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

Refer to this link for detail:

https://apisix.apache.org/en/docs/apisix/admin-api/#query-data-planes
