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
| ---------------- | ------- |-----| ------------------------------------------------ |
| path             | string  | 是   | 自定义输出文件路径。例如：`logs/file.log`。        |
| log_format       | object  | 否   | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| include_req_body   | boolean | 否   | 当设置为 `true` 时，日志中将包含请求体。如果请求体太大而无法在内存中保存，则由于 Nginx 的限制，无法记录请求体。|
| include_req_body_expr | array   | 否   | 当 `include_req_body` 属性设置为 `true` 时的过滤器。只有当此处设置的表达式求值为 `true` 时，才会记录请求体。有关更多信息，请参阅 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 。 |
| include_resp_body      | boolean | 否   | 当设置为 `true` 时，生成的文件包含响应体。                                                                                               |
| include_resp_body_expr | array   | 否   | 当 `include_resp_body` 属性设置为 `true` 时，使用该属性并基于 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 进行过滤。如果存在，则仅在表达式计算结果为 `true` 时记录响应。       |
| match        | array[array] | 否   |  当设置了这个选项后，只有匹配规则的日志才会被记录。`match` 是一个表达式列表，具体请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr#operator-list)。   |

### 默认日志格式示例

  ```json
  {
    "service_id": "",
    "apisix_latency": 100.99999809265,
    "start_time": 1703907485819,
    "latency": 101.99999809265,
    "upstream_latency": 1,
    "client_ip": "127.0.0.1",
    "route_id": "1",
    "server": {
        "version": "3.7.0",
        "hostname": "localhost"
    },
    "request": {
        "headers": {
            "host": "127.0.0.1:1984",
            "content-type": "application/x-www-form-urlencoded",
            "user-agent": "lua-resty-http/0.16.1 (Lua) ngx_lua/10025",
            "content-length": "12"
        },
        "method": "POST",
        "size": 194,
        "url": "http://127.0.0.1:1984/hello?log_body=no",
        "uri": "/hello?log_body=no",
        "querystring": {
            "log_body": "no"
        }
    },
    "response": {
        "headers": {
            "content-type": "text/plain",
            "connection": "close",
            "content-length": "12",
            "server": "APISIX/3.7.0"
        },
        "status": 200,
        "size": 123
    },
    "upstream": "127.0.0.1:1982"
 }
  ```

## 插件元数据设置

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| path             | string  | 否   |  |         | 当插件配置中未指定 `path` 时使用的日志文件路径。 |
| log_format       | object  | 可选   |  |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |

:::note 注意

该设置全局生效。如果指定了 `log_format`，则所有绑定 `file-logger` 的路由或服务都将使用该日志格式。

:::

以下示例展示了如何通过 Admin API 配置插件元数据：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/file-logger \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "path": "logs/metadata-file.log",
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr",
        "request": { "method": "$request_method", "uri": "$request_uri" },
        "response": { "status": "$status" }
    }
}'
```

配置完成后，你可以在日志系统中看到如下类似日志：

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
```

## 启用插件

你可以通过以下命令在指定路由中启用该插件：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
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

## 过滤日志

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
  "plugins": {
    "file-logger": {
      "path": "logs/file.log",
      "match": [
        [
          [ "arg_name","==","jack" ]
        ]
      ]
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

测试：

```shell
curl -i http://127.0.0.1:9080/hello?name=jack
```

在 `logs/file.log` 中可以看到日志记录

```shell
curl -i http://127.0.0.1:9080/hello?name=rose
```

在 `logs/file.log` 中看不到日志记录

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
            "127.0.0.1:9001": 1
        }
    }
}'
```
