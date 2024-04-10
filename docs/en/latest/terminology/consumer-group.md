---
title: Consumer Group
keywords:
  - API gateway
  - Apache APISIX
  - Consumer Group
description: Consumer Group in Apache APISIX.
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

Consumer Groups are used to extract commonly used [Plugin](./plugin.md) configurations and can be bound directly to a [Consumer](./consumer.md).

With consumer groups, you can define any number of plugins, e.g. rate limiting and apply them to a set of consumers,
instead of managing each consumer individually.

## Example

The example below illustrates how to create a Consumer Group and bind it to a Consumer.

Create a Consumer Group which shares the same rate limiting quota:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/consumer_groups/company_a \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "limit-count": {
            "count": 200,
            "time_window": 60,
            "rejected_code": 503,
            "group": "grp_company_a"
        }
    }
}'
```

Create a Consumer within the Consumer Group:

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "auth-one"
        }
    },
    "group_id": "company_a"
}'
```

When APISIX can't find the Consumer Group with the `group_id`, the Admin API is terminated with a status code of `400`.

:::tip

1. When the same plugin is configured in [consumer](./consumer.md), [routing](./route.md), [plugin config](./plugin-config.md) and [service](./service.md), only one configuration is in effect, and the consumer has the highest priority. Please refer to [Plugin](./plugin.md).
2. If a Consumer already has the `plugins` field configured, the plugins in the Consumer Group will effectively be merged into it. The same plugin in the Consumer Group will not override the one configured directly in the Consumer.

:::

For example, if we configure a Consumer Group as shown below:

```json
{
    "id": "bar",
    "plugins": {
        "response-rewrite": {
            "body": "hello"
        }
    }
}
```

To a Consumer as shown below.

```json
{
    "username": "foo",
    "group_id": "bar",
    "plugins": {
        "basic-auth": {
            "username": "foo",
            "password": "bar"
        },
        "response-rewrite": {
            "body": "world"
        }
    }
}
```

Then the `body` in `response-rewrite` keeps `world`.
