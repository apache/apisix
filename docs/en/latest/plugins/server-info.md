---
title: server-info
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Server info
  - server-info
description: This document contains information about the Apache APISIX server-info Plugin.
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

The `server-info` Plugin periodically reports basic server information to etcd.

:::warning

The `server-info` Plugin is deprecated and will be removed in a future release. For more details about the deprecation and removal plan, please refer to [this discussion](https://github.com/apache/apisix/discussions/12298).

:::

The information reported by the Plugin is explained below:

| Name         | Type    | Description                                                                                                            |
|--------------|---------|------------------------------------------------------------------------------------------------------------------------|
| boot_time    | integer | Bootstrap time (UNIX timestamp) of the APISIX instance. Resets when hot updating but not when APISIX is just reloaded. |
| id           | string  | APISIX instance ID.                                                                                                    |
| etcd_version | string  | Version of the etcd cluster used by APISIX. Will be `unknown` if the network to etcd is partitioned.                   |
| version      | string  | Version of APISIX instance.                                                                                            |
| hostname     | string  | Hostname of the machine/pod APISIX is deployed to.                                                                     |

## Attributes

None.

## API

This Plugin exposes the endpoint `/v1/server_info` to the [Control API](../control-api.md)

## Enable Plugin

Add `server-info` to the Plugin list in your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
  - ...
  - server-info
```

## Customizing server info report configuration

We can change the report configurations in the `plugin_attr` section of `conf/config.yaml`.

The following configurations of the server info report can be customized:

| Name         | Type   | Default  | Description                                                          |
| ------------ | ------ | -------- | -------------------------------------------------------------------- |
| report_ttl | integer | 36 | Time in seconds after which the report is deleted from etcd (maximum: 86400, minimum: 3). |

To customize, you can modify the `plugin_attr` attribute in your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugin_attr:
  server-info:
    report_ttl: 60
```

## Example usage

After you enable the Plugin as mentioned above, you can access the server info report through the Control API:

```shell
curl http://127.0.0.1:9090/v1/server_info -s | jq .
```

```json
{
  "etcd_version": "3.5.0",
  "id": "b7ce1c5c-b1aa-4df7-888a-cbe403f3e948",
  "hostname": "fedora32",
  "version": "2.1",
  "boot_time": 1608522102
}
```

:::tip

You can also view the server info report through the [APISIX Dashboard](/docs/dashboard/USER_GUIDE).

:::

## Delete Plugin

To remove the Plugin, you can remove `server-info` from the list of Plugins in your configuration file:

```yaml title="conf/config.yaml"
plugins:
  - ...
```
