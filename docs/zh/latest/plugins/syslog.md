---
title: syslog
keywords:
  - APISIX
  - API 网关
  - Plugin
  - syslog
description: API 网关 Apache APISIX syslog 插件可用于将日志推送到 Syslog 服务器。
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

`syslog` 插件可用于将日志推送到 Syslog 服务器。

该插件还实现了将日志数据以 JSON 格式发送到 Syslog 服务的能力。

## 属性

| 名称             | 类型     | 必选项 | 默认值       | 有效值        | 描述                                                                                                                                 |
| ---------------- | ------- | ------ | ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| host             | string  | 是     |              |               | IP 地址或主机名。                                                                                                                      |
| port             | integer | 是     |              |               | 目标上游端口。                                                                                                                         |
| timeout          | integer | 否     | 3000         | [1, ...]      | 上游发送数据超时（以毫秒为单位）。                                                                                                       |
| tls              | boolean | 否     | false        |               | 当设置为 `true` 时执行 SSL 验证。                                                                                                       |
| flush_limit      | integer | 否     | 4096         | [1, ...]      | 如果缓冲的消息的大小加上当前消息的大小达到（> =）此限制（以字节为单位），则缓冲的日志消息将被写入日志服务器，默认为 4096（4KB）。              |
| drop_limit       | integer | 否     | 1048576      |               | 如果缓冲的消息的大小加上当前消息的大小大于此限制（以字节为单位），则由于缓冲区大小有限，当前的日志消息将被丢弃，默认为 1048576（1MB）。        |
| sock_type        | string  | 否     | "tcp"        | ["tcp","udp"] | 用于传输层的 IP 协议类型。                                                                                                               |
| max_retry_count  | integer | 否     |              | [1, ...]      | 连接到日志服务器失败或将日志消息发送到日志服务器失败后的最大重试次数。                                                                      |
| retry_delay      | integer | 否     |              | [0, ...]      | 重试连接到日志服务器或重试向日志服务器发送日志消息之前的时间延迟（以毫秒为单位）。                                                           |
| pool_size        | integer | 否     | 5            | [5, ...]      | `sock：keepalive` 使用的 Keepalive 池大小。                                                                                              |
| log_format             | object  | 否   |          |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| include_req_body | boolean | 否     | false        |               | 当设置为 `true` 时包括请求体。                                                                                                        |

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

## 插件元数据

| 名称         | 类型     | 必选项 | 默认值 | 描述                                                                                                                                                             |
|------------|--------|-----|-----|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format | object | 否   |     | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头。则表明获取 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |

:::info 重要

该设置全局生效。如果指定了 `log_format`，则所有绑定 `syslog` 的路由或服务都将使用该日志格式。

:::

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

现在你可以向 APISIX 发起请求：

```shell
curl -i http://127.0.0.1:9080/hello
```

```
HTTP/1.1 200 OK
...
hello, world
```

## 删除插件

当你需要删除该插件时，可通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
