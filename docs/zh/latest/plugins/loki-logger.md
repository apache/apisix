---
title: loki-logger
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Loki-logger
  - Grafana Loki
description: 本文件包含关于 Apache APISIX loki-logger 插件的信息。
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

`loki-logger` 插件用于将日志转发到 [Grafana Loki](https://grafana.com/oss/loki/) 进行分析和存储。

当启用该插件时，APISIX 将把请求上下文信息序列化为 [JSON 中的日志条目](https://grafana.com/docs/loki/latest/api/#push-log-entries-to-loki) 并将其提交到批处理队列中。当队列中的数据量超过最大批处理大小时，数据将被推送到 Grafana Loki。有关更多详细信息，请参阅批处理处理器 [batch processor](../batch-processor.md)。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 描述 |
|--|---|---|---|---|
| endpoint_addrs | array[string] | True |  | Loki API 基础 URL，格式如 http://127.0.0.1:3100，支持 HTTPS 和域名。如果配置了多个端点，它们将随机选择一个进行写入 |
| endpoint_uri | string | False | /loki/api/v1/push | 如果您正在使用与 Loki Push API 兼容的日志收集服务，您可以使用此配置项自定义 API 路径。 |
| tenant_id | string | False | fake | Loki 租户 ID。根据 Loki 的 [多租户文档](https://grafana.com/docs/loki/latest/operations/multi-tenancy/#multi-tenancy)，在单租户模式下，默认值设置为 `fake`。 |
| log_labels | object | False | {job = "apisix"} | Loki 日志标签。您可以使用 [APISIX 变量](../apisix-variable.md) 和 [Nginx 变量](http://nginx.org/en/docs/varindex.html) 只需在字符串前面加上 `$` 符号即可，可以使用单个变量或组合变量，例如 `$host` 或 `$remote_addr:$remote_port`。 |
| ssl_verify    | boolean       | False    | true | 当设置为 `true` 时，将验证 SSL 证书。 |
| timeout       | integer       | False    | 3000ms | Loki 服务 HTTP 调用的超时时间，范围从 1 到 60,000 毫秒。  |
| keepalive     | boolean       | False    | true | 当设置为 `true` 时，会保持连接以供多个请求使用。 |
| keepalive_timeout | integer       | False    | 60000ms | 连接空闲时间后关闭连接。范围大于或等于 1000 毫秒。  |
| keepalive_pool | integer       | False    | 5       | 连接池限制。范围大于或等于 1。 |
| log_format | object | False    |          | 以 JSON 格式声明的键值对形式的日志格式。值仅支持字符串类型。可以通过在字符串前面加上 `$` 来使用 [APISIX 变量](../apisix-variable.md) 和 [Nginx 变量](http://nginx.org/en/docs/varindex.html) 。 |
| include_req_body   | boolean | False    | false | 当设置为 `true` 时，日志中将包含请求体。如果请求体太大而无法在内存中保存，则由于 Nginx 的限制，无法记录请求体。|
| include_req_body_expr | array   | False    |  | 当 `include_req_body` 属性设置为 `true` 时的过滤器。只有当此处设置的表达式求值为 `true` 时，才会记录请求体。有关更多信息，请参阅 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 。 |
| include_resp_body  | boolean | False    | false | 当设置为 `true` 时，日志中将包含响应体。 |
| include_resp_body_expr | array   | False    | | 当 `include_resp_body` 属性设置为 `true` 时的过滤器。只有当此处设置的表达式求值为 `true` 时，才会记录响应体。有关更多信息，请参阅 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 。 |

该插件支持使用批处理器对条目（日志/数据）进行批量聚合和处理，避免了频繁提交数据的需求。批处理器每隔 `5` 秒或当队列中的数据达到 `1000` 时提交数据。有关更多信息或设置自定义配置，请参阅 [批处理器](../batch-processor.md#configuration)。

### 默认日志格式示例

```json
{
  "request": {
    "headers": {
      "connection": "close",
      "host": "localhost",
      "test-header": "only-for-test#1"
    },
    "method": "GET",
    "uri": "/hello",
    "url": "http://localhost:1984/hello",
    "size": 89,
    "querystring": {}
  },
  "client_ip": "127.0.0.1",
  "start_time": 1704525701293,
  "apisix_latency": 100.99994659424,
  "response": {
    "headers": {
      "content-type": "text/plain",
      "server": "APISIX/3.7.0",
      "content-length": "12",
      "connection": "close"
    },
    "status": 200,
    "size": 118
  },
  "route_id": "1",
  "loki_log_time": "1704525701293000000",
  "upstream_latency": 5,
  "latency": 105.99994659424,
  "upstream": "127.0.0.1:1980",
  "server": {
    "hostname": "localhost",
    "version": "3.7.0"
  },
  "service_id": ""
}
```

## 元数据

您还可以通过配置插件元数据来设置日志的格式。以下配置项可供选择：

| 名称 | 类型 | 必选项 | 默认值 | 描述 |
|------|------|----------|--|-------------|
| log_format | object | False |  | 日志格式以 JSON 格式声明为键值对。值只支持字符串类型。可以通过在字符串前面加上 `$` 来使用 [APISIX 变量](../apisix-variable.md) 和 [Nginx 变量](http://nginx.org/en/docs/varindex.html) 。 |

:::info 重要提示

配置插件元数据具有全局范围。这意味着它将对使用 `loki-logger` 插件的所有路由和服务生效。

:::

以下示例展示了如何通过 Admin API 进行配置：

:::note

您可以像这样从 config.yaml 中获取 admin_key 。

```bash
 admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/loki-logger -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

使用这个配置，您的日志将被格式化为以下形式：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## 启用插件

以下示例展示了如何在特定的路由上启用 `loki-logger` 插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
        "loki-logger": {
            "endpoint_addrs" : ["http://127.0.0.1:3100"]
        }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
    },
    "uri": "/hello"
}'
```

## 示例用法

现在，如果您向 APISIX 发出请求，该请求将被记录在您的 Loki 服务器中：

```shell
curl -i http://127.0.0.1:9080/hello
```

## 删除插件

当您需要删除 `loki-logger` 插件时，您可以使用以下命令删除相应的 JSON 配置，APISIX 将自动重新加载相关配置，而无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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

## FAQ

### 日志未正确推送

请查看 `error.log` 文件以获取此类日志。

```text
2023/04/30 13:45:46 [error] 19381#19381: *1075673 [lua] batch-processor.lua:95: Batch Processor[loki logger] failed to process entries: loki server returned status: 401, body: no org id, context: ngx.timer, client: 127.0.0.1, server: 0.0.0.0:9081
```

可以根据错误代码 `failed to process entries: loki server returned status: 401, body: no org id` 和 loki 服务器的响应正文来诊断错误。

### 当请求每秒 (RPS) 较高时出现错误？

- 请确保 `keepalive` 相关的配置已正确设置。有关更多信息，请参阅[属性](#属性) 。
- 请检查 `error.log` 中的日志，查找此类日志。

    ```text
    2023/04/30 13:49:34 [error] 19381#19381: *1082680 [lua] batch-processor.lua:95: Batch Processor[loki logger] failed to process entries: loki server returned status: 429, body: Ingestion rate limit exceeded for user tenant_1 (limit: 4194304 bytes/sec) while attempting to ingest '1000' lines totaling '616307' bytes, reduce log volume or contact your Loki administrator to see if the limit can be increased, context: ngx.timer, client: 127.0.0.1, server: 0.0.0.0:9081
    ```

  - 通常与高 QPS 相关的日志如上所示。错误信息为：`Ingestion rate limit exceeded for user tenant_1 (limit: 4194304 bytes/sec) while attempting to ingest '1000' lines totaling '616307' bytes, reduce log volume or contact your Loki administrator to see if the limit can be increased`。
  - 请参考 [Loki 文档](https://grafana.com/docs/loki/latest/configuration/#limits_config) ，添加默认日志量和突发日志量的限制，例如 `ingestion_rate_mb` 和 `ingestion_burst_size_mb`。

    在开发过程中进行测试时，将 `ingestion_burst_size_mb` 设置为 100 可以确保 APISIX 以至少 10000 RPS 的速率正确推送日志。
