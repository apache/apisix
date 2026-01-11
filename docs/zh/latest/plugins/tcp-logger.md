---
title: tcp-logger
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - TCP Logger
description: 本文介绍了 API 网关 Apache APISIX 如何使用 tcp-logger 插件将日志数据发送到 TCP 服务器。
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

`tcp-logger` 插件可用于将日志数据发送到 TCP 服务器。

该插件还实现了将日志数据以 JSON 格式发送到监控工具或其它 TCP 服务的能力。

## 属性

| 名称             | 类型     | 必选项  | 默认值 | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------ | ------- | ------------------------------------------------ |
| host             | string  | 是     |        |         | TCP 服务器的 IP 地址或主机名。                     |
| port             | integer | 是     |        | [0,...] | 目标端口。                                        |
| timeout          | integer | 否     | 1000   | [1,...] | 发送数据超时间。                                   |
| log_format       | object  | 否   |          |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| tls              | boolean | 否     | false  |         | 用于控制是否执行 SSL 验证。                        |
| tls_options      | string  | 否     |        |         | TLS 选项。                                        |
| include_req_body | boolean | 否     |        | [false, true] | 当设置为 `true` 时，日志中将包含请求体。           |
| include_req_body_expr | array | 否 |       |           | 当 `include_req_body` 属性设置为 `true` 时的过滤器。只有当此处设置的表达式求值为 `true` 时，才会记录请求体。有关更多信息，请参阅 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 。    |
| include_resp_body | boolean | 否     | false | [false, true]| 当设置为 `true` 时，日志中将包含响应体。                                                     |
| include_resp_body_expr | array | 否 |       |           | 当 `include_resp_body` 属性设置为 `true` 时进行过滤响应体，并且只有当此处设置的表达式计算结果为 `true` 时，才会记录响应体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

### 默认日志格式示例

```json
{
  "response": {
    "status": 200,
    "headers": {
      "server": "APISIX/3.7.0",
      "content-type": "text/plain",
      "content-length": "12",
      "connection": "close"
    },
    "size": 118
  },
  "server": {
    "version": "3.7.0",
    "hostname": "localhost"
  },
  "start_time": 1704527628474,
  "client_ip": "127.0.0.1",
  "service_id": "",
  "latency": 102.9999256134,
  "apisix_latency": 100.9999256134,
  "upstream_latency": 2,
  "request": {
    "headers": {
      "connection": "close",
      "host": "localhost"
    },
    "size": 59,
    "method": "GET",
    "uri": "/hello",
    "url": "http://localhost:1984/hello",
    "querystring": {}
  },
  "upstream": "127.0.0.1:1980",
  "route_id": "1"
}
```

## 插件元数据

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 否    |  |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| max_pending_entries | integer | 否 | | | 在批处理器中开始删除待处理条目之前可以购买的最大待处理条目数。|

:::info 注意

该设置全局生效。如果指定了 `log_format`，则所有绑定 `tcp-logger` 的路由或服务都将使用该日志格式。

:::

以下示例展示了如何通过 Admin API 配置插件元数据：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/tcp-logger \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr",
        "request": { "method": "$request_method", "uri": "$request_uri" },
        "response": { "status": "$status" }
    }
}'
```

配置完成后，你将在日志系统中看到如下类似日志：

```json
{"@timestamp":"2023-01-09T14:47:25+08:00","route_id":"1","host":"localhost","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200}}
```

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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
