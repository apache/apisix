---
title: server-info
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Server info
  - server-info
description: 本文介绍了关于 Apache APISIX `server-info` 插件的基本信息及使用方法。
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

`server-info` 插件可以定期将服务基本信息上报至 etcd。

:::warning

`server-info` 插件已弃用，将在未来的版本中被移除。更多关于弃用和移除计划的信息，请参考[这个讨论](https://github.com/apache/apisix/discussions/12298)。

:::

服务信息中每一项的含义如下：

| 名称             | 类型    | 描述                                                                                                                   |
| ---------------- | ------- | --------------------------------------------------------------------------------------------------------------------- |
| boot_time        | integer | APISIX 服务实例的启动时间（UNIX 时间戳），如果对 APISIX 进行热更新操作，该值将被重置。普通的 reload 操作不会影响该值。         |
| id               | string  | APISIX 服务实例 id。                                                                                                   |
| etcd_version     | string  | etcd 集群的版本信息，如果 APISIX 和 etcd 集群之间存在网络分区，该值将设置为 `"unknown"`。                                   |
| version          | string  | APISIX 版本信息。                                                                                                       |
| hostname         | string  | 部署 APISIX 的主机或 Pod 的主机名信息。                                                                                  |

## 属性

无。

## 插件接口

该插件在 [Control API](../control-api.md) 下暴露了一个 API 接口 `/v1/server_info`。

## 启用插件

该插件默认是禁用状态，你可以在配置文件（`./conf/config.yaml`）中添加如下配置启用 `server-info` 插件。

```yaml title="conf/config.yaml"
plugins:                          # plugin list
  - ...
  - server-info
```

## 自定义服务信息上报配置

我们可以在 `./conf/config.yaml` 文件的 `plugin_attr` 部分修改上报配置。

下表是可以自定义配置的参数：

| 名称            | 类型    | 默认值  | 描述                                                               |
| --------------- | ------- | ------ | --------------------------------------------------------------- |
| report_ttl      | integer | 36     | etcd 中服务信息保存的 TTL（单位：秒，最大值：86400，最小值：3）。|

以下是示例是通过修改配置文件（`conf/config.yaml`）中的 `plugin_attr` 部分将 `report_ttl` 设置为 1 分钟：

```yaml title="conf/config.yaml"
plugin_attr:
  server-info:
    report_ttl: 60
```

## 测试插件

在启用 `server-info` 插件后，可以通过插件的 Control API 来访问到这些数据：

```shell
curl http://127.0.0.1:9090/v1/server_info -s | jq .
```

```JSON
{
  "etcd_version": "3.5.0",
  "id": "b7ce1c5c-b1aa-4df7-888a-cbe403f3e948",
  "hostname": "fedora32",
  "version": "2.1",
  "boot_time": 1608522102
}
```

:::tip

你可以通过 [APISIX Dashboard](/docs/dashboard/USER_GUIDE) 查看服务信息报告。

:::

## 删除插件

如果你想禁用插件，可以将 `server-info` 从配置文件中的插件列表删除，重新加载 APISIX 后即可生效。

```yaml title="conf/config.yaml"
plugins:    # plugin list
  - ...
```
