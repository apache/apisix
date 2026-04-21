---
title: http-logger
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - HTTP Logger
  - 日志
description: http-logger 插件将请求和响应日志以 JSON 对象批量推送到 HTTP(S) 服务器，支持自定义日志格式以增强数据管理能力。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/http-logger" />
</head>

## 描述

`http-logger` 插件将请求和响应日志以 JSON 对象批量推送到 HTTP(S) 服务器，并支持自定义日志格式。

## 属性

| 名称                   | 类型    | 必选项 | 默认值  | 有效值               | 描述                                                                                                                                                                                                                                                                                   |
|------------------------|---------|--------|---------|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| uri                    | string  | True   |         |                      | HTTP(S) 服务器的 URI。                                                                                                                                                                                                                                                                 |
| auth_header            | string  | False  |         |                      | HTTP(S) 服务器所需的授权请求头。                                                                                                                                                                                                                                                       |
| timeout                | integer | False  | 3       | 大于 0               | 发送请求后保持连接的存活时间。                                                                                                                                                                                                                                                         |
| log_format             | object  | False  |         |                      | 以 JSON 键值对形式声明的自定义日志格式，值可以引用 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。也可以通过[插件元数据](../plugin-metadata.md)在全局范围内配置日志格式，该配置将应用于所有 `http-logger` 插件实例。如果插件实例上的日志格式与插件元数据上的日志格式不同，插件实例的日志格式优先生效。 |
| include_req_body       | boolean | False  | false   |                      | 若为 true，则在日志中包含请求体。注意：若请求体太大而无法保存在内存中，由于 NGINX 的限制，将无法记录。                                                                                                                                                                                 |
| include_req_body_expr  | array   | False  |         |                      | [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式数组。当 `include_req_body` 为 true 时使用，仅当此处表达式求值为 true 时才记录请求体。                                                                                                                                  |
| include_resp_body      | boolean | False  | false   |                      | 若为 true，则在日志中包含响应体。                                                                                                                                                                                                                                                      |
| include_resp_body_expr | array   | False  |         |                      | [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式数组。当 `include_resp_body` 为 true 时使用，仅当此处表达式求值为 true 时才记录响应体。                                                                                                                                 |
| max_req_body_bytes     | integer | False  | 524288  | 大于等于 1           | 日志中记录的最大请求体字节数。超出该值的请求体将被截断。                                                                                                                                                                                                                               |
| max_resp_body_bytes    | integer | False  | 524288  | 大于等于 1           | 日志中记录的最大响应体字节数。超出该值的响应体将被截断。                                                                                                                                                                                                                               |
| concat_method          | string  | False  | `json`  | `json` 或 `new_line` | 日志的拼接方式。设为 `json` 时对所有待发日志使用 `json.encode`；设为 `new_line` 时也使用 `json.encode`，但用换行符 `\n` 拼接各行。                                                                                                                                                     |
| ssl_verify             | boolean | False  | false   |                      | 若为 true，则验证服务器的 SSL 证书。                                                                                                                                                                                                                                                   |

:::note

该插件支持使用批处理器来聚合并批量处理条目（日志/数据），避免频繁提交数据。默认情况下，批处理器每 `5` 秒或队列数据达到 `1000` 条时提交数据。详情请参考[批处理器](../batch-processor.md#configuration)。

:::

## 插件元数据

也可以通过配置插件元数据来设置日志格式，可用配置如下：

| 名称                | 类型    | 必选项 | 描述                                                                                                                                               |
|---------------------|---------|--------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format          | object  | False  | 以 JSON 键值对形式声明的自定义日志格式，值可以引用 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。                         |
| max_pending_entries | integer | False  | 批处理器中允许的最大未处理条目数。达到此限制后，新条目将被丢弃，直到积压减少。在 APISIX 3.15.0 版本中可用。                                         |

:::info IMPORTANT

插件元数据的配置为全局范围生效，将作用于所有使用 `http-logger` 插件的路由和服务。

:::

## 使用示例

以下示例演示如何在不同场景下配置 `http-logger` 插件。

请先使用 [mockbin](https://mockbin.io) 启动一个模拟 HTTP 日志端点，并记录 mockbin URL。

:::note

您可以通过以下命令从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 以默认日志格式记录请求

以下示例演示如何在路由上配置 `http-logger` 插件，记录访问该路由的请求信息。

创建一条路由并配置 `http-logger` 插件，指定服务器 URI：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "http-logger-route",
    "uri": "/anything",
    "plugins": {
      "http-logger": {
        "uri": "https://669f05eb10ca49f18763e023312c3d77.api.mockbin.io/"
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
curl "http://127.0.0.1:9080/anything"
```

您应收到 `HTTP/1.1 200 OK` 响应。在 mockbin 中，您应看到类似如下的日志条目：

```json
[
  {
    "upstream": "3.213.1.197:80",
    "server": {
      "hostname": "7d8d831179d4",
      "version": "3.9.0"
    },
    "start_time": 1718291190508,
    "client_ip": "192.168.65.1",
    "response": {
      "status": 200,
      "headers": {
        "server": "APISIX/3.9.0",
        "content-length": "390",
        "access-control-allow-credentials": "true",
        "connection": "close",
        "date": "Thu, 13 Jun 2024 15:06:31 GMT",
        "access-control-allow-origin": "*",
        "content-type": "application/json"
      },
      "size": 617
    },
    "latency": 1200.0000476837,
    "upstream_latency": 1133,
    "apisix_latency": 67.000047683716,
    "request": {
      "url": "http://127.0.0.1:9080/anything",
      "querystring": {},
      "method": "GET",
      "uri": "/anything",
      "headers": {
        "accept": "*/*",
        "user-agent": "curl/8.6.0",
        "host": "127.0.0.1:9080"
      },
      "size": 85
    },
    "service_id": "",
    "route_id": "http-logger-route"
  }
]
```

### 通过插件元数据记录请求和响应头

以下示例演示如何使用[插件元数据](../plugin-metadata.md)和 NGINX 变量自定义日志格式，记录请求和响应中的特定头部信息。

在 APISIX 中，[插件元数据](../plugin-metadata.md)用于配置同一插件所有实例的公共元数据字段。当插件在多个资源上启用并需要统一更新元数据字段时，插件元数据非常有用。

首先，创建一条带有 `http-logger` 插件的路由：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "http-logger-route",
    "uri": "/anything",
    "plugins": {
      "http-logger": {
        "uri": "https://669f05eb10ca49f18763e023312c3d77.api.mockbin.io/"
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

接着，为 `http-logger` 配置插件元数据，记录自定义请求头 `env` 和响应头 `Content-Type`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/http-logger" -X PUT \
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
curl "http://127.0.0.1:9080/anything" -H "env: dev"
```

您应收到 `HTTP/1.1 200 OK` 响应。在 mockbin 中，您应看到类似如下的日志条目：

```json
[
  {
    "route_id": "http-logger-route",
    "client_ip": "192.168.65.1",
    "@timestamp": "2024-06-13T15:19:34+00:00",
    "host": "127.0.0.1",
    "env": "dev",
    "resp_content_type": "application/json"
  }
]
```

### 按条件记录请求体

以下示例演示如何按条件记录请求体。

创建如下带有 `http-logger` 插件的路由，仅当 URL 查询参数 `log_body` 为 `yes` 时才记录请求体：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "http-logger-route",
    "uri": "/anything",
    "plugins": {
      "http-logger": {
        "uri": "https://669f05eb10ca49f18763e023312c3d77.api.mockbin.io/",
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

您应能看到日志中包含请求体：

```json
[
  {
    "request": {
      "url": "http://127.0.0.1:9080/anything?log_body=yes",
      "querystring": {
        "log_body": "yes"
      },
      "uri": "/anything?log_body=yes",
      "body": "{\"env\": \"dev\"}"
    }
  }
]
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
  "http-logger": {
    "log_format": {"body": "$request_body"}
  }
}
```

:::
