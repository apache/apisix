---
title: Consumer Group
keywords:
  - API 网关
  - Apache APISIX
  - Consumer Group
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

当在同一个路由中配置相同的插件时，只有一份配置是生效的。关于插件配置的优先级，请参考 [Plugin](./plugin.md)。

## 配置示例

以下示例展示了如何创建消费者组并将其绑定到消费者中。

```shell
curl http://127.0.0.1:9180/apisix/admin/consumer_groups/company_a \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "limit-count": {
            "count": 200,
            "time_window": 60,
            "rejected_code": 503,
            "group": "$consumer_group_id"
        }
    }
}'
```

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

如果消费者已经配置了 `plugins` 字段，那么消费者中定义的插件将与之合并。如果消费者和消费者组配置了相同的插件，则消费者组中的插件将会失效。

如下示例，假如你配置了一个消费者组：

```json title=“Consumer Group”
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

```json title=“Consumer”
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

那么 `response-rewrite` 中的 `body` 保留 `world`。
