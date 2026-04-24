---
title: rocketmq-logger
keywords:
  - APISIX
  - API 网关
  - Plugin
  - RocketMQ
description: rocketmq-logger 插件将请求和响应日志以 JSON 对象批量推送到 RocketMQ 集群，支持自定义日志格式以增强数据管理能力。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/rocketmq-logger" />
</head>

## 描述

`rocketmq-logger` 插件将请求和响应日志以 JSON 对象批量推送到 RocketMQ 集群，并支持自定义日志格式。

## 属性

| 名称                   | 类型    | 必选项 | 默认值             | 有效值                | 描述                                                                                                                                                                                                                                                                                                            |
|------------------------|---------|--------|--------------------|-----------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| nameserver_list        | array[string]  | True   |                    |                       | RocketMQ nameserver 列表。                                                                                                                                                                                                                                                                                      |
| topic                  | string  | True   |                    |                       | 要推送数据的目标 topic。                                                                                                                                                                                                                                                                                         |
| key                    | string  | False  |                    |                       | 消息的 key。                                                                                                                                                                                                                                                                                                    |
| tag                    | string  | False  |                    |                       | 消息的 tag。                                                                                                                                                                                                                                                                                                    |
| log_format             | object  | False  |                    |                       | 以 JSON 键值对形式声明的自定义日志格式，值可以引用 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。也可以通过[插件元数据](../plugin-metadata.md)在全局范围内配置日志格式，将应用于所有 `rocketmq-logger` 插件实例。如果插件实例的日志格式与插件元数据的日志格式不同，插件实例的日志格式优先生效。 |
| timeout                | integer | False  | 3                  |                       | 向上游发送数据的超时时间。                                                                                                                                                                                                                                                                                      |
| use_tls                | boolean | False  | false              |                       | 若为 true，则启用 TLS 连接以加密传输。                                                                                                                                                                                                                                                                          |
| access_key             | string  | False  |                    |                       | ACL 的 Access key。设置为空字符串将禁用 ACL。                                                                                                                                                                                                                                                                   |
| secret_key             | string  | False  |                    |                       | ACL 的 Secret key。                                                                                                                                                                                                                                                                                             |
| name                   | string  | False  | `rocketmq logger`  |                       | 批处理器中插件的唯一标识符。若使用 Prometheus 监控 APISIX 指标，该名称将以 `apisix_batch_process_entries` 导出。                                                                                                                                                                                                |
| meta_format            | string  | False  | `default`          | `default` 或 `origin` | 收集请求信息的格式。设为 `default` 以 JSON 格式收集，设为 `origin` 以原始 HTTP 请求格式收集。                                                                                                                                                                                                                   |
| include_req_body       | boolean | False  | false              |                       | 若为 true，则在日志中包含请求体。注意：若请求体太大而无法保存在内存中，由于 NGINX 的限制，将无法记录。                                                                                                                                                                                                          |
| include_req_body_expr  | array   | False  |                    |                       | [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式数组。当 `include_req_body` 为 true 时使用，仅当此处表达式求值为 true 时才记录请求体。                                                                                                                                                           |
| include_resp_body      | boolean | False  | false              |                       | 若为 true，则在日志中包含响应体。                                                                                                                                                                                                                                                                               |
| include_resp_body_expr | array   | False  |                    |                       | [lua-resty-expr](https://github.com/api7/lua-resty-expr) 表达式数组。当 `include_resp_body` 为 true 时使用，仅当此处表达式求值为 true 时才记录响应体。                                                                                                                                                          |
| max_req_body_bytes     | integer | False  | 524288             | 大于等于 1            | 日志中记录的最大请求体字节数。超出该值的请求体将被截断。在 APISIX 3.16.0 版本中可用。                                                                                                                                                                                                                           |
| max_resp_body_bytes    | integer | False  | 524288             | 大于等于 1            | 日志中记录的最大响应体字节数。超出该值的响应体将被截断。在 APISIX 3.16.0 版本中可用。                                                                                                                                                                                                                           |
| batch_max_size         | integer | False  | 1000               | 大于 0                | 每批次允许的最大日志条目数。达到该值后，批次将被发送至日志服务。设置为 1 表示立即处理。                                                                                                                                                                                                                         |
| inactive_timeout       | integer | False  | 5                  | 大于 0                | 在将批次发送至日志服务前等待新日志的最长时间（秒）。该值应小于 `buffer_duration`。                                                                                                                                                                                                                              |
| buffer_duration        | integer | False  | 60                 | 大于 0                | 发送批次前允许最早条目存在的最长时间（秒）。                                                                                                                                                                                                                                                                    |
| retry_delay            | integer | False  | 1                  | 大于等于 0            | 批次发送失败后重试的时间间隔（秒）。                                                                                                                                                                                                                                                                            |
| max_retry_count        | integer | False  | 60                 | 大于等于 0            | 丢弃日志条目前允许的最大重试次数。                                                                                                                                                                                                                                                                              |

注意：schema 中还定义了 `encrypt_fields = {"secret_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考[加密存储字段](../plugin-develop.md#加密存储字段)。

## 插件元数据

也可以通过配置插件元数据来设置日志格式，可用配置如下：

| 名称                | 类型    | 必选项 | 描述                                                                                                                                               |
|---------------------|---------|--------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format          | object  | False  | 以 JSON 键值对形式声明的自定义日志格式，值可以引用 [NGINX 变量](https://nginx.org/en/docs/http/ngx_http_core_module.html)。                         |
| max_pending_entries | integer | False  | 批处理器中允许的最大未处理条目数。达到此限制后，新条目将被丢弃，直到积压减少。在 APISIX 3.15.0 版本中可用。                                         |

:::info IMPORTANT

插件元数据的配置为全局范围生效，将作用于所有使用 `rocketmq-logger` 插件的路由和服务。

:::

## 使用示例

以下示例演示如何在不同场景下配置 `rocketmq-logger` 插件。

请先启动一个示例 RocketMQ 集群：

```yaml title="docker-compose.yml"
version: "3"

services:
  rocketmq_namesrv:
    image: apacherocketmq/rocketmq:4.6.0
    container_name: rmqnamesrv
    restart: unless-stopped
    ports:
      - "9876:9876"
    command: sh mqnamesrv
    networks:
      rocketmq_net:

  rocketmq_broker:
    image: apacherocketmq/rocketmq:4.6.0
    container_name: rmqbroker
    restart: unless-stopped
    ports:
      - "10909:10909"
      - "10911:10911"
      - "10912:10912"
    depends_on:
      - rocketmq_namesrv
    command: sh mqbroker -n rmqnamesrv:9876 -c ../conf/broker.conf
    networks:
      rocketmq_net:

networks:
  rocketmq_net:
```

启动容器：

```shell
docker compose up -d
```

稍等片刻，nameserver 和 broker 应相继启动。

创建 `TopicTest` topic：

```shell
docker exec -i rmqnamesrv rm /home/rocketmq/rocketmq-4.6.0/conf/tools.yml
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rmqnamesrv:9876 -t TopicTest -c DefaultCluster
```

等待来自已配置 RocketMQ topic 的消息：

```shell
docker run -it --name rocketmq_consumer -e NAMESRV_ADDR=localhost:9876 --net host apacherocketmq/rocketmq:4.6.0 sh tools.sh org.apache.rocketmq.example.quickstart.Consumer
```

稍等片刻，消费者应启动并监听来自 APISIX 的消息：

```text
Consumer Started.
```

打开新的终端会话，继续以下操作。

:::note

您可以通过以下命令从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 以不同元日志格式记录日志

以下示例演示如何在路由上启用 `rocketmq-logger` 插件，记录客户端请求并推送日志到 RocketMQ，同时了解 `default` 和 `origin` 两种元日志格式的区别。

创建带 `rocketmq-logger` 的路由，将 `meta_format` 设为 `default`，将 `batch_max_size` 设为 1 以立即发送日志条目：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "rocketmq-logger-route",
    "uri": "/anything",
    "plugins": {
      "rocketmq-logger": {
        "nameserver_list": [ "127.0.0.1:9876" ],
        "topic": "TopicTest",
        "key": "key1",
        "timeout": 30,
        "meta_format": "default",
        "batch_max_size": 1
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

向路由发送请求以生成日志条目：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应看到类似如下的日志条目：

```json
{
  "client_ip": "127.0.0.1",
  "upstream": "34.197.122.172:80",
  "start_time": 1744727400000,
  "request": {
    "headers": {
      "host": "127.0.0.1:9080",
      "accept": "*/*",
      "user-agent": "curl/8.6.0"
    },
    "querystring": {},
    "size": 86,
    "uri": "/anything",
    "url": "http://127.0.0.1:9080/anything",
    "method": "GET"
  },
  "route_id": "rocketmq-logger-route",
  "apisix_latency": 8.9998455047607,
  "upstream_latency": 503,
  "latency": 511.99984550476,
  "response": {
    "size": 617,
    "headers": {
      "content-length": "391",
      "connection": "close",
      "date": "Tue, 15 Apr 2025 14:30:00 GMT",
      "server": "APISIX/3.15.0",
      "content-type": "application/json"
    },
    "status": 200
  },
  "server": {
    "hostname": "apisix",
    "version": "3.15.0"
  },
  "service_id": ""
}
```

将 `rocketmq-logger` 的元日志格式更新为 `origin`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes/rocketmq-logger-route" -X PATCH \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "rocketmq-logger": {
        "meta_format": "origin"
      }
    }
  }'
```

再次向路由发送请求以生成新的日志条目：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应看到以原始 HTTP 请求格式呈现的日志条目：

```text
GET /anything HTTP/1.1
host: 127.0.0.1:9080
user-agent: curl/8.6.0
accept: */*
```

### 通过插件元数据记录请求和响应头

以下示例演示如何使用[插件元数据](../plugin-metadata.md)和 NGINX 变量自定义日志格式，记录请求和响应中的特定头部信息。

在 APISIX 中，[插件元数据](../plugin-metadata.md)用于配置同一插件所有实例的公共元数据字段。当插件在多个资源上启用并需要统一更新元数据字段时非常有用。

注意：若希望通过插件元数据自定义日志格式，`meta_format` 必须设为 `default`。若 `meta_format` 设为 `origin`，日志条目将保持 `origin` 格式。

首先，创建带 `rocketmq-logger` 的路由，将 `meta_format` 设为 `default`，`batch_max_size` 设为 1 以立即发送日志条目：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "rocketmq-logger-route",
    "uri": "/anything",
    "plugins": {
      "rocketmq-logger": {
        "nameserver_list": [ "127.0.0.1:9876" ],
        "topic": "TopicTest",
        "key": "key1",
        "timeout": 30,
        "meta_format": "default",
        "batch_max_size": 1
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

接着，为 `rocketmq-logger` 配置插件元数据，记录自定义请求头 `env` 和响应头 `Content-Type`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/rocketmq-logger" -X PUT \
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

您应看到类似如下的日志条目：

```json
{
  "host": "127.0.0.1",
  "client_ip": "127.0.0.1",
  "resp_content_type": "application/json",
  "route_id": "rocketmq-logger-route",
  "env": "dev",
  "@timestamp": "2025-04-15T14:30:00+00:00"
}
```

### 按条件记录请求体

以下示例演示如何按条件记录请求体。

创建如下带 `rocketmq-logger` 的路由，仅当 URL 查询参数 `log_body` 为 `yes` 时才记录请求体：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "rocketmq-logger-route",
    "uri": "/anything",
    "plugins": {
      "rocketmq-logger": {
        "nameserver_list": [ "127.0.0.1:9876" ],
        "topic": "TopicTest",
        "key": "key1",
        "timeout": 30,
        "meta_format": "default",
        "batch_max_size": 1,
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
    "body": "{\"env\": \"dev\"}",
    "size": 183
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
  "rocketmq-logger": {
    "log_format": {"body": "$request_body"}
  }
}
```

:::
