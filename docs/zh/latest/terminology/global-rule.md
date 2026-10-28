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

[Global Rule](../admin-api.md#global-rule) 为传入请求配置 [Plugin](plugin.md)，不依赖于绑定到 [Route](route.md)、[Service](service.md)、[Consumer](consumer.md) 或 [Plugin Config](plugin-config.md) 的插件配置。限流和可观测性插件通常会全局启用，以便为所有 API 提供一致的行为。

同一阶段内的 Global Rule Plugin 会先于局部绑定的 Plugin 执行。完整顺序为：全局 `rewrite`、局部 `rewrite`、全局 `access`、局部 `access`。因此，全局 `access` 处理函数不会先于局部 `rewrite` 处理函数执行。优先级只对同一阶段和作用域内的 Plugin 进行排序；如果某个处理函数提前返回响应，后续处理函数将不会执行。详情请参见[插件执行顺序](./plugin.md#插件执行顺序)。

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
