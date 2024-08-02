---
title: Plugin Metadata
keywords:
  - API Gateway
  - Apache APISIX
  - Plugin Metadata
description: Plugin Metadata in Apache APISIX.
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

In this document, you will learn the basic concept of plugin metadata in APISIX and why you may need them.

Explore additional resources at the end of the document for more information on related topics.

## Overview

In APISIX, a plugin metadata object is used to configure the common metadata field(s) of all plugin instances sharing the same plugin name. It is useful when a plugin is enabled across multiple objects and requires a universal update to their metadata fields.

The following diagram illustrates the concept of plugin metadata using two instances of [syslog](https://apisix.apache.org/docs/apisix/plugins/syslog/) plugins on two different routes, as well as a plugin metadata object setting a [global](https://apisix.apache.org/docs/apisix/plugins/syslog/) `log_format` for the syslog plugin:

![plugin_metadata](https://static.apiseven.com/uploads/2023/04/17/Z0OFRQhV_plugin%20metadata.svg)

Without otherwise specified, the `log_format` on plugin metadata object should apply the same log format uniformly to both `syslog` plugins. However, since the `syslog` plugin on the `/orders` route has a different `log_format`, requests visiting this route will generate logs in the `log_format` specified by the plugin in route.

Metadata properties set at the plugin level is more granular and has a higher priority over the "global" metadata object.

Plugin metadata objects should only be used for plugins that have metadata fields. Check the specific plugin documentation to know more.

## Example usage

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/http-logger \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

With this configuration, your logs would be formatted as shown below:

```json
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## Additional Resource(s)

Key Concepts - [Plugins](https://apisix.apache.org/docs/apisix/terminology/plugin/)
