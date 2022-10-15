---
title: udp-logger
keywords:
  - APISIX
  - API 网关
  - Plugin
  - UDP Logger
description: 本文介绍了 API 网关 Apache APISIX 如何使用 udp-logger 插件将日志数据发送到 UDP 服务器。
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

`udp-logger` 插件可用于将日志数据发送到 UDP 服务器。

该插件还实现了将日志数据以 JSON 格式发送到监控工具或其它 UDP 服务的能力。

## 属性

| 名称             | 类型    | 必选项  | 默认值       | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------ | ------- | ------------------------------------------------ |
| host             | string  | 是     |              |         | UDP 服务的 IP 地址或主机名。                       |
| port             | integer | 是     |              | [0,...] | 目标端口。                                         |
| timeout          | integer | 否     | 1000         | [1,...] | 发送数据超时间。                                   |
| name             | string  | 否     | "udp logger" |         | 用于识别批处理器。                                 |
| include_req_body | boolean | 否     |              |         | 当设置为 `true` 时，日志中将包含请求体。           |

该插件支持使用批处理器来聚合并批量处理条目（日志和数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

## 如何开启

你可以通过如下命令在指定路由上启用 `udp-logger` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "udp-logger": {
                 "host": "127.0.0.1",
                 "port": 3000,
                 "batch_max_size": 1,
                 "name": "udp logger"
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

## 禁用插件

当你需要禁用该插件时，可通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
