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

- [English](../../plugins/tcp-logger.md)

# 摘要

- [**定义**](#name)
- [**属性列表**](#attributes)
- [**如何开启**](#how-to-enable)
- [**测试插件**](#test-plugin)
- [**禁用插件**](#disable-plugin)

## 定义

`tcp-logger` 是用于将日志数据发送到TCP服务的插件。

以实现将日志数据以JSON格式发送到监控工具或其它TCP服务的能力。

该插件提供了将Log Data作为批处理推送到外部TCP服务器的功能。如果您没有收到日志数据，请放心一些时间，它会在我们的批处理处理器中的计时器功能到期后自动发送日志。

有关Apache APISIX中Batch-Processor的更多信息，请参考。
[Batch-Processor](../batch-processor.md)

## 属性列表

| 名称             | 类型    | 必选项 | 默认值 | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------ | ------- | ------------------------------------------------ |
| host             | string  | 必须   |        |         | TCP 服务的IP地址或主机名                         |
| port             | integer | 必须   |        | [0,...] | 目标端口                                         |
| timeout          | integer | 可选   | 1000   | [1,...] | 发送数据超时间                                   |
| tls              | boolean | 可选   | false  |         | 用于控制是否执行SSL验证                          |
| tls_options      | string  | 可选   |        |         | TLS 选项                                         |
| batch_max_size   | integer | 可选   | 1000   | [1,...] | 每批的最大大小                                   |
| inactive_timeout | integer | 可选   | 5      | [1,...] | 刷新缓冲区的最大时间（以秒为单位）               |
| buffer_duration  | integer | 可选   | 60     | [1,...] | 必须先处理批次中最旧条目的最长期限（以秒为单位） |
| max_retry_count  | integer | 可选   | 0      | [0,...] | 从处理管道中移除之前的最大重试次数               |
| retry_delay      | integer | 可选   | 1      | [0,...] | 如果执行失败，则应延迟执行流程的秒数             |
| include_req_body | boolean | 可选   |        |         | 是否包括请求 body                                |


## 如何开启

1. 下面例子展示了如何为指定路由开启 `tcp-logger` 插件的。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

想要禁用“tcp-logger”插件，是非常简单的，将对应的插件配置从json配置删除，就会立即生效，不需要重新启动服务：

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
