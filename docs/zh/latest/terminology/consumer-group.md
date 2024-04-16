---
title: Consumer Groups
keywords:
  - API 网关
  - Apache APISIX
  - Consumer Groups
description: 本文介绍了 Apache APISIX Consumer Group 对象的概念及使用方法。
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

通过 Consumer Groups，你可以在同一个消费者组中启用任意数量的[插件](./plugin.md)，并在一个或者多个[消费者](./consumer.md)中引用该消费者组。

## 配置示例

以下示例展示了如何创建消费者组并将其绑定到消费者中。

创建一个共享相同限流配额的消费者组：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

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

在消费者组中创建消费者：

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

当 APISIX 无法找到 `group_id` 中定义的消费者组时，创建或者更新消费者的请求将会终止，并返回错误码 `404`。

如果消费者已经配置了 `plugins` 字段，那么消费者组中配置的插件将与之合并。

:::tip

此处需要注意两点：

1. 当在同一个插件分别配置在[消费者](./consumer.md)、[路由](./route.md)、[插件配置](./plugin-config.md)和[服务](./service.md)中时，只有一份配置是生效的，并且消费者的优先级最高。更多信息，请参考 [Plugin](./plugin.md)。
2. 如果消费者和消费者组配置了相同的插件，则消费者中的插件配置优先级更高。对于第一点，因为消费者组需要配置在消费者中，因此你只需关心消费者中插件的优先级。

:::

如下示例，假如你配置了一个消费者组：

```json title="Consumer Group"
{
    "id": "bar",
    "plugins": {
        "response-rewrite": {
            "body": "hello"
        }
    }
}
```

并配置了消费者：

```json title="Consumer"
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

那么 `response-rewrite` 中的 `body` 将保留 `world`。
