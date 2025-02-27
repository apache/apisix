---
title: public-api
keywords:
  - APISIX
  - API 网关
  - Public API
description: public-api 插件公开了一个内部 API 端点，使其可被公开访问。该插件的主要用途之一是公开由其他插件创建的内部端点。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/public-api" />
</head>

## 描述

`public-api` 插件公开了一个内部 API 端点，使其可被公开访问。该插件的主要用途之一是公开由其他插件创建的内部端点。

## 属性

| 名称  | 类型   | 必选项 | 默认值 | 有效值 | 描述 |
|------|--------|-------|-------|------|------|
| uri  | string | 否    |    |   | 内部端点的 URI。如果未配置，则暴露路由的 URI。|

## 示例

以下示例展示了如何在不同场景中配置 `public-api`。

### 在自定义端点暴露 Prometheus 指标

以下示例演示如何禁用默认在端口 `9091` 上暴露端点的 Prometheus 导出服务器，并在 APISIX 用于监听其他客户端请求的端口 `9080` 上，通过新的公共 API 端点暴露 APISIX 的 Prometheus 指标。

此外，还会配置路由，使内部端点 `/apisix/prometheus/metrics` 通过自定义端点对外公开。

:::caution

如果收集了大量指标，插件可能会占用大量 CPU 资源用于计算，从而影响正常请求的处理。

为了解决这个问题，APISIX 使用 [特权代理进程](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/process.md#enable_privileged_agent) ，并将指标计算卸载至独立进程。如果使用配置文件中 `plugin_attr.prometheus.export_addr` 设定的指标端点，该优化将自动生效。但如果通过 `public-api` 插件暴露指标端点，则不会受益于此优化。

:::

在配置文件中禁用 Prometheus 导出服务器，并重新加载 APISIX 以使更改生效：

```yaml
plugin_attr:
  prometheus:
    enable_export_server: false
```

接下来，创建一个带有 `public-api` 插件的路由，并为 APISIX 指标暴露一个公共 API 端点。你应将路由的 `uri` 设置为自定义端点路径，并将插件的 `uri` 设置为要暴露的内部端点。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H 'X-API-KEY: ${admin_key}' \
  -d '{
    "id": "prometheus-metrics",
    "uri": "/prometheus_metrics",
    "plugins": {
      "public-api": {
        "uri": "/apisix/prometheus/metrics"
      }
    }
  }'
```

向自定义指标端点发送请求：

```shell
curl http://127.0.0.1:9080/prometheus_metrics
```

你应看到类似以下的输出：

```text
# HELP apisix_http_requests_total The total number of client requests since APISIX started
# TYPE apisix_http_requests_total gauge
apisix_http_requests_total 1
# HELP apisix_nginx_http_current_connections Number of HTTP connections
# TYPE apisix_nginx_http_current_connections gauge
apisix_nginx_http_current_connections{state="accepted"} 1
apisix_nginx_http_current_connections{state="active"} 1
apisix_nginx_http_current_connections{state="handled"} 1
apisix_nginx_http_current_connections{state="reading"} 0
apisix_nginx_http_current_connections{state="waiting"} 0
apisix_nginx_http_current_connections{state="writing"} 1
...
```

### 暴露批量请求端点

以下示例展示了如何使用 `public-api` 插件来暴露 `batch-requests` 插件的端点，该插件用于将多个请求组合成一个请求，然后将它们发送到网关。

创建一个样本路由到 httpbin 的 `/anything` 端点，用于验证目的：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "httpbin-anything",
    "uri": "/anything",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

创建一个带有 `public-api` 插件的路由，并将路由的 `uri` 设置为要暴露的内部端点：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "batch-requests",
    "uri": "/apisix/batch-requests",
    "plugins": {
      "public-api": {}
    }
  }'
```

向暴露的批量请求端点发送一个包含 GET 和 POST 请求的流水线请求：

```shell
curl "http://127.0.0.1:9080/apisix/batch-requests" -X POST -d '
{
  "pipeline": [
    {
      "method": "GET",
      "path": "/anything"
    },
    {
      "method": "POST",
      "path": "/anything",
      "body": "a post request"
    }
  ]
}'
```

您应该会收到两个请求的响应，类似于以下内容：

```json
[
  {
    "reason": "OK",
    "body": "{\n  \"args\": {}, \n  \"data\": \"\", \n  \"files\": {}, \n  \"form\": {}, \n  \"headers\": {\n    \"Accept\": \"*/*\", \n    \"Host\": \"127.0.0.1\", \n    \"User-Agent\": \"curl/8.6.0\", \n    \"X-Amzn-Trace-Id\": \"Root=1-67b6e33b-5a30174f5534287928c54ca9\", \n    \"X-Forwarded-Host\": \"127.0.0.1\"\n  }, \n  \"json\": null, \n  \"method\": \"GET\", \n  \"origin\": \"192.168.107.1, 43.252.208.84\", \n  \"url\": \"http://127.0.0.1/anything\"\n}\n",
    "headers": {
      ...
    },
    "status": 200
  },
  {
    "reason": "OK",
    "body": "{\n  \"args\": {}, \n  \"data\": \"a post request\", \n  \"files\": {}, \n  \"form\": {}, \n  \"headers\": {\n    \"Accept\": \"*/*\", \n    \"Content-Length\": \"14\", \n    \"Host\": \"127.0.0.1\", \n    \"User-Agent\": \"curl/8.6.0\", \n    \"X-Amzn-Trace-Id\": \"Root=1-67b6e33b-0eddcec07f154dac0d77876f\", \n    \"X-Forwarded-Host\": \"127.0.0.1\"\n  }, \n  \"json\": null, \n  \"method\": \"POST\", \n  \"origin\": \"192.168.107.1, 43.252.208.84\", \n  \"url\": \"http://127.0.0.1/anything\"\n}\n",
    "headers": {
      ...
    },
    "status": 200
  }
]
```

如果您希望在自定义端点处暴露批量请求端点，请创建一个带有 `public-api` 插件的路由。您应该将路由的 `uri` 设置为自定义端点路径，并将插件的 uri 设置为要暴露的内部端点。

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "batch-requests",
    "uri": "/batch-requests",
    "plugins": {
      "public-api": {
        "uri": "/apisix/batch-requests"
      }
    }
  }'
```

现在批量请求端点应该被暴露为 `/batch-requests`，而不是 `/apisix/batch-requests`。
向暴露的批量请求端点发送一个包含 GET 和 POST 请求的流水线请求：

```shell
curl "http://127.0.0.1:9080/batch-requests" -X POST -d '
{
  "pipeline": [
    {
      "method": "GET",
      "path": "/anything"
    },
    {
      "method": "POST",
      "path": "/anything",
      "body": "a post request"
    }
  ]
}'
```

您应该会收到两个请求的响应，类似于以下内容：

```json
[
  {
    "reason": "OK",
    "body": "{\n  \"args\": {}, \n  \"data\": \"\", \n  \"files\": {}, \n  \"form\": {}, \n  \"headers\": {\n    \"Accept\": \"*/*\", \n    \"Host\": \"127.0.0.1\", \n    \"User-Agent\": \"curl/8.6.0\", \n    \"X-Amzn-Trace-Id\": \"Root=1-67b6e33b-5a30174f5534287928c54ca9\", \n    \"X-Forwarded-Host\": \"127.0.0.1\"\n  }, \n  \"json\": null, \n  \"method\": \"GET\", \n  \"origin\": \"192.168.107.1, 43.252.208.84\", \n  \"url\": \"http://127.0.0.1/anything\"\n}\n",
    "headers": {
      ...
    },
    "status": 200
  },
  {
    "reason": "OK",
    "body": "{\n  \"args\": {}, \n  \"data\": \"a post request\", \n  \"files\": {}, \n  \"form\": {}, \n  \"headers\": {\n    \"Accept\": \"*/*\", \n    \"Content-Length\": \"14\", \n    \"Host\": \"127.0.0.1\", \n    \"User-Agent\": \"curl/8.6.0\", \n    \"X-Amzn-Trace-Id\": \"Root=1-67b6e33b-0eddcec07f154dac0d77876f\", \n    \"X-Forwarded-Host\": \"127.0.0.1\"\n  }, \n  \"json\": null, \n  \"method\": \"POST\", \n  \"origin\": \"192.168.107.1, 43.252.208.84\", \n  \"url\": \"http://127.0.0.1/anything\"\n}\n",
    "headers": {
      ...
    },
    "status": 200
  }
]
```
