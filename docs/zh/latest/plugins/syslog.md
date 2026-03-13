---
title: syslog
keywords:
  - APISIX
  - API 网关
  - Plugin
  - syslog
description: API 网关 Apache APISIX syslog 插件可用于将日志推送到 Syslog 服务器。
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

`syslog` 插件可用于将日志推送到 Syslog 服务器。

该插件还实现了将日志数据以 JSON 格式发送到 Syslog 服务的能力。

## 属性

| 名称             | 类型     | 必选项 | 默认值       | 有效值        | 描述                                                                                                                                 |
| ---------------- | ------- | ------ | ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| host             | string  | 是     |              |               | IP 地址或主机名。                                                                                                                      |
| port             | integer | 是     |              |               | 目标上游端口。                                                                                                                         |
| name             | string  | 否     | "sys logger" |               | 标识 logger 的唯一标识符。如果您使用 Prometheus 监视 APISIX 指标，名称将以 `apisix_batch_process_entries` 导出。                                                                                                                |
| timeout          | integer | 否     | 3000         | [1, ...]      | 上游发送数据超时（以毫秒为单位）。                                                                                                       |
| tls              | boolean | 否     | false        |               | 当设置为 `true` 时执行 SSL 验证。                                                                                                       |
| flush_limit      | integer | 否     | 4096         | [1, ...]      | 如果缓冲的消息的大小加上当前消息的大小达到（> =）此限制（以字节为单位），则缓冲的日志消息将被写入日志服务器，默认为 4096（4KB）。              |
| drop_limit       | integer | 否     | 1048576      |               | 如果缓冲的消息的大小加上当前消息的大小大于此限制（以字节为单位），则由于缓冲区大小有限，当前的日志消息将被丢弃，默认为 1048576（1MB）。        |
| sock_type        | string  | 否     | "tcp"        | ["tcp","udp"] | 用于传输层的 IP 协议类型。                                                                                                               |
| max_retry_count  | integer | 否     |              | [1, ...]      | 连接到日志服务器失败或将日志消息发送到日志服务器失败后的最大重试次数。                                                                      |
| retry_delay      | integer | 否     |              | [0, ...]      | 重试连接到日志服务器或重试向日志服务器发送日志消息之前的时间延迟（以毫秒为单位）。                                                           |
| pool_size        | integer | 否     | 5            | [5, ...]      | `sock：keepalive` 使用的 Keepalive 池大小。                                                                                              |
| log_format             | object  | 否   |          |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| include_req_body | boolean | 否     | false        |  [false, true]    | 当设置为 `true` 时包括请求体。                                                                                                        |
| include_req_body_expr   | array         | 否   |       |               | 当 `include_req_body` 属性设置为 `true` 时的过滤器。只有当此处设置的表达式求值为 `true` 时，才会记录请求体。有关更多信息，请参阅 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 。    |
| include_resp_body       | boolean       | 否   | false | [false, true] | 当设置为 `true` 时，包含响应体。                                                                                                                               |
| include_resp_body_expr  | array         | 否   |       |               | 当 `include_resp_body` 属性设置为 `true` 时进行过滤响应体，并且只有当此处设置的表达式计算结果为 `true` 时，才会记录响应体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

### 默认日志格式示例

```text
"<46>1 2024-01-06T02:30:59.145Z 127.0.0.1 apisix 82324 - - {\"response\":{\"status\":200,\"size\":141,\"headers\":{\"content-type\":\"text/plain\",\"server\":\"APISIX/3.7.0\",\"transfer-encoding\":\"chunked\",\"connection\":\"close\"}},\"route_id\":\"1\",\"server\":{\"hostname\":\"baiyundeMacBook-Pro.local\",\"version\":\"3.7.0\"},\"request\":{\"uri\":\"/opentracing\",\"url\":\"http://127.0.0.1:1984/opentracing\",\"querystring\":{},\"method\":\"GET\",\"size\":155,\"headers\":{\"content-type\":\"application/x-www-form-urlencoded\",\"host\":\"127.0.0.1:1984\",\"user-agent\":\"lua-resty-http/0.16.1 (Lua) ngx_lua/10025\"}},\"upstream\":\"127.0.0.1:1982\",\"apisix_latency\":100.99999809265,\"service_id\":\"\",\"upstream_latency\":1,\"start_time\":1704508259044,\"client_ip\":\"127.0.0.1\",\"latency\":101.99999809265}\n"
```

## 插件元数据

| 名称         | 类型     | 必选项 | 默认值 | 描述                                                                                                                                                             |
|------------|--------|-----|-----|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format | object | 否   |     | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |

:::info 重要

该设置全局生效。如果指定了 `log_format`，则所有绑定 `syslog` 的路由或服务都将使用该日志格式。

:::

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "syslog": {
            "host" : "127.0.0.1",
            "port" : 5044,
            "flush_limit" : 1
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
curl http://127.0.0.1:9180/apisix/admin/routes/1  \
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
