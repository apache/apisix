---
title: ext-plugin-pre-req
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

## 目录

- [**简介**](#简介)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 简介

`ext-plugin-pre-req` 在执行大多数内置 Lua 插件执行之前，在 Plugin Runner 内运行特定 External Plugin。

为了理解什么是 Plugin Runner，请参考 [external plugin](../external-plugin.md) 部分。

External Plugins 执行的结果会影响当前请求的行为。

## 属性

| 名称      | 类型          | 必选项 | 默认值    | 有效值                                                                    | 描述                                                                                                                                         |
| --------- | ------------- | ----------- | ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| conf     | array        | 可选    |              | [{"name": "ext-plugin-A", "value": "{\"enable\":\"feature\"}"}] |     在 Plugin Runner 内执行的插件列表的配置 |
| allow_degradation              | boolean  | 可选                                | false       |                                                                     | 当 Plugin Runner 临时不可用时是否允许请求继续。当值设置为 true 时则自动允许请求继续，默认值是 false。|

## 如何启用

以下是一个示例，在指定路由中启用插件：

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "ext-plugin-pre-req": {
            "conf" : [
                {"name": "ext-plugin-A", "value": "{\"enable\":\"feature\"}"}
            ]
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

使用 `curl` 去测试：

```shell
curl -i http://127.0.0.1:9080/index.html
```

你会看到配置的 Plugin Runner 将会被触发，同时 `ext-plugin-A` 插件将会被执行。

## 禁用插件

当你想去掉 ext-plugin-pre-req 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

现在就已经移除 `ext-plugin-pre-req` 插件了。其他插件的开启和移除也是同样的方法。
