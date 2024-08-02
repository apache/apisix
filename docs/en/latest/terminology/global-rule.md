---
title: Global Rules
keywords:
  - API Gateway
  - Apache APISIX
  - Global Rules
description: This article describes how to use global rules.
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

A [Plugin](./plugin.md) configuration can be bound directly to a [Route](./route.md), a [Service](./service.md) or a [Consumer](./consumer.md). But what if we want a Plugin to work on all requests? This is where we register a global Plugin with Global Rule.

Compared with the plugin configuration in Route, Service, Plugin Config, and Consumer, the plugin in the Global Rules is always executed first.

## Example

The example below shows how you can use the `limit-count` Plugin on all requests:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -X PUT \
  http://{apisix_listen_address}/apisix/admin/global_rules/1 \
  -H 'Content-Type: application/json' \
  -H "X-API-KEY: $admin_key" \
  -d '{
        "plugins": {
            "limit-count": {
                "time_window": 60,
                "policy": "local",
                "count": 2,
                "key": "remote_addr",
                "rejected_code": 503
            }
        }
    }'
```

You can also list all the Global rules by making this request with the Admin API:

```shell
curl http://{apisix_listen_address}/apisix/admin/global_rules -H "X-API-KEY: $admin_key"
```
