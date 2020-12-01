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

- [English](../../plugins/server-info.md)

# Summary

- [**插件简介**](#插件简介)
- [插件属性](#插件属性)
- [**插件接口**](#插件接口)
- [启用插件](#启用插件)
- [测试插件](#测试插件)
- [禁用插件](#禁用插件)
- [注意事项](#注意事项)

## 插件简介

`server-info` 是 `APISIX` 提供的一款查询其服务基本信息的插件。

## 插件属性

无

## 插件接口

此插件提供了接口 `/apisix/server_info`，可以通过 [interceptors](../plugin-interceptors.md) 来保护该接口。

## 启用插件

在配置文件 `apisix/conf/config.yaml` 的插件列表中添加 `server-info`, 即可启用该插件。

```
plugins:                          # plugin list
  - example-plugin
  - limit-req
  - node-status
  - server-info
  - jwt-auth
  - zipkin
  ......
```

在启动/重启 APISIX 之后，即可通过访问 `/apisix/server_info` 来获取服务基本信息。

## 测试插件

```bash
curl http://127.0.0.1:9080/apisix/admin/server_info -s | jq
{
  "up_time": 5,
  "last_report_time": 1606551536,
  "id": "71cb4999-4349-475d-aa39-c703944a63d3",
  "etcd_version": "3.5.0",
  "version": "2.0",
  "hostname": "gentoo"
}
```

服务信息中每一项的含义如下：

| 名称    | 类型 | 描述 |
|---------|------|-------------|
| up_time | integer | APISIX 服务实例当前的运行时间, 如果对 APSIX
进行热更新操作，该值将被重置；普通的 reload 操作不会影响该值。 |
| last_report_time | integer | 最近一次服务信息上报的时间 （UNIX 时间戳）。|
| id | string | APISIX 服务实例 id 。|
| etcd_version | string | etcd 集群的版本信息，如果 APISIX 和 etcd 集群之间存在网络分区，该值将设置为 `"unknown"`。|
| version | string | APISIX 版本信息。 |
| hostname | string | APISIX 所部署的机器或 pod 的主机名信息。|

## 禁用插件

通过移除配置文件 `apisix/conf/config.yaml` 插件列表中的 `server-info`，即可方便地禁用该插件。

```
plugins:                          # plugin list
  - example-plugin
  - limit-req
  - node-status
  - jwt-auth
  - zipkin
  ......
```

## 注意事项

当使用 etcd 作为 APISIX 的数据中心的说话，服务信息将被周期性地上报到 etcd（目前的上报间隔是 5
秒）并被 APISIX Dashboard 所收集，所以你也可以通过 APISIX Dashboard 来访问这些数据。
