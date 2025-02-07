---
title: public-api
keywords:
  - APISIX
  - API 网关
  - Public API
description: `public-api` 插件公开了一个内部 API 端点，使其可被公开访问。该插件的主要用途之一是公开由其他插件创建的内部端点。
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

| 名称  | 类型   | 必选项 | 默认值 | 描述 |
|------|--------|-------|-------|------|
| uri  | string | 否    | -     | 内部端点的 URI。如果未配置，则暴露路由的 URI。|

## 示例

### 在自定义端点暴露 Prometheus 指标

以下示例演示如何禁用默认在端口 `9091` 上暴露端点的 Prometheus 导出服务器，并在 APISIX 用于监听其他客户端请求的端口 `9080` 上，通过新的公共 API 端点暴露 APISIX 的 Prometheus 指标。

你还将配置路由，使内部端点 `/apisix/prometheus/metrics` 在自定义端点上暴露。

:::caution

如果收集了大量指标，插件可能会占用大量 CPU 资源进行指标计算，并对常规请求的处理产生负面影响。

为了解决这个问题，APISIX 使用 [特权代理](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/process.md#enable_privileged_agent) 机制，并将指标计算卸载至独立进程。如果使用配置文件中 `plugin_attr.prometheus.export_addr` 设定的指标端点，该优化将自动生效。但如果通过 `public-api` 插件暴露指标端点，则无法享受此优化。

:::

在配置文件中禁用 Prometheus 导出服务器，并重新加载 APISIX 以使更改生效：

```yaml
plugin_attr:
  prometheus:
    enable_export_server: false
```

接下来，创建一个带有 `public-api` 插件的路由，并为 APISIX 指标暴露一个公共 API 端点。你应将路由的 `uri` 设置为自定义端点路径，并将插件的 `uri` 设置为要暴露的内部端点。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/prometheus-metrics -X PUT \
  -H 'X-API-KEY: ${admin_key}' \
  -d '{
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
