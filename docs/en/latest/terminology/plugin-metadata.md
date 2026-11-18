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

In this document, you will learn the basic concept of plugin metadata in APISIX and why you may need it.

## Overview

In APISIX, a plugin metadata object configures shared settings for all instances of the same plugin. It is useful for values, such as log-format templates, that should normally remain consistent wherever the plugin is enabled.

APISIX stores one plugin metadata object for each plugin name. Only plugins that define a metadata schema support plugin metadata. Fields and behavior depend on the plugin, so check the documentation for the specific plugin before configuring its metadata.

For example, plugin metadata can define a shared `log_format` for every instance of the `syslog` plugin. An instance without its own `log_format` uses the metadata value, while an instance-level `log_format` takes precedence when configured.

For logger plugins that support shared `log_format` metadata, this behavior also applies to plugins such as `http-logger`, `kafka-logger`, and `file-logger`.

Plugin metadata is not merged with every plugin configuration by a universal precedence rule. Each plugin determines how its instances consume metadata and whether an instance-level field overrides a metadata field.

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

## Additional resources

[Plugins](./plugin.md)
