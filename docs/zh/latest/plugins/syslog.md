---
title: syslog
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

`sys` 是一个将 Log data 请求推送到 Syslog 的插件。

这将提供将 Log 数据请求作为 JSON 对象发送的功能。

## 属性列表

| 名称             | 类型    | 必选项 | 默认值       | 有效值        | 描述                                                                                                                                 |
| ---------------- | ------- | ------ | ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| host             | string  | 必须   |              |               | IP地址或主机名                                                                                                                       |
| port             | integer | 必须   |              |               | 目标上游端口                                                                                                                         |
| name             | string  | 可选   | "sys logger" |               |                                                                                                                                      |
| timeout          | integer | 可选   | 3            | [1, ...]      | 上游发送数据超时                                                                                                                     |
| tls              | boolean | 可选   | false        |               | 用于控制是否执行SSL验证                                                                                                              |
| flush_limit      | integer | 可选   | 4096         | [1, ...]      | 如果缓冲的消息的大小加上当前消息的大小达到（> =）此限制（以字节为单位），则缓冲的日志消息将被写入日志服务器。默认为4096（4KB）       |
| drop_limit       | integer | 可选   | 1048576      |               | 如果缓冲的消息的大小加上当前消息的大小大于此限制（以字节为单位），则由于缓冲区大小有限，当前的日志消息将被丢弃。默认为1048576（1MB） |
| sock_type        | string  | 可选   | "tcp"        | ["tcp","udp"] | 用于传输层的 IP 协议类型。                                                                                                             |
| max_retry_times  | integer | 可选   |              | [1, ...]      | 已废弃。请改用 `max_retry_count`。连接到日志服务器失败或将日志消息发送到日志服务器失败后的最大重试次数。                                                               |
| retry_interval   | integer | 可选   |              | [0, ...]      | 已废弃。请改用 `retry_delay`。重试连接到日志服务器或重试向日志服务器发送日志消息之前的时间延迟（以毫秒为单位）。                                                   |
| pool_size        | integer | 可选   | 5            | [5, ...]      | sock：keepalive 使用的 Keepalive 池大小。                                                                                               |
| include_req_body | boolean | 可选   | false        |               | 是否包括请求 body                                                                                                                    |

本插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

## 如何开启

1. 下面例子展示了如何为指定路由开启 `sys-logger` 插件的。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "syslog": {
            "host" : "127.0.0.1",
            "port" : 5044,
            "flush_limit" : 1
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "uri": "/hello"
}'
```

## 测试插件

* 成功的情况:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## 禁用插件

想要禁用“sys-logger”插件，是非常简单的，将对应的插件配置从 json 配置删除，就会立即生效，不需要重新启动服务：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
