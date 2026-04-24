---
title: syslog
keywords:
  - APISIX
  - API 网关
  - Plugin
  - syslog
description: syslog 插件将请求和响应日志以 JSON 对象批量推送到 syslog 服务器，支持自定义日志格式以增强数据管理能力。
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

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/syslog" />
</head>

## 描述

`syslog` 插件将请求和响应日志以 JSON 对象批量推送到 syslog 服务器，并支持自定义日志格式。

## 属性

| 名称                   | 类型    | 必选项 | 默认值       | 有效值                | 描述                                                                                                                                                                                                                                                                                   |
|------------------------|---------|--------|--------------|-----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| host                   | string  | True   |              |                       | syslog 服务器的 IP 地址或主机名。                                                                                                                                                                                                                                                      |
| port                   | integer | True   |              |                       | syslog 服务器的目标端口。                                                                                                                                                                                                                                                              |
| timeout                | integer | False  | 3000         | 大于 0                | 向上游发送数据的超时时间（毫秒）。                                                                                                                                                                                                                                                     |
| tls                    | boolean | False  | false        |                       | 若为 true，则验证 TLS。                                                                                                                                                                                                                                                                |
| flush_limit            | integer | False  | 4096         | 大于 0                | 推送日志到 syslog 服务器前，缓冲区和当前消息的最大大小（字节，B）。                                                                                                                                                                                                                   |
| drop_limit             | integer | False  | 1048576      | 大于 0                | 丢弃日志前，缓冲区和当前消息允许的最大大小（字节，B）。                                                                                                                                                                                                                               |
| sock_type              | string  | False  | `tcp`        | `tcp` 或 `udp`        | 使用的传输层协议。                                                                                                                                                                                                                                                                     |
| pool_size              | integer | False  | 5            | 大于等于 5            | `sock:keepalive` 使用的连接池大小。                                                                                                                                                                                                                                                    |
| log_format             | object  | False  |              |                       | 以 JSON 键值对形式声明的自定义日志格式，值可以引用 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。也可以通过[插件元数据](../plugin-metadata.md)在全局范围内配置日志格式，将应用于所有 `syslog` 插件实例。如果插件实例的日志格式与插件元数据的日志格式不同，插件实例的日志格式优先生效。 |
| include_req_body       | boolean | False  | false        |                       | 若为 true，则在日志中包含请求体。注意：若请求体太大而无法保存在内存中，由于 NGINX 的限制，将无法记录。                                                                                                                                                                                 |
| include_req_body_expr  | array   | False  |              |                       | [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式数组。当 `include_req_body` 为 true 时使用，仅当此处表达式求值为 true 时才记录请求体。                                                                                                                                  |
| include_resp_body      | boolean | False  | false        |                       | 若为 true，则在日志中包含响应体。                                                                                                                                                                                                                                                      |
| include_resp_body_expr | array   | False  |              |                       | [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式数组。当 `include_resp_body` 为 true 时使用，仅当此处表达式求值为 true 时才记录响应体。                                                                                                                                 |
| max_req_body_bytes     | integer | False  | 524288       | 大于等于 1            | 日志中记录的最大请求体字节数。超出该值的请求体将被截断。在 APISIX 3.16.0 版本中可用。                                                                                                                                                                                                  |
| max_resp_body_bytes    | integer | False  | 524288       | 大于等于 1            | 日志中记录的最大响应体字节数。超出该值的响应体将被截断。在 APISIX 3.16.0 版本中可用。                                                                                                                                                                                                  |
| name                   | string  | False  | `sys logger` |                       | 批处理器中插件的唯一标识符。若使用 Prometheus 监控 APISIX 指标，该名称将以 `apisix_batch_process_entries` 导出。                                                                                                                                                                        |
| batch_max_size         | integer | False  | 1000         | 大于 0                | 每批次允许的最大日志条目数。达到该值后，批次将被发送至日志服务。设置为 1 表示立即处理。                                                                                                                                                                                                |
| inactive_timeout       | integer | False  | 5            | 大于 0                | 在将批次发送至日志服务前等待新日志的最长时间（秒）。该值应小于 `buffer_duration`。                                                                                                                                                                                                     |
| buffer_duration        | integer | False  | 60           | 大于 0                | 发送批次前允许最早条目存在的最长时间（秒）。                                                                                                                                                                                                                                           |
| retry_delay            | integer | False  | 1            | 大于等于 0            | 批次发送失败后重试的时间间隔（秒）。                                                                                                                                                                                                                                                   |
| max_retry_count        | integer | False  | 60           | 大于等于 0            | 丢弃日志条目前允许的最大重试次数。                                                                                                                                                                                                                                                     |

:::note

该插件支持使用批处理器来聚合并批量处理条目（日志/数据），避免频繁提交数据。默认情况下，批处理器每 `5` 秒或队列数据达到 `1000` 条时提交数据。详情请参考[批处理器](../batch-processor.md#configuration)。

:::

## 插件元数据

也可以通过配置插件元数据来设置日志格式，可用配置如下：

| 名称       | 类型   | 必选项 | 描述                                                                                                                                               |
|------------|--------|--------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format | object | False  | 以 JSON 键值对形式声明的自定义日志格式，值可以引用 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。                         |

:::info IMPORTANT

插件元数据的配置为全局范围生效，将作用于所有使用 `syslog` 插件的路由和服务。

:::

## 使用示例

以下示例演示如何在不同场景下配置 `syslog` 插件。

请先在 Docker 中启动一个示例 rsyslog 服务器：

```shell
docker run -d -p 514:514 --name example-rsyslog-server rsyslog/syslog_appliance_alpine
```

:::note

您可以通过以下命令从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 推送日志到 Syslog 服务器

以下示例演示如何在路由上启用 `syslog` 插件，记录客户端请求并推送日志到 syslog 服务器。

创建带 `syslog` 的路由，将 `host` 和 `port` 替换为您 syslog 服务器的地址和端口，并将 `flush_limit` 设为 1 以立即推送日志：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "syslog-route",
    "uri": "/anything",
    "plugins": {
      "syslog": {
        "host" : "172.0.0.1",
        "port" : 514,
        "flush_limit" : 1
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应收到 `HTTP/1.1 200 OK` 响应。

在 syslog 服务器中，您应看到类似如下的日志条目：

```json
{
  "response": {
    "status": 200,
    "headers": {
      "access-control-allow-credentials": "true",
      "connection": "close",
      "date": "Sat, 02 Mar 2024 00:14:19 GMT",
      "access-control-allow-origin": "*",
      "server": "APISIX/3.8.0",
      "content-type": "application/json",
      "content-length": "387"
    },
    "size": 614
  },
  "service_id": "",
  "client_ip": "172.19.0.1",
  "server": {
    "hostname": "eff61bf7be4d",
    "version": "3.8.0"
  },
  "upstream": "35.171.123.176:80",
  "apisix_latency": 13.999900817871,
  "request": {
    "method": "GET",
    "url": "http://127.0.0.1:9080/anything",
    "querystring": {},
    "size": 86,
    "uri": "/anything",
    "headers": {
      "host": "127.0.0.1:9080",
      "accept": "*/*",
      "user-agent": "curl/7.29.0"
    }
  },
  "route_id": "syslog-route",
  "upstream_latency": 165,
  "latency": 178.99990081787,
  "start_time": 1709334859598
}
```

### 通过插件元数据自定义日志格式

以下示例演示如何使用[插件元数据](../plugin-metadata.md)自定义日志格式。插件元数据中配置的日志格式将应用于所有 `syslog` 插件实例。

创建带 `syslog` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "syslog-route",
    "uri": "/anything",
    "plugins": {
      "syslog": {
        "host" : "172.0.0.1",
        "port" : 514,
        "flush_limit" : 1
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

为 `syslog` 配置插件元数据：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/syslog" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "log_format": {
      "host": "$host",
      "@timestamp": "$time_iso8601",
      "route_id": "$route_id",
      "client_ip": "$remote_addr",
      "resp_content_type": "$sent_http_Content_Type"
    }
  }'
```

向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

在 syslog 服务器中，您应看到类似如下的日志条目：

```json
{
  "@timestamp": "2024-03-02T00:00:31+00:00",
  "resp_content_type": "application/json",
  "host": "127.0.0.1",
  "route_id": "syslog-route",
  "client_ip": "172.19.0.1"
}
```

### 按条件记录请求体

以下示例演示如何按条件记录请求体。

创建如下带 `syslog` 插件的路由，仅当 URL 查询参数 `log_body` 为 `yes` 时才记录请求体：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "syslog-route",
    "uri": "/anything",
    "plugins": {
      "syslog": {
        "host" : "172.0.0.1",
        "port" : 514,
        "flush_limit" : 1,
        "include_req_body": true,
        "include_req_body_expr": [["arg_log_body", "==", "yes"]]
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    }
  }'
```

发送满足条件的带 URL 查询参数的请求：

```shell
curl -i "http://127.0.0.1:9080/anything?log_body=yes" -X POST -d '{"env": "dev"}'
```

您应看到日志中包含请求体：

```json
{
  "request": {
    "method": "POST",
    "url": "http://127.0.0.1:9080/anything?log_body=yes",
    "querystring": {
      "log_body": "yes"
    },
    "size": 183,
    "body": "{\"env\": \"dev\"}",
    "uri": "/anything?log_body=yes",
    "headers": {
      "accept": "*/*",
      "user-agent": "curl/7.29.0",
      "host": "127.0.0.1:9080",
      "content-type": "application/x-www-form-urlencoded",
      "content-length": "14"
    }
  }
}
```

不带 URL 查询参数发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST -d '{"env": "dev"}'
```

此时日志中将不包含请求体。

:::note

若在将 `include_req_body` 或 `include_resp_body` 设为 `true` 的同时自定义了 `log_format`，插件将不会在日志中包含请求体或响应体。

解决方法是在日志格式中使用 NGINX 变量 `$request_body`，例如：

```json
{
  "syslog": {
    "log_format": {"body": "$request_body"}
  }
}
```

:::
