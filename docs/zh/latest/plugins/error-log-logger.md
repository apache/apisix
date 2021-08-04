---
title: error-log-logger
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

## 摘要

- [**定义**](#定义)
- [**属性列表**](#属性列表)
- [**如何开启和禁用**](#如何开启和禁用)
- [**如何更新**](#如何更新)

## 定义

`error-log-logger` 是用于按用户设定的 log 级别对 APISIX 的 `error.log` 进行筛选，继而将筛选的数据发送到 TCP 服务或者 [Apache SkyWalking](https://skywalking.apache.org/) 的插件。

以实现将 error.log 中的数据进行筛选并发送到监控工具或其它 TCP 服务，和通过 HTTP 发送到 SkyWalking 的能力。

该插件提供了将日志数据作为批处理推送到外部 TCP 服务器的功能。如果您没有收到日志数据，请放心一些时间，它会在我们的批处理处理器中的计时器功能到期后自动发送日志。

有关 Apache APISIX 中 Batch-Processor 的更多信息，请参考。
[Batch-Processor](../batch-processor.md)

## 属性列表

| 名称                              | 类型     | 必选项 | 默认值                          | 有效值   | 描述                                                                              |
| -------------------------------- | ------- | ----- | ------------------------------ | ---------------- | -------------------------------------------------------------------------|
| tcp.host                         | string  | 必须   |                                |                  | TCP 服务的IP地址或主机名                                                    |
| tcp.port                         | integer | 必须   |                                | [0,...]          | 目标端口                                                                  |
| tcp.tls                          | boolean | 可选   | false                          |                  | 用于控制是否执行SSL验证                                                     |
| tcp.tls_server_name              | string  | 可选   |                                |                  | TLS 服务名称标记                                                          |
| skywalking.endpoint_addr         | string  | 可选   | http://127.0.0.1:12900/v3/logs |                  | Skywalking 的 HTTP endpoint 地址，例如：http://127.0.0.1:12800             |
| skywalking.service_name          | string  | 可选   | APISIX                         |                  | skywalking 上报的 service 名称                                            |
| skywalking.service_instance_name | String  | 可选   | APISIX Instance Name           |                  | skywalking 上报的 service 实例名, 如果期望直接获取本机主机名则设置为 `$hostname` |
| host                             | string  | 可选   |                                |                  | (`弃用`，替换成`tcp.host`) TCP 服务的IP地址或主机名                           |
| port                             | integer | 可选   |                                | [0,...]          | (`弃用`，替换成`tcp.port`) 目标端口                                         |
| tls                              | boolean | 可选   | false                          |                  | (`弃用`，替换成`tcp.tls`) 用于控制是否执行SSL验证                             |
| tls_server_name                  | string  | 可选   |                                |                  | (`弃用`，替换成`tcp.tls_server_name`) TLS 服务名称标记                       |
| timeout                          | integer | 可选   | 3                              | [1,...]          | 连接和发送数据超时间（以秒为单位）                                             |
| keepalive                        | integer | 可选   | 30                             | [1,...]          | 复用连接时，连接保持的时间（以秒为单位）                                        |
| level                            | string  | 可选   | WARN                           |                  | 进行错误日志筛选的级别，缺省WARN，取值["STDERR", "EMERG", "ALERT", "CRIT", "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"]，其中 ERR 与 ERROR 级别一致                                     |
| inactive_timeout                 | integer | 可选   | 3                              | [1,...]          | 刷新缓冲区的最大时间（以秒为单位）                                             |
| batch_max_size                   | integer | 可选   | 1000                           | [1,...]          | 每批的最大大小                                                             |
| buffer_duration                  | integer | 可选   | 60                             | [1,...]          | 必须先处理批次中最旧条目的最长期限（以秒为单位）                                 |
| max_retry_count                  | integer | 可选   | 0                              | [0,...]          | 从处理管道中移除之前的最大重试次数                                             |
| retry_delay                      | integer | 可选   | 1                              | [0,...]          | 如果执行失败，则应延迟执行流程的秒数                                           |

## 如何开启和禁用

本插件属于 APISIX 全局性插件。

### 开启插件

在 `conf/config.yaml` 中启用插件 `error-log-logger` 即可，不需要在任何 route 或 service 中绑定。
下面是一个在`conf/config.yaml` 中添加插件信息的例子：

```yaml
plugins:                          # plugin list
  ... ...
  - request-id
  - hmac-auth
  - api-breaker
  - error-log-logger              # enable plugin `error-log-logger
```

### 禁用插件

在 `conf/config.yaml` 中删除或注释掉插件 `error-log-logger`即可。

```yaml
plugins:                          # plugin list
  ... ...
  - request-id
  - hmac-auth
  - api-breaker
  #- error-log-logger              # enable plugin `error-log-logger
```

## 如何设置接收日志的 TCP 服务器

步骤：更新插件属性

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/error-log-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "tcp": {
    "host": "127.0.0.1",
    "port": 1999
  },
  "inactive_timeout": 1
}'
```

## 如何设置接收日志的 SkyWalking OAP 服务器

步骤：更新插件属性

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/error-log-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "skywalking": {
    "endpoint_addr": "http://127.0.0.1:12800/v3/logs"
  },
  "inactive_timeout": 1
}'
```
