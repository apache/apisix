---
title: splunk-hec-logging
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
- [**如何开启**](#如何开启)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 定义

`splunk-hec-logging` 插件用于将 `Apache APISIX` 的请求日志转发到 `Splunk HTTP 事件收集器（HEC）` 中进行分析和存储，启用该插件后 `Apache APISIX` 将在 `Log Phase` 获取请求上下文信息并序列化为 [Splunk Event Data 格式](https://docs.splunk.com/Documentation/Splunk/latest/Data/FormateventsforHTTPEventCollector#Event_metadata) 后提交到批处理队列中，当触发批处理队列每批次最大处理容量或刷新缓冲区的最大时间时会将队列中的数据提交到 `Splunk HEC` 中。

有关 `Apache APISIX` 的 `Batch-Processor` 的更多信息，请参考：
[Batch-Processor](../batch-processor.md)

## 属性列表

| 名称                  | 是否必需 | 默认值                                                                                                                                                                                         | 描述                                                                                                                                                           |
| ----------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| endpoint                | 必选   |                                                                                                                                                                                                   | Splunk HEC 端点配置信息                                                                                                                                     |
| endpoint.uri            | 必选   |                                                                                                                                                                                                   | Splunk HEC 事件收集API                                                                                                                                     |
| endpoint.token          | 必选   |                                                                                                                                                                                                   | Splunk HEC 身份令牌                                                                                                                                        |
| endpoint.channel        | 可选   |                                                                                                                                                                                                   | Splunk HEC 发送渠道标识，参考：[About HTTP Event Collector Indexer Acknowledgment](https://docs.splunk.com/Documentation/Splunk/8.2.3/Data/AboutHECIDXAck)   |
| endpoint.timeout        | 可选   | 10                                                                                                                                                                                                | Splunk HEC 数据提交超时时间（以秒为单位）                                                                                                                      |
| ssl_verify              | 可选   | true                                                                                                                                                                                              | 启用 `SSL` 验证, 参考：[OpenResty文档](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake)                                                    |
| max_retry_count         | 可选   | 0                                                                                                                                                                                                 | 从处理管道中移除之前的最大重试次数                                                                                                                              |
| retry_delay             | 可选   | 1                                                                                                                                                                                                 | 如果执行失败，流程执行应延迟的秒数                                                                                                                              |
| buffer_duration         | 可选   | 60                                                                                                                                                                                                | 必须先处理批次中最旧条目的最大期限（以秒为单位）                                                                                                                  |
| inactive_timeout        | 可选   | 5                                                                                                                                                                                                 | 刷新缓冲区的最大时间（以秒为单位）                                                                                                                              |
| batch_max_size          | 可选   | 1000                                                                                                                                                                                              | 每个批处理队列可容纳的最大条目数                                                                                                                               |

## 如何开启

下面例子展示了如何为指定路由开启 `splunk-hec-logging` 插件。

### 完整配置

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins":{
        "splunk-hec-logging":{
            "endpoint":{
                "uri":"http://127.0.0.1:8088/services/collector",
                "token":"BD274822-96AA-4DA6-90EC-18940FB2414C",
                "channel":"FE0ECFAD-13D5-401B-847D-77833BD77131",
                "timeout":60
            },
            "buffer_duration":60,
            "max_retry_count":0,
            "retry_delay":1,
            "inactive_timeout":2,
            "batch_max_size":10
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    },
    "uri":"/splunk.do"
}'
```

### 最小化配置

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins":{
        "splunk-hec-logging":{
            "endpoint":{
                "uri":"http://127.0.0.1:8088/services/collector",
                "token":"BD274822-96AA-4DA6-90EC-18940FB2414C"
            }
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    },
    "uri":"/splunk.do"
}'
```

## 测试插件

* 向配置 `splunk-hec-logging` 插件的路由发送请求

```shell
$ curl -i http://127.0.0.1:9080/splunk.do?q=hello
HTTP/1.1 200 OK
...
hello, world
```

* 登录Splunk控制台检索查看日志

![splunk hec search view](../../../assets/images/plugin/splunk-hec-admin-cn.png)

## 禁用插件

禁用 `splunk-hec-logging` 插件非常简单，只需将 `splunk-hec-logging` 对应的 `JSON` 配置移除即可。

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
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
