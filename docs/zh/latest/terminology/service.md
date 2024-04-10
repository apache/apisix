---
title: Service
keywords:
  - API 网关
  - Apache APISIX
  - Router
description: 本文介绍了 Apache APISIX Service 对象的概念及其使用方法。
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

Service（也称之为服务）是某类 API 的抽象（也可以理解为一组 Route 的抽象）。它通常与上游服务抽象是一一对应的，但与路由之间，通常是 1:N 即一对多的关系。参看下图。

![服务示例](../../../assets/images/service-example.png)

不同路由规则同时绑定到一个服务上，这些路由将具有相同的上游和插件配置，减少冗余配置。当路由和服务都开启同一个插件时，路由中的插件优先级高于服务中的插件。关于插件优先级的更多信息，请参考 [Plugin](./plugin.md)。

更多关于 Service 的信息，请参考 [Admin API 的 Service 对象](../admin-api.md#service)。

## 配置示例

以下示例创建了一个启用限流插件的服务，并且将该服务绑定到 ID 为 `100` 和 `101` 的路由上。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

1. 创建服务。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/services/200 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "plugins": {
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        },
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
    }'
    ```

2. 创建 ID 为 `100` 的路由，并绑定 ID 为 `200` 的服务。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/100 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "methods": ["GET"],
        "uri": "/index.html",
        "service_id": "200"
    }'
    ```

3. 创建 ID 为 `101` 的路由，并绑定 ID 为 `200` 的服务。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/101 \
    -H "X-API-KEY: $admin_key" -X PUT -d '
    {
        "methods": ["GET"],
        "uri": "/foo/index.html",
        "service_id": "200"
    }'
    ```

当然你也可以为路由指定不同的插件配置或上游。比如在以下示例中，我们设置了不同的限流参数，其他部分（比如上游）则继续使用上述服务中的配置参数。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/102 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/bar/index.html",
    "id": "102",
    "service_id": "200",
    "plugins": {
        "limit-count": {
            "count": 2000,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    }
}'
```

:::tip 提示

当路由和服务都启用同一个插件时，路由中的插件配置会优先于服务。更多信息，请参考[Plugin](./plugin.md)。

:::
