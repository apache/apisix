---
title: Global rules
keywords:
  - API 网关
  - Apache APISIX
  - Global Rules
  - 全局规则
description: 本文介绍了全局规则的概念以及如何启用全局规则。
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

[Plugin](plugin.md) 配置可直接绑定在 [Route](route.md) 上，也可以被绑定在 [Service](service.md) 或 [Consumer](consumer.md) 上。

如果你需要一个能作用于所有请求的 Plugin，可以通过 Global Rules 启用一个全局的插件配置。

全局规则相对于 Route、Service、Plugin Config、Consumer 中的插件配置，Global Rules 中的插件总是优先执行。

## 使用示例

以下示例展示了如何为所有请求启用 `limit-count` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/global_rules/1 -X PUT \
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

你也可以通过以下命令查看所有的全局规则：

```shell
curl http://127.0.0.1:9180/apisix/admin/global_rules -H "X-API-KEY: $admin_key"
```
