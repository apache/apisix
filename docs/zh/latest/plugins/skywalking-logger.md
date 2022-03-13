---
title: skywalking-logger
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

`http-logger` 是一个插件，可将 Access Log 数据通过 `HTTP` 推送到 SkyWalking OAP 服务器。如果上下文中存在 `tracing context`，插件会自动建立 `trace` 与日志的关联，并依赖于 [SkyWalking Cross Process Propagation Headers Protocol](https://skywalking.apache.org/docs/main/latest/en/protocols/skywalking-cross-process-propagation-headers-protocol-v3/) 。

这将提供将 Access Log 数据作为JSON对象发送到 SkyWalking OAP 服务器的功能。

## 属性列表

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| endpoint_addr    | string  | 必须   |               |         | `SkyWalking OAp` 服务器的 URI。                   |
| service_name   | string  | 可选   |"APISIX"         |         | `SkyWalking` 服务名称。                           |
| service_instance_name    | string  | 可选   |"APISIX Instance Name"|         | `SkyWalking`服务实例名称，将其设置为`$hostname`以直接获取本地主机名。 |
| timeout          | integer | 可选   | 3             | [1,...] | 发送请求后保持连接活动的时间。                      |
| name             | string  | 可选   | "skywalking logger" |         | 标识 logger 的唯一标识符。                   |
| include_req_body | boolean | 可选   | false         | [false, true] | 是否包括请求 body。false： 表示不包含请求的 body ； true： 表示包含请求的 body 。 |

本插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

## 如何开启

这是有关如何为特定路由启用 `skywalking-logger` 插件的示例。在此之前，需要有可用的 SkyWalking OAP 可以被访问。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "skywalking-logger": {
                "endpoint_addr": "http://127.0.0.1:12800"
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

> 成功:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

完成上述步骤后，在可以 SkyWalking UI 查看到相关日志。

## 插件元数据设置

`skywalking-logger` 也是制定日志格式，与 [http-logger](./http-logger.md) 插件类似。

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 可选   | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 __APISIX__ 变量或 [Nginx 内置变量](http://nginx.org/en/docs/varindex.html)。|

特别的，**该设置是全局生效的**，意味着指定 log_format 后，将对所有绑定 skywalking-logger 的 Route 或 Service 生效。

## 禁用插件

在插件配置中删除相应的 json 配置以禁用 skywalking-logger。APISIX 插件是热重载的，因此无需重新启动 APISIX：

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
