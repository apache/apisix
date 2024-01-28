---
title: skywalking-logger
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - SkyWalking
description: 本文将介绍 API 网关 Apache APISIX 如何通过 skywalking-logger 插件将日志数据推送到 SkyWalking OAP 服务器。
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

`skywalking-logger` 插件可用于将 APISIX 的访问日志数据推送到 SkyWalking OAP 服务器。

如果上下文中存在 `tracing context`，插件会自动建立 `trace` 与日志的关联，该功能依赖于 [SkyWalking Cross Process Propagation Headers Protocol](https://skywalking.apache.org/docs/main/next/en/api/x-process-propagation-headers-v3/)。

该插件也提供了将访问日志作为 JSON 对象发送到 SkyWalking OAP 服务器的能力。

## 属性

| 名称                    | 类型    | 必选项 | 默认值                | 有效值           | 描述                                                                                                                                               |
| ---------------------- | ------- | ------ | -------------------- |---------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| endpoint_addr          | string  | 是     |                      |               | SkyWalking OAP 服务器的 URI。                                                                                                                         |
| service_name           | string  | 否     |"APISIX"              |               | SkyWalking 服务名称。                                                                                                                                 |
| service_instance_name  | string  | 否     |"APISIX Instance Name"|               | SkyWalking 服务的实例名称。当设置为 `$hostname`会直接获取本地主机名。                                                                                                   |
| log_format             | object  | 否   |          |               | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| timeout                | integer | 否     | 3                    | [1,...]       | 发送请求后保持连接活动的时间。                                                                                                                                  |
| name                   | string  | 否     | "skywalking logger"  |               | 标识 logger 的唯一标识符。如果您使用 Prometheus 监视 APISIX 指标，名称将以 `apisix_batch_process_entries` 导出。                                                           |
| include_req_body       | boolean | 否     | false                | [false, true] | 当设置为 `true` 时，将请求正文包含在日志中。                                                                                                                       |
| include_req_body_expr   | array         | 否   |       |               | 当 `include_req_body` 属性设置为 `true` 时的过滤器。只有当此处设置的表达式求值为 `true` 时，才会记录请求体。有关更多信息，请参阅 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 。    |
| include_resp_body       | boolean       | 否   | false | [false, true] | 当设置为 `true` 时，包含响应体。                                                                                                                               |
| include_resp_body_expr  | array         | 否   |       |               | 当 `include_resp_body` 属性设置为 `true` 时进行过滤响应体，并且只有当此处设置的表达式计算结果为 `true` 时，才会记录响应体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

### 默认日志格式示例

  ```json
   {
      "serviceInstance": "APISIX Instance Name",
      "body": {
        "json": {
          "json": "body-json"
        }
      },
      "endpoint": "/opentracing",
      "service": "APISIX"
    }
  ```

对于 body-json 数据，它是一个转义后的 json 字符串，格式化后如下：

  ```json
    {
      "response": {
        "status": 200,
        "headers": {
          "server": "APISIX/3.7.0",
          "content-type": "text/plain",
          "transfer-encoding": "chunked",
          "connection": "close"
        },
        "size": 136
      },
      "route_id": "1",
      "upstream": "127.0.0.1:1982",
      "upstream_latency": 8,
      "apisix_latency": 101.00020599365,
      "client_ip": "127.0.0.1",
      "service_id": "",
      "server": {
        "hostname": "localhost",
        "version": "3.7.0"
      },
      "start_time": 1704429712768,
      "latency": 109.00020599365,
      "request": {
        "headers": {
          "content-length": "9",
          "host": "localhost",
          "connection": "close"
        },
        "method": "POST",
        "body": "body-data",
        "size": 94,
        "querystring": {},
        "url": "http://localhost:1984/opentracing",
        "uri": "/opentracing"
      }
    }
  ```

## 配置插件元数据

`skywalking-logger` 也支持自定义日志格式，与 [http-logger](./http-logger.md) 插件类似。

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 否   |  |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX](../apisix-variable.md) 或 [NGINX](http://nginx.org/en/docs/varindex.html) 变量。|

:::info 重要

该配置全局生效。如果你指定了 `log_format`，该配置就会对所有绑定 `skywalking-logger` 的路由或服务生效。

:::

以下示例展示了如何通过 Admin API 进行插件元数据配置：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/skywalking-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

配置成功后，将得到如下日志格式：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## 启用插件

完成 SkyWalking OAP 配置后，你可以通过以下命令在路由中启用该插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

现在你可以向 APISIX 发起请求：

```shell
curl -i http://127.0.0.1:9080/hello
```

完成上述步骤后，你可以在 SkyWalking UI 查看到相关日志。

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
