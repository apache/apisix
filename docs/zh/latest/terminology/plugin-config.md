---
title: Plugin Config
keywords:
  - API 网关
  - Apache APISIX
  - 插件配置
  - Plugin Config
description: Plugin Config 对象，可以用于创建一组通用的插件配置，并在路由中使用这组配置。
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

在很多情况下，我们在不同的路由中会使用相同的插件规则，此时就可以通过 Plugin Config 来设置这些规则。Plugin Config 属于一组通用插件配置的抽象。

`plugins` 的配置可以通过 [Admin API](../admin-api.md#plugin-config) `/apisix/admin/plugin_configs` 进行单独配置，在路由中使用 `plugin_config_id` 与之进行关联。

对于同一个插件的配置，只能有一个是有效的，优先级为 Consumer > Route > Plugin Config > Service。

## 使用示例

你可以参考如下步骤将 Plugin Config 绑定在路由上。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

1. 创建 Plugin config。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/plugin_configs/1 \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
    {
        "desc": "enable limit-count plugin",
        "plugins": {
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503
            }
        }
    }'
    ```

2. 创建路由并绑定 `Plugin Config 1`。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
    {
        "uris": ["/index.html"],
        "plugin_config_id": 1,
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
    }'
    ```

如果找不到对应的 Plugin Config，该路由上的请求会报 `503` 错误。

## 注意事项

如果路由中已经配置了 `plugins`，那么 Plugin Config 里面的插件配置将会与 `plugins` 合并。

相同的插件不会覆盖掉 `plugins` 原有的插件配置。详细信息，请参考 [Plugin](./plugin.md)。

1. 假设你创建了一个 Plugin Config。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/plugin_configs/1 \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
    {
        "desc": "enable ip-restruction and limit-count plugin",
        "plugins": {
            "ip-restriction": {
                "whitelist": [
                    "127.0.0.0/24",
                    "113.74.26.106"
                ]
            },
            "limit-count": {
                "count": 2,
                "time_window": 60,
                "rejected_code": 503
            }
        }
    }'
    ```

2. 并在路由中引入 Plugin Config。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
    {
        "uris": ["/index.html"],
        "plugin_config_id": 1,
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
        "plugins": {
            "proxy-rewrite": {
                "uri": "/test/add",
                "host": "apisix.iresty.com"
            },
            "limit-count": {
                "count": 20,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        }
    }'
    ```

3. 最后实现的效果如下。

    ```shell
    curl http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -i -d '
    {
        "uris": ["/index.html"],
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
        "plugins": {
            "ip-restriction": {
                "whitelist": [
                    "127.0.0.0/24",
                    "113.74.26.106"
                ]
            },
            "proxy-rewrite": {
                "uri": "/test/add",
                "host": "apisix.iresty.com"
            },
            "limit-count": {
                "count": 20,
                "time_window": 60,
                "rejected_code": 503,
                "key": "remote_addr"
            }
        }
    }'
    ```
