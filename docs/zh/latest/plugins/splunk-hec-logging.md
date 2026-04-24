---
title: splunk-hec-logging
keywords:
  - APISIX
  - API 网关
  - Plugin
  - Splunk HTTP Event Collector
  - splunk-hec-logging
description: splunk-hec-logging 插件将请求和响应上下文信息序列化为 Splunk Event Data 格式并批量推送到 Splunk HTTP Event Collector（HEC），支持自定义日志格式以增强数据管理。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/splunk-hec-logging" />
</head>

## 描述

`splunk-hec-logging` 插件将请求和响应上下文信息序列化为 [Splunk Event Data 格式](https://docs.splunk.com/Documentation/Splunk/latest/Data/FormateventsforHTTPEventCollector#Event_metadata)并批量推送到 [Splunk HTTP Event Collector（HEC）](https://docs.splunk.com/Documentation/Splunk/latest/Data/UsetheHTTPEventCollector)。该插件还支持自定义日志格式。

## 属性

| 名称                       | 类型    | 必选项 | 默认值             | 有效值  | 描述                                                                                                                                                                                                                                       |
|----------------------------|---------|--------|--------------------|---------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| endpoint                   | object  | True   |                    |         | Splunk HEC endpoint 配置。                                                                                                                                                                                                                |
| endpoint.uri               | string  | True   |                    |         | Splunk HEC 事件收集器 API 端点。                                                                                                                                                                                                          |
| endpoint.token             | string  | True   |                    |         | Splunk HEC 鉴权 token。                                                                                                                                                                                                                   |
| endpoint.channel           | string  | False  |                    |         | Splunk HEC 发送数据通道标识符。详情参见 [About HTTP Event Collector Indexer Acknowledgment](https://docs.splunk.com/Documentation/Splunk/latest/Data/AboutHECIDXAck)。                                                                     |
| endpoint.timeout           | integer | False  | 10                 |         | Splunk HEC 发送数据超时时间（秒）。                                                                                                                                                                                                       |
| endpoint.keepalive_timeout | integer | False  | 60000              | >= 1000 | 保持连接的超时时间（毫秒）。                                                                                                                                                                                                              |
| ssl_verify                 | boolean | False  | true               |         | 若为 `true`，则按照 [OpenResty 文档](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake) 启用 SSL 验证。                                                                                                                    |
| log_format                 | object  | False  |                    |         | 以 JSON 键值对形式声明的自定义日志格式。值可通过 `$` 前缀引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。也可通过[插件元数据](#插件元数据)全局配置日志格式。          |
| name                       | string  | False  | splunk-hec-logging |         | 批处理器中插件的唯一标识符。                                                                                                                                                                                                              |
| batch_max_size             | integer | False  | 1000               | 大于 0  | 单批允许的日志条目数。达到此数量后，批次将被发送至 Splunk HEC。设置为 `1` 表示立即处理。                                                                                                                                                  |
| inactive_timeout           | integer | False  | 5                  | 大于 0  | 在发送批次到日志服务之前等待新日志的最长时间（秒）。该值应小于 `buffer_duration`。                                                                                                                                                        |
| buffer_duration            | integer | False  | 60                 | 大于 0  | 在发送批次到日志服务之前，允许最早条目存在的最长时间（秒）。                                                                                                                                                                              |
| retry_delay                | integer | False  | 1                  | >= 0    | 批次发送失败后重试的时间间隔（秒）。                                                                                                                                                                                                      |
| max_retry_count            | integer | False  | 60                 | >= 0    | 在丢弃日志条目之前允许的最大重试次数。                                                                                                                                                                                                    |

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据。如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

## 插件元数据

| 名称               | 类型    | 必选项 | 默认值 | 有效值 | 描述                                                                                                                                                                                                 |
|--------------------|---------|--------|--------|--------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format         | object  | False  |        |        | 以 JSON 键值对形式声明的自定义日志格式。值可通过 `$` 前缀引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。该配置全局生效，对所有绑定 `splunk-hec-logging` 的路由和服务生效。 |
| max_pending_entries | integer | False |        | >= 1   | 批处理器中允许的最大未处理条目数。达到此限制后，新条目将被丢弃，直到积压减少。                                                                                                                         |

## 示例

以下示例演示了如何为不同场景配置 `splunk-hec-logging` 插件。

按照示例操作，请先完成以下步骤设置 Splunk：

* 安装 [Splunk](https://www.splunk.com/en_us/download.html)。Splunk Web 默认运行在 `localhost:8000`。
* 参见[在 Splunk Web 中设置和使用 HTTP Event Collector](https://docs.splunk.com/Documentation/Splunk/latest/Data/UsetheHTTPEventCollector) 来设置 HTTP Event Collector。
* 在控制台右上角导航至 **Settings > Data Inputs**，你应该看到 HTTP Event Collector 中至少有一条 input。记录下 token 值。
* 在控制台右上角导航至 **Settings > Data Inputs** 并选择 **HTTP Event Collector**。在 **Global Settings** 中启用所有 tokens。
* 在 **Global Settings** 中，你还可以找到收集器的默认端口为 `8088`。

通过以下命令验证设置（替换为你的 token）：

```shell
curl "http://localhost:8088/services/collector/event" \
  -H "Authorization: Splunk <替换为你的 token>" \
  -d '{"event": "hello world"}'
```

你应该看到 `success` 响应。

:::note

你可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 推送日志到 Splunk

以下示例演示如何在路由上启用 `splunk-hec-logging` 插件，记录客户端请求并将日志推送到 Splunk。

创建如下路由，将 `uri` 替换为你的 Splunk HTTP 收集器端点和 IP 地址，`token` 替换为你的收集器 token：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "splunk-route",
    "uri": "/anything",
    "plugins": {
      "splunk-hec-logging":{
        "endpoint":{
          "uri":"http://192.168.2.108:8088/services/collector/event",
          "token":"26b15ddd-31db-455b-ak0c-9b5be3decc4a"
        }
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

向路由发送几条请求：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

你应该收到 `HTTP/1.1 200 OK` 响应。

在 Splunk Web 左侧菜单中选择 **Search & Reporting**。在搜索框中输入 `source="apache-apisix-splunk-hec-logging"` 搜索来自 APISIX 的事件。你应该看到对应请求的事件，例如：

```json
{
  "response_size": 617,
  "response_headers": {
    "server": "APISIX/3.10.0",
    "connection": "close",
    "content-type": "application/json",
    "access-control-allow-credentials": "true",
    "access-control-allow-origin": "*",
    "date": "Wed, 27 Nov 2024 19:49:27 GMT",
    "content-length": "389"
  },
  "request_headers": {
    "host": "127.0.0.1:9080",
    "user-agent": "curl/8.6.0",
    "accept": "*/*"
  },
  "request_query": {},
  "request_url": "http://127.0.0.1:9080/anything",
  "upstream": "18.208.8.205:80",
  "latency": 746.00005149841,
  "request_method": "GET",
  "request_size": 85,
  "response_status": 200
}
```

### 使用插件元数据记录请求和响应头

以下示例演示如何使用插件元数据和 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html) 自定义日志格式，以记录请求和响应中的特定头信息。

插件元数据全局生效，对所有 `splunk-hec-logging` 实例有效。如果单个插件实例上配置的日志格式与插件元数据中配置的日志格式不同，则实例级别的配置优先。

创建如下路由，将端点 `uri` 替换为你的 Splunk HTTP 收集器端点和 IP 地址，`token` 替换为你的收集器 token：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "splunk-route",
    "uri": "/anything",
    "plugins": {
      "splunk-hec-logging":{
        "endpoint":{
          "uri":"http://192.168.2.108:8088/services/collector/event",
          "token":"26b15ddd-31db-455b-ak0c-9b5be3decc4a"
        }
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

为 `splunk-hec-logging` 配置插件元数据，以记录自定义请求头 `env` 和响应头 `Content-Type`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/splunk-hec-logging" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "log_format": {
      "host": "$host",
      "@timestamp": "$time_iso8601",
      "client_ip": "$remote_addr",
      "env": "$http_env",
      "resp_content_type": "$sent_http_Content_Type"
    }
  }'
```

向路由发送带有 `env` 头的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H "env: dev"
```

在 Splunk Web 左侧菜单中选择 **Search & Reporting**。在搜索框中输入 `source="apache-apisix-splunk-hec-logging"` 搜索事件。你应该看到对应最新请求的事件，类似如下：

```json
{
  "host":"127.0.0.1",
  "env":"dev",
  "client_ip":"192.168.65.1",
  "@timestamp":"2024-11-27T20:59:28+00:00",
  "route_id":"splunk-route",
  "resp_content_type":"application/json"
}
```
