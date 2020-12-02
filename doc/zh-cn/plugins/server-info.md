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
- [如何自定义服务信息上报间隔](#如何自定义服务信息上报间隔)
- [测试插件](#测试插件)
- [禁用插件](#禁用插件)

## 插件简介

`server-info` 是一款能够定期将服务基本信息上报至 etcd，同时允许我们通过它提供的 API 在数据面访问到这些数据的插件。

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

在启动 APISIX 之后，即可通过访问 `/apisix/server_info` 来获取服务基本信息。

## 如何自定义服务信息上报间隔

我们可以在 `conf/config.yaml` 文件的 `plugin_attr` 一节中修改上报间隔。

| 名称         | 类型   | 默认值  | 描述                                                          |
| ------------ | ------ | -------- | -------------------------------------------------------------------- |
| report_interval | number | 60 | 上报服务信息至 etcd 的间隔（单位：秒）|

下面的例子将服务信息上报间隔修改成了 10 秒：

```yaml
plugin_attr:
  server-info:
    report_interval: 10
```


## 测试插件

```bash
curl http://127.0.0.1:9080/apisix/server_info -s | jq
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
