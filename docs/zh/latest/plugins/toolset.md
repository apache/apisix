---
title: toolset
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - Toolset
  - toolset
  - trace
  - table-count
description: 本文介绍了关于 Apache APISIX `toolset` 插件的基本信息及使用方法。
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

`toolset` 插件是一个诊断与可观测性框架，用于托管多个轻量级子插件。每个子插件通过 `config.yaml` 中的 `plugin_attr.toolset` 进行配置，并在运行时动态加载或卸载，无需重启 APISIX。`toolset` 插件本身没有路由级别的 schema，始终在全局范围内运行。

### 子插件

| 子插件         | 描述                                                           |
|----------------|----------------------------------------------------------------|
| `trace`        | 对 APISIX 请求各阶段进行计时，并将耗时表格输出到错误日志中。 |
| `table_count`  | 定期统计并记录指定 Lua 模块表中的条目数量。                   |

## 属性

`toolset` 插件通过 `config.yaml` 中的 `plugin_attr` 进行配置，不支持路由级别的属性。

### trace

| 名称                  | 类型    | 必选 | 默认值 | 描述                                                                                                           |
|-----------------------|---------|------|--------|----------------------------------------------------------------------------------------------------------------|
| rate                  | integer | 否   | 1      | 采样率，N/100 的请求会被追踪。`1` 表示每 100 个请求追踪 1 个；设置为 `100` 则追踪所有请求。                 |
| hosts                 | array   | 否   | `[]`   | `Host` 请求头的白名单（支持 glob 模式）。为空表示所有 host 均通过。                                          |
| paths                 | array   | 否   | `[]`   | 请求 URI 的白名单（支持 glob 模式）。为空表示所有路径均通过。                                                |
| gen_uid               | boolean | 否   | false  | 为 `true` 时，当未找到标准追踪请求头（`x-request-id`、`traceparent` 等）时，自动生成 UUID 并添加到追踪输出。 |
| vars                  | array   | 否   | `[]`   | 要附加到追踪输出的额外 nginx 或 APISIX 变量名。                                                              |
| timespan_threshold    | number  | 否   | 0      | 仅记录总耗时超过该值（单位：秒）的请求追踪。`0` 表示记录所有追踪。                                          |

### table_count

| 名称         | 类型    | 必选 | 默认值                              | 描述                                                                          |
|--------------|---------|------|-------------------------------------|-------------------------------------------------------------------------------|
| lua_modules  | array   | 是   |                                     | 需要统计的 Lua 模块路径列表（例如 `["apisix.router"]`）。                     |
| interval     | integer | 否   | 5                                   | 两次统计之间的间隔时间（单位：秒）。                                          |
| depth        | integer | 否   | 10                                  | 递归统计表条目时的最大深度。`0` 表示禁用递归统计。                            |
| scopes       | array   | 否   | `["worker", "privileged agent"]`    | 子插件运行的 APISIX 进程类型。                                                |

## 启用插件

在 `config.yaml` 的 `plugins` 列表中添加 `toolset`，并在 `plugin_attr.toolset` 下配置子插件：

```yaml
plugins:
  - toolset

plugin_attr:
  toolset:
    trace:
      rate: 10
      hosts:
        - "*.example.com"
      paths:
        - "/api/*"
      gen_uid: true
      vars:
        - remote_addr
      timespan_threshold: 0.5
    table_count:
      lua_modules:
        - apisix.router
      interval: 10
      depth: 5
      scopes:
        - worker
```

## 使用示例

### 追踪慢请求

以下配置对发往 `*.example.com` 且总处理时间超过 500ms 的请求进行最多 10% 的采样追踪：

```yaml
plugin_attr:
  toolset:
    trace:
      rate: 10
      hosts:
        - "*.example.com"
      timespan_threshold: 0.5
```

当请求满足条件时，APISIX 会以 `WARN` 级别将类似如下的耗时表格写入错误日志：

```
+----------+---------------------------+----------+-------------------------+
| Role     | Phase                     | Timespan | Start time              |
+----------+---------------------------+----------+-------------------------+
| APISIX   | access                    | 3ms      | 2024-01-01 12:00:00.123 |
| APISIX   | \_match_route             | 1ms      | 2024-01-01 12:00:00.124 |
| APISIX   | balancer                  | 1ms      | 2024-01-01 12:00:00.125 |
| Upstream | upstream (req + response) | 520ms    | 2024-01-01 12:00:00.126 |
| APISIX   | header_filter             | 0ms      | 2024-01-01 12:00:00.646 |
| APISIX   | body_filter               | 0ms      | 2024-01-01 12:00:00.646 |
| Client   | response                  | 1ms      | 2024-01-01 12:00:00.647 |
| APISIX   | log                       | 0ms      | 2024-01-01 12:00:00.648 |
+----------+---------------------------+----------+-------------------------+
```

### 监控路由表增长

以下配置每 30 秒统计一次 `apisix.router` Lua 模块的条目数，仅在 worker 进程中运行：

```yaml
plugin_attr:
  toolset:
    table_count:
      lua_modules:
        - apisix.router
      interval: 30
      depth: 5
      scopes:
        - worker
```

统计结果以 `WARN` 级别写入错误日志：

```
package apisix.router table count is: 1234 for loaded: 1
```

## 禁用插件

从 `config.yaml` 的 `plugins` 列表中移除 `toolset` 并重新加载 APISIX：

```yaml
plugins:
  # - toolset   # 移除或注释掉此行
```
