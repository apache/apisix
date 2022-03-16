---
title: tcp-logger
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

`tcp-logger` 是用于将日志数据发送到 TCP 服务的插件。

以实现将日志数据以 JSON 格式发送到监控工具或其它 TCP 服务的能力。

该插件提供了将 Log Data 作为批处理推送到外部 TCP 服务器的功能。如果您没有收到日志数据，请放心一些时间，它会在我们的批处理处理器中的计时器功能到期后自动发送日志。

有关 Apache APISIX 中 Batch-Processor 的更多信息，请参考：
[Batch-Processor](../batch-processor.md)

## 属性列表

| 名称             | 类型    | 必选项 | 默认值 | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------ | ------- | ------------------------------------------------ |
| host             | string  | 必须   |        |         | TCP 服务的 IP 地址或主机名                         |
| port             | integer | 必须   |        | [0,...] | 目标端口                                         |
| timeout          | integer | 可选   | 1000   | [1,...] | 发送数据超时间                                   |
| tls              | boolean | 可选   | false  |         | 用于控制是否执行 SSL 验证                          |
| tls_options      | string  | 可选   |        |         | TLS 选项                                         |
| include_req_body | boolean | 可选   |        |         | 是否包括请求 body                                |

本插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

## 如何开启

1. 下面例子展示了如何为指定路由开启 `tcp-logger` 插件的。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "tcp-logger": {
                 "host": "127.0.0.1",
                 "port": 5044,
                 "tls": false,
                 "batch_max_size": 1,
                 "name": "tcp logger"
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

想要禁用“tcp-logger”插件，是非常简单的，将对应的插件配置从 json 配置删除，就会立即生效，不需要重新启动服务：

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
