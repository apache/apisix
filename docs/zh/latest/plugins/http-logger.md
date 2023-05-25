---
title: http-logger
keywords:
  - APISIX
  - API 网关
  - 插件
  - HTTP Logger
  - 日志
description: 本文介绍了 API 网关 Apache APISIX 的 http-logger 插件。使用该插件可以将 APISIX 的日志数据推送到 HTTP 或 HTTPS 服务器。
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

`http-logger` 插件可以将 APISIX 的日志数据推送到 HTTP 或 HTTPS 服务器。该插件提供了将日志数据请求作为 JSON 对象发送到监控工具或者其他 HTTP 服务器的功能。

## 属性

| 名称                   | 类型     | 必选项 | 默认值         | 有效值               | 描述                                             |
| ---------------------- | ------- | ------ | ------------- | -------------------- | ------------------------------------------------ |
| uri                    | string  | 是     |               |                      | HTTP 或 HTTPS 服务器的 URI。                   |
| auth_header            | string  | 否     |               |                      | 授权 header（如果需要）。                                    |
| timeout                | integer | 否     | 3             | [1,...]              | 发送请求后保持连接处于活动状态的时间。           |
| log_format             | object  | 否     |               |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| include_req_body       | boolean | 否     | false         | [false, true]        | 当设置为 `true` 时，将请求体包含在日志中。如果请求体太大而无法保存在内存中，由于 NGINX 的限制，无法记录。 |
| include_resp_body      | boolean | 否     | false         | [false, true]        | 当设置为 `true` 时，包含响应体。                                                                                               |
| include_resp_body_expr | array   | 否     |               |                      | 当 `include_resp_body` 属性设置为 `true` 时，使用该属性并基于 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 进行过滤。如果存在，则仅在表达式计算结果为 `true` 时记录响应。       |
| concat_method          | string  | 否     | "json"        | ["json", "new_line"] | 枚举类型： **json**：对所有待发日志使用 `json.encode` 编码。**new_line**：对每一条待发日志单独使用 `json.encode` 编码并使用 `\n` 连接起来。 |
| ssl_verify             | boolean | 否     | false          | [false, true]       | 当设置为 `true` 时验证证书。 |

该插件支持使用批处理器来聚合并批量处理条目（日志和数据）。这样可以避免该插件频繁地提交数据。默认情况下每 `5` 秒钟或队列中的数据达到 `1000` 条时，批处理器会自动提交数据，如需了解更多信息或自定义配置，请参考 [Batch Processor](../batch-processor.md#配置)。

## 插件元数据

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 否    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头。则表明获取 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |

:::info 注意

该设置全局生效。如果指定了 `log_format`，则所有绑定 `http-logger` 的路由或服务都将使用该日志格式。

:::

以下示例展示了如何通过 Admin API 配置插件元数据：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/http-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

配置完成后，你将在日志系统中看到如下类似日志：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## 启用插件

你可以通过如下命令在指定路由上启用 `http-logger` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "http-logger": {
                "uri": "http://mockbin.org/bin/:ID"
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

[mockbin](http://mockbin.org/bin/create) 服务器用于模拟 HTTP 服务器，以方便查看 APISIX 生成的日志。

## 测试插件

你可以通过以下命令向 APISIX 发出请求，访问日志将记录在你的 `mockbin` 服务器中：

```shell
curl -i http://127.0.0.1:9080/hello
```

## 禁用插件

当你需要禁用该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
