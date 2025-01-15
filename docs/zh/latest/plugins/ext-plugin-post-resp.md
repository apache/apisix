---
title: ext-plugin-post-resp
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - ext-plugin-post-resp
description: 本文介绍了关于 Apache APISIX `ext-plugin-post-resp` 插件的基本信息及使用方法。
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

`ext-plugin-post-resp` 插件用于在执行内置 Lua 插件之前和在 Plugin Runner 内运行特定的 External Plugin。

`ext-plugin-post-resp` 插件将在请求获取到上游的响应之后执行。

启用本插件之后，APISIX 将使用 [lua-resty-http](https://github.com/api7/lua-resty-http) 库向上游发起请求，这会导致：

- [proxy-control](./proxy-control.md) 插件不可用
- [proxy-mirror](./proxy-mirror.md) 插件不可用
- [proxy-cache](./proxy-cache.md) 插件不可用
- [APISIX 与上游间的双向认证](../mtls.md#apisix-与上游间的双向认证) 功能尚不可用

如果你想了解更多关于 External Plugin 的信息，请参考 [External Plugin](../external-plugin.md) 。

:::note

External Plugin 执行的结果会影响当前请求的响应。

:::

## 属性

| 名称              | 类型    | 必选项 | 默认值  | 有效值                                                           | 描述                                                                              |
| ----------------- | ------ | ------ | ------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| conf              | array  | 否     |         | [{"name": "ext-plugin-A", "value": "{\"enable\":\"feature\"}"}] | 在 Plugin Runner 内执行的插件列表的配置。                                           |
| allow_degradation | boolean| 否     | false   | [false, true]                                                    | 当 Plugin Runner 临时不可用时是否允许请求继续，当值设置为 `true` 时则自动允许请求继续。   |

## 启用插件

以下示例展示了如何在指定路由中启用 `ext-plugin-post-resp` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "ext-plugin-post-resp": {
            "conf" : [
                {"name": "ext-plugin-A", "value": "{\"enable\":\"feature\"}"}
            ]
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

## 测试插件

通过上述命令启用插件后，可以使用如下命令测试插件是否启用成功：

```shell
curl -i http://127.0.0.1:9080/index.html
```

在返回结果中可以看到刚刚配置的 Plugin Runner 已经被触发，同时 `ext-plugin-A` 插件也已经被执行。

## 删除插件

当你需要禁用 `ext-plugin-post-resp` 插件时，可通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
