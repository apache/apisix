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

- [中文](../zh-cn/plugins/server-info.md)

# Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**API**](#api)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)
- [Note](#note)

## Name

`server-info` is a plugin which we can get basic server information through it's API.

## Attributes

None

## API

This plugin now exposes only one API `/apisix/server_info` to get basic server information.
You may need to use [interceptors](../plugin-interceptors.md) to protect it.


## How to Enable

Just configure `server-info` in the plugin list of the configuration file `apisix/conf/config.yaml`.

```
plugins:                          # plugin list
  - example-plugin
  - limit-req
  - node-status
  - server-info
  - jwt-auth
  - zipkin
  ......
```

After starting APISIX and accessing `/apisix/server_info` then you can get server information.

## Test Plugin

```bash
curl http://127.0.0.1:9080/apisix/admin/server_info -s | jq
{
  "up_time": 5,
  "last_report_time": 1606551536,
  "id": "71cb4999-4349-475d-aa39-c703944a63d3",
  "etcd_version": "3.5.0",
  "version": "2.0",
  "hostname": "gentoo"
}
```

The meaning of each item in server information is following:

| Name    | Type | Description |
|---------|------|-------------|
| up_time | integer | Elapsed time since APISIX instance was launched, value will be reset when you hot updating APISIX but is kept for intact if you just reloading APISIX. |
| last_report_time | integer | Last reporting timestamp. |
| id | string | APISIX instance id. |
| etcd_version | string | The etcd cluster version that APISIX is using, value will be `"unknown"` if the network (to etcd) is partitioned. |
| version | string | APISIX version. |
| hostname | string | Hostname of the machine/pod that APISIX is deployed. |

## Disable Plugin

By removing `server-info` in the plugin list of configure file `apisix/conf/config.yaml` and restart APISIX, you can diable `server-info` plugin easily.

```
plugins:                          # plugin list
  - example-plugin
  - limit-req
  - node-status
  - jwt-auth
  - zipkin
  ......
```

## Note

When you use etcd as the data center for APISIX, the server information is also reported to etcd periodically (for now the interval is `5s`) and collected by APISIX Dashboard, so you can also access it from APISIX Dashboard.
