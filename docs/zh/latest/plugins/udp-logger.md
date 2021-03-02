---
title: udp-logger
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

- [摘要](#摘要)
- [定义](#定义)
- [属性列表](#属性列表)
- [如何开启](#如何开启)
- [测试插件](#测试插件)
- [禁用插件](#禁用插件)

## 定义

`udp-logger` 是用于将日志数据发送到 UDP 服务的插件。

以实现将日志数据以 JSON 格式发送到监控工具或其它 UDP 服务的能力。

此插件提供了将批处理数据批量推送到外部 UDP 服务器的功能。如果您没有收到日志数据，请放心一些时间，它会在我们的批处理处理器中的计时器功能到期后自动发送日志

有关 Apache APISIX 中 Batch-Processor 的更多信息，请参考。
[Batch-Processor](../batch-processor.md)

## 属性列表

| 名称             | 类型    | 必选项 | 默认值       | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------ | ------- | ------------------------------------------------ |
| host             | string  | 必须   |              |         | UDP 服务的 IP 地址或主机名                       |
| port             | integer | 必须   |              | [0,...] | 目标端口                                         |
| timeout          | integer | 可选   | 1000         | [1,...] | 发送数据超时间                                   |
| name             | string  | 可选   | "udp logger" |         | 用于识别批处理器                                 |
| batch_max_size   | integer | 可选   | 1000         | [1,...] | 每批的最大大小                                   |
| inactive_timeout | integer | 可选   | 5            | [1,...] | 刷新缓冲区的最大时间（以秒为单位）               |
| buffer_duration  | integer | 可选   | 60           | [1,...] | 必须先处理批次中最旧条目的最长期限（以秒为单位） |
| include_req_body | boolean | 可选   |              |         | 是否包括请求 body                                |

## 如何开启

1. 下面例子展示了如何为指定路由开启 `udp-logger` 插件的。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

* 成功的情况:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## 禁用插件

想要禁用“udp-logger”插件，是非常简单的，将对应的插件配置从 json 配置删除，就会立即生效，不需要重新启动服务：

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
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
