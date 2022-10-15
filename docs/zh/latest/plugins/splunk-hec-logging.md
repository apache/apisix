---
title: splunk-hec-logging
keywords:
  - APISIX
  - API 网关
  - 插件
  - Splunk
  - 日志
description: API 网关 Apache APISIX 的 splunk-hec-logging 插件可用于将请求日志转发到 Splunk HTTP 事件收集器（HEC）中进行分析和存储。
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

`splunk-hec-logging` 插件可用于将请求日志转发到 Splunk HTTP 事件收集器（HEC）中进行分析和存储。

启用该插件后，APISIX 将在 `Log Phase` 获取请求上下文信息，并将其序列化为 [Splunk Event Data 格式](https://docs.splunk.com/Documentation/Splunk/latest/Data/FormateventsforHTTPEventCollector#Event_metadata) 后提交到批处理队列中，当触发批处理队列每批次最大处理容量或刷新缓冲区的最大时间时会将队列中的数据提交到 `Splunk HEC` 中。

## 属性

| 名称                | 必选项  | 默认值 | 描述                                                                                                                                                               |
| ------------------  | ------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| endpoint            | 是     |        | Splunk HEC 端点配置信息。                                                                                                                                            |
| endpoint.uri        | 是     |        | Splunk HEC 事件收集 API。                                                                                                                                            |
| endpoint.token      | 是     |        | Splunk HEC 身份令牌。                                                                                                                                                |
| endpoint.channel    | 否     |        | Splunk HEC 发送渠道标识，更多信息请参考 [About HTTP Event Collector Indexer Acknowledgment](https://docs.splunk.com/Documentation/Splunk/8.2.3/Data/AboutHECIDXAck)。 |
| endpoint.timeout    | 否     | 10     | Splunk HEC 数据提交超时时间（以秒为单位）。                                                                                                                             |
| ssl_verify          | 否     | true   | 当设置为 `true` 时，启用 `SSL` 验证。                                                                                                                                 |

本插件支持使用批处理器来聚合并批量处理条目（日志和数据）。这样可以避免该插件频繁地提交数据。默认情况下每 `5` 秒钟或队列中的数据达到 `1000` 条时，批处理器会自动提交数据，如需了解更多信息或自定义配置，请参考 [Batch-Processor](../batch-processor.md#配置)。

## 启用插件

以下示例展示了如何在指定路由上启用该插件：

**完整配置**

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

**最小化配置**

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

你可以通过以下命令向 APISIX 发出请求：

```shell
curl -i http://127.0.0.1:9080/splunk.do?q=hello
```

```
HTTP/1.1 200 OK
...
hello, world
```

访问成功后，你可以登录 Splunk 控制台检索查看日志：

![splunk hec search view](../../../assets/images/plugin/splunk-hec-admin-cn.png)

## 禁用插件

当你需要禁用该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
