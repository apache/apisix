---
title: file-logger
keywords:
  - APISIX
  - API 网关
  - Plugin
  - file-logger
description: API 网关 Apache APISIX file-logger 插件可用于将日志数据存储到指定位置。
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

`file-logger` 插件可用于将日志数据存储到指定位置。

:::tip 提示

`file-logger` 插件特点如下：

- 可将指定路由的日志发送到指定位置，方便你在本地统计各个路由的请求和响应数据。在使用 [debug mode](../../../en/latest/debug-mode.md) 时，你可以很轻松地将出现问题的路由的日志输出到指定文件中，从而更方便地排查问题。
- 可以获取 [APISIX 变量](../../../en/latest/apisix-variable.md)和 [NGINX 变量](http://nginx.org/en/docs/varindex.html)，而 `access.log` 仅能使用 NGINX 变量。
- 支持热加载，你可以在路由中随时更改其配置并立即生效。而修改 `access.log` 相关配置，则需要重新加载 APISIX。
- 支持以 JSON 格式保存日志数据。
- 可以在 `log phase` 阶段修改 `file-logger` 执行的函数来收集你所需要的信息。

:::

## 属性

| 名称             | 类型     | 必选项 | 描述                                             |
| ---------------- | ------- | ------ | ------------------------------------------------ |
| path             | string  | 是     | 自定义输出文件路径。例如：`logs/file.log`。        |
| log_format       | object  | 否     | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| include_resp_body      | boolean | 否     | 当设置为 `true` 时，生成的文件包含响应体。                                                                                               |
| include_resp_body_expr | array   | 否     | 当 `include_resp_body` 属性设置为 `true` 时，使用该属性并基于 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 进行过滤。如果存在，则仅在表达式计算结果为 `true` 时记录响应。       |

## 插件元数据设置

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 可选   | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |

:::note 注意

该设置全局生效。如果指定了 `log_format`，则所有绑定 `file-logger` 的路由或服务都将使用该日志格式。

:::

以下示例展示了如何通过 Admin API 配置插件元数据：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/file-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

配置完成后，你可以在日志系统中看到如下类似日志：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "plugins": {
    "file-logger": {
      "path": "logs/file.log"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:9001": 1
    }
  },
  "uri": "/hello"
}'
```

## 测试插件

你可以通过以下命令向 APISIX 发出请求：

```shell
curl -i http://127.0.0.1:9080/hello
```

```
HTTP/1.1 200 OK
...
hello, world
```

访问成功后，你可以在对应的 `logs` 目录下找到 `file.log` 文件。

## 禁用插件

当你需要禁用该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
            "127.0.0.1:9001": 1
        }
    }
}'
```
