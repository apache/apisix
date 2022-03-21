---
title: server-info
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

## Description

`server-info` is a plugin that reports basic server information to etcd periodically.

The meaning of each item in server information is following:

| Name    | Type | Description |
|---------|------|-------------|
| boot_time | integer | Bootstrap time (UNIX timestamp) of the APISIX instance, value will be reset when you hot updating APISIX but is kept for intact if you just reloading APISIX. |
| id | string | APISIX instance id. |
| etcd_version | string | The etcd cluster version that APISIX is using, value will be `"unknown"` if the network (to etcd) is partitioned. |
| version | string | APISIX version. |
| hostname | string | Hostname of the machine/pod that APISIX is deployed. |

## Attributes

None

## API

This plugin exposes one API `/v1/server_info` to [Control API](../control-api.md).

## How to Enable

Just configure `server-info` in the plugin list of the configuration file `conf/config.yaml`.

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

## How to customize the server info report configurations

We can change the report configurations in the `plugin_attr` section of `conf/config.yaml`.

| Name         | Type   | Default  | Description                                                          |
| ------------ | ------ | -------- | -------------------------------------------------------------------- |
| report_ttl | integer | 36 | the live time for server info in etcd (unit: second, maximum: 86400, minimum: 3). |

Here is an example, which modifies the `report_ttl` to one minute.

```yaml
plugin_attr:
  server-info:
    report_ttl: 60
```

## Test Plugin

After enabling this plugin, you can access these data through the plugin Control API:

```shell
$ curl http://127.0.0.1:9090/v1/server_info -s | jq .
{
  "etcd_version": "3.5.0",
  "id": "b7ce1c5c-b1aa-4df7-888a-cbe403f3e948",
  "hostname": "fedora32",
  "version": "2.1",
  "boot_time": 1608522102
}
```

The APISIX Dashboard will collects server info in etcd, so you may also try to check them through Dashboard.

## Disable Plugin

Remove `server-info` in the plugin list of configure file `conf/config.yaml`.

```
plugins:                          # plugin list
  - example-plugin
  - limit-req
  - node-status
  - jwt-auth
  - zipkin
  ......
```
