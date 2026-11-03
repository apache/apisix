---
title: Plugin Metadata
keywords:
  - API 网关
  - Apache APISIX
  - 插件元数据配置
  - Plugin Metadata
description: APISIX 的插件元数据
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

## 描述

本文介绍 APISIX 插件元数据的基本概念和适用场景。

在 APISIX 中，插件元数据对象为同一插件的所有实例配置共享设置，适用于日志格式模板等通常需要保持一致的配置。

APISIX 为每个插件名称保存一个插件元数据对象。只有定义了元数据 Schema 的插件才支持插件元数据。字段和行为取决于具体插件，因此配置前请查看对应插件的文档。

例如，插件元数据可以为所有 `syslog` 插件实例定义共享的 `log_format`。未配置实例级 `log_format` 时，插件使用元数据中的值；配置实例级 `log_format` 后，该值优先。

对于支持共享 `log_format` 元数据的日志插件，此行为也适用于 `http-logger`、`kafka-logger` 和 `file-logger` 等插件。

插件元数据与插件实例配置之间不存在适用于所有插件的统一优先级规则。每个插件自行决定如何使用元数据，以及实例级字段是否覆盖元数据字段。

## 配置示例

以下示例展示了如何通过 Admin API 配置插件元数据：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

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

配置完成后，你将在日志系统中看到如下类似日志：

```json
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## 相关资源

[插件](./plugin.md)
