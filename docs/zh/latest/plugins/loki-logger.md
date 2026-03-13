---
title: loki-logger
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Loki-logger
  - Grafana Loki
description: loki-logger 插件通过 Loki HTTP API /loki/api/v1/push 将请求和响应日志批量推送到 Grafana Loki。该插件还支持自定义日志格式。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/loki-logger" />
</head>

## 描述

`loki-logger` 插件通过 [Loki HTTP API](https://grafana.com/docs/loki/latest/reference/loki-http-api/#loki-http-api) `/loki/api/v1/push` 将请求和响应日志批量推送到 [Grafana Loki](https://grafana.com/oss/loki/)。该插件还支持自定义日志格式。

启用后，插件会将请求上下文信息序列化为 [JSON object](https://grafana.com/docs/loki/latest/api/#push-log-entries-to-loki) 并将其添加到队列中，然后再将其推送到 Loki。有关更多详细信息，请参阅批处理处理器 [batch processor](../batch-processor.md)。

## 属性

| 名称 | 类型 | 必选项 | 默认值 | 有效值 | 描述 |
|--|---|---|---|---|
| end_addrs | array[string] | 是 | | | Loki API URL，例如 `http://127.0.0.1:3100`。如果配置了多个端点，日志将被推送到列表中随机确定的端点。 |
| end_uri | string | 否 | /loki/api/v1/push | | Loki 提取端点的 URI 路径。 |
| tenant_id | string | 否 | fake | | Loki 租户 ID。根据 Loki 的 [多租户文档](https://grafana.com/docs/loki/latest/operations/multi-tenancy/#multi-tenancy)，在单租户下默认值设置为 `fake`。 |
| headers | object | 否 |  |  | 请求头键值对（对 `X-Scope-OrgID` 和 `Content-Type` 的设置将会被忽略）。 |
| log_labels | object | 否 | {job = "apisix"} | | Loki 日志标签。支持 [NGINX 变量](https://nginx.org/en/docs/varindex.html) 和值中的常量字符串。变量应以 `$` 符号为前缀。例如，标签可以是 `{"origin" = "apisix"}` 或 `{"origin" = "$remote_addr"}`。|
| ssl_verify | boolean | 否 | true | | 如果为 true，则验证 Loki 的 SSL 证书。|
| timeout | integer | 否 | 3000 | [1, 60000] | Loki 服务 HTTP 调用的超时时间（以毫秒为单位）。|
| keepalive | boolean | 否 | true | | 如果为 true，则保持连接以应对多个请求。|
| keepalive_timeout | integer | 否 | 60000 | >=1000 | Keepalive 超时时间（以毫秒为单位）。|
| keepalive_pool | integer | 否 | 5 | >=1 | 连接池中的最大连接数。|
| log_format | object | 否 | | | 自定义日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过 `$` 前缀引用 [APISIX 变量](../apisix-variable.md) 和 [NGINX 变量](http://nginx.org/en/docs/varindex.html)。 |
| name | string | 否 | loki-logger | | 批处理器插件的唯一标识符。如果使用 [Prometheus](./prometheus.md) 监控 APISIX 指标，则名称会导出到 `apisix_batch_process_entries`。 |
| include_req_body | boolean | 否 | false | | 如果为 true，则将请求正文包含在日志中。请注意，如果请求正文太大而无法保存在内存中，则由于 NGINX 的限制而无法记录。 |
| include_req_body_expr | array[array] | 否 | | |一个或多个 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 形式条件的数组。在 `include_req_body` 为 true 时使用。仅当此处配置的表达式计算结果为 true 时，才会记录请求正文。|
| include_resp_body | boolean | 否 | false | | 如果为 true，则将响应正文包含在日志中。|
| include_resp_body_expr | array[array] | 否 | | | 一个或多个 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 形式条件的数组。在 `include_resp_body` 为 true 时使用。仅当此处配置的表达式计算结果为 true 时，才会记录响应正文。|

该插件支持使用批处理器对条目（日志/数据）进行批量聚合和处理，避免了频繁提交数据的需求。批处理器每隔 `5` 秒或当队列中的数据达到 `1000` 时提交数据。有关更多信息或设置自定义配置，请参阅 [批处理器](../batch-processor.md#configuration)。

## Plugin Metadata

您还可以使用 [Plugin Metadata](../terminology/plugin-metadata.md) 全局配置日志格式，该 Plugin Metadata 配置所有 `loki-logger` 插件实例的日志格式。如果在单个插件实例上配置的日志格式与在 Plugin Metadata 上配置的日志格式不同，则在单个插件实例上配置的日志格式优先。

| 名称 | 类型 | 必选项 | 默认值 | 描述 |
|------|------|----------|--|-------------|
| log_format | object | 否 |  | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 和 [NGINX 变量](http://nginx.org/en/docs/varindex.html)。 |
| max_pending_entries | integer | 否 | | | 在批处理器中开始删除待处理条目之前可以购买的最大待处理条目数。|

## 示例

下面的示例演示了如何为不同场景配置 `loki-logger` 插件。

为了遵循示例，请在 Docker 中启动一个示例 Loki 实例：

```shell
wget https://raw.githubusercontent.com/grafana/loki/v3.0.0/cmd/loki/loki-local-config.yaml -O loki-config.yaml
docker run --name loki -d -v $(pwd):/mnt/config -p 3100:3100 grafana/loki:3.2.1 -config.file=/mnt/config/loki-config.yaml
```

此外，启动 Grafana 实例来查看和可视化日志：

```shell
docker run -d --name=apisix-quickstart-grafana \
  -p 3000:3000 \
  grafana/grafana-oss
```

要连接 Loki 和 Grafana，请访问 Grafana，网址为 [`http://localhost:3000`](http://localhost:3000)。在 __Connections > Data sources__ 下，添加新数据源并选择 Loki。您的连接 URL 应遵循 `http://{your_ip_address}:3100` 的格式。保存新数据源时，Grafana 还应测试连接，您应该会看到 Grafana 通知数据源已成功连接。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 以默认日志格式记录请求和响应

以下示例演示了如何在路由上配置 `loki-logger` 插件以记录通过路由的请求和响应。

使用 `loki-logger` 插件创建路由并配置 Loki 的地址：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "loki-logger-route",
    "uri": "/anything",
    "plugins": {
      "loki-logger": {
        "endpoint_addrs": ["http://192.168.1.5:3100"]
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

向路由发送一些请求以生成日志条目：

```shell
curl "http://127.0.0.1:9080/anything"
```

您应该会收到所有请求的“HTTP/1.1 200 OK”响应。

导航到 [Grafana explore view](http://localhost:3000/explore) 并运行查询 `job = apisix`。您应该会看到与您的请求相对应的许多日志，例如以下内容：

```json
{
  "route_id": "loki-logger-route",
  "response": {
    "status": 200,
    "headers": {
      "date": "Fri, 03 Jan 2025 03:54:26 GMT",
      "server": "APISIX/3.11.0",
      "access-control-allow-credentials": "true",
      "content-length": "391",
      "access-control-allow-origin": "*",
      "content-type": "application/json",
      "connection": "close"
    },
    "size": 619
  },
  "start_time": 1735876466,
  "client_ip": "192.168.65.1",
  "service_id": "",
  "apisix_latency": 5.0000038146973,
  "upstream": "34.197.122.172:80",
  "upstream_latency": 666,
  "server": {
    "hostname": "0b9a772e68f8",
    "version": "3.11.0"
  },
  "request": {
    "headers": {
      "user-agent": "curl/8.6.0",
      "accept": "*/*",
      "host": "127.0.0.1:9080"
    },
    "size": 85,
    "method": "GET",
    "url": "http://127.0.0.1:9080/anything",
    "querystring": {},
    "uri": "/anything"
  },
  "latency": 671.0000038147
}
```

这验证了 Loki 已从 APISIX 接收日志。您还可以在 Grafana 中创建仪表板，以进一步可视化和分析日志。

### 使用 Plugin Metadata 自定义日志格式

以下示例演示了如何使用 [Plugin Metadata](../terminology/plugin-metadata.md) 自定义日志格式。

使用 `loki-logger` 插件创建路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "loki-logger-route",
    "uri": "/anything",
    "plugins": {
      "loki-logger": {
        "endpoint_addrs": ["http://192.168.1.5:3100"]
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org": 1
      }
    }
  }'
```

为 `loki-logger` 配置 Plugin Metadata，它将更新所有需要记录请求的路由的日志格式：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/loki-logger" -X PUT \
  -H 'X-API-KEY: ${admin_key}' \
  -d '{
    "log_format": {
      "host": "$host",
      "client_ip": "$remote_addr",
      "route_id": "$route_id",
      "@timestamp": "$time_iso8601"
    }
  }'
```

向路由发送请求以生成新的日志条目：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

导航到 [Grafana explore view](http://localhost:3000/explore) 并运行查询 `job = apisix`。您应该会看到与您的请求相对应的日志条目，类似于以下内容：

```json
{
  "@timestamp":"2025-01-03T21:11:34+00:00",
  "client_ip":"192.168.65.1",
  "route_id":"loki-logger-route",
  "host":"127.0.0.1"
}
```

如果路由上的插件指定了特定的日志格式，它将优先于 Plugin Metadata 中指定的日志格式。例如，按如下方式更新上一个路由上的插件：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/loki-logger-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "loki-logger": {
        "log_format": {
          "route_id": "$route_id",
          "client_ip": "$remote_addr",
          "@timestamp": "$time_iso8601"
        }
      }
    }
  }'
```

向路由发送请求以生成新的日志条目：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

导航到 [Grafana explore view](http://localhost:3000/explore) 并重新运行查询 `job = apisix`。您应该会看到与您的请求相对应的日志条目，与路由上配置的格式一致，类似于以下内容：

```json
{
  "client_ip":"192.168.65.1",
  "route_id":"loki-logger-route",
  "@timestamp":"2025-01-03T21:19:45+00:00"
}
```

### 有条件地记录请求主体

以下示例演示了如何有条件地记录请求主体。

使用 `loki-logger` 创建路由，仅在 URL 查询字符串 `log_body` 为 `yes` 时记录请求主体：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "loki-logger-route",
    "uri": "/anything",
    "plugins": {
      "loki-logger": {
        "endpoint_addrs": ["http://192.168.1.5:3100"],
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

使用满足条件的 URL 查询字符串向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything?log_body=yes" -X POST -d '{"env": "dev"}'
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

导航到 [Grafana explore view](http://localhost:3000/explore) 并重新运行查询 `job = apisix`。您应该会看到与您的请求相对应的日志条目，与路由上配置的格式一致，类似于以下内容：

```json
{
  "route_id": "loki-logger-route",
  ...,
  "request": {
    "headers": {
      ...
    },
    "body": "{\"env\": \"dev\"}",
    "size": 182,
    "method": "POST",
    "url": "http://127.0.0.1:9080/anything?log_body=yes",
    "querystring": {
      "log_body": "yes"
    },
    "uri": "/anything?log_body=yes"
  },
  "latency": 809.99994277954
}
```

向路由发送一个没有任何 URL 查询字符串的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST -d '{"env": "dev"}'
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

导航到 [Grafana explore view](http://localhost:3000/explore) 并重新运行查询 `job = apisix`。您应该会看到与您的请求相对应的日志条目，与路由上配置的格式一致，类似于以下内容：

```json
{
  "route_id": "loki-logger-route",
  ...,
  "request": {
    "headers": {
      ...
    },
    "size": 169,
    "method": "POST",
    "url": "http://127.0.0.1:9080/anything",
    "querystring": {},
    "uri": "/anything"
  },
  "latency": 557.00016021729
}
```

:::info

如果您除了将 `include_req_body` 或 `include_resp_body` 设置为 `true` 之外还自定义了 `log_format`，则插件不会在日志中包含正文。

作为一种解决方法，您可以在日志格式中使用 NGINX 变量 `$request_body`，例如：

```json
{
  "kafka-logger": {
    ...,
    "log_format": {"body": "$request_body"}
  }
}
```

:::

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
