---
title: server-info
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

- [插件简介](#插件简介)
- [插件属性](#插件属性)
- [插件接口](#插件接口)
- [启用插件](#启用插件)
- [如何自定义服务信息上报配置](#如何自定义服务信息上报配置)
- [测试插件](#测试插件)
- [禁用插件](#禁用插件)

## 插件简介

`server-info` 是一款能够定期将服务基本信息上报至 etcd 的插件。

服务信息中每一项的含义如下：

| 名称    | 类型 | 描述 |
|---------|------|-------------|
| up_time | integer | APISIX 服务实例当前的运行时间（单位：秒）, 如果对 APISIX 进行热更新操作，该值将被重置；普通的 reload 操作不会影响该值。 |
| boot_time | integer | APISIX 服务实例的启动时间（UNIX 时间戳），如果对 APIISIX 进行热更新操作，该值将被重置；普通的 reload 操作不会影响该值。|
| last_report_time | integer | 最近一次服务信息上报的时间 （UNIX 时间戳）。|
| id | string | APISIX 服务实例 id 。|
| etcd_version | string | etcd 集群的版本信息，如果 APISIX 和 etcd 集群之间存在网络分区，该值将设置为 `"unknown"`。|
| version | string | APISIX 版本信息。 |
| hostname | string | APISIX 所部署的机器或 pod 的主机名信息。|

## 插件属性

无

## 插件接口

该插件在 [Control API](../../control-api.md) 下暴露了一个 API 接口 `/v1/server_info`。

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

## 如何自定义服务信息上报配置

我们可以在 `conf/config.yaml` 文件的 `plugin_attr` 一节中修改上报配置。

| 名称         | 类型   | 默认值  | 描述                                                          |
| ------------ | ------ | -------- | -------------------------------------------------------------------- |
| report_interval | integer | 60 | 上报服务信息至 etcd 的间隔（单位：秒，最大值：3600，最小值：60）|
| report_ttl | integer | 7200 | etcd 中服务信息保存的 TTL（单位：秒，最大值：86400，最小值：3600）|

下面的例子将 `report_interval` 修改成了 10 分钟，并将 `report_ttl` 修改成了 1
小时：

```yaml
plugin_attr:
  server-info:
    report_interval: 600
    report_ttl: 3600
```

## 测试插件

在启用该插件后，你可以通过插件的 Control API 来访问到这些数据：

```shell
$ curl http://127.0.0.1:9090/v1/server_info -s | jq .
{
  "etcd_version": "3.5.0",
  "up_time": 9460,
  "last_report_time": 1608531519,
  "id": "b7ce1c5c-b1aa-4df7-888a-cbe403f3e948",
  "hostname": "fedora32",
  "version": "2.1",
  "boot_time": 1608522102
}
```

Apache APISIX Dashboard 会收集上报到 etcd 中的服务信息，因此你也可以通过 APISIX Dashboard 来查看这些数据。

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
