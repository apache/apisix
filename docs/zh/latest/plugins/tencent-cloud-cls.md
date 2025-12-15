---
title: tencent-cloud-cls
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - CLS
  - 腾讯云
description: API 网关 Apache APISIX tencent-cloud-cls 插件可用于将日志推送到[腾讯云日志服务](https://cloud.tencent.com/document/product/614)。
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

`tencent-cloud-cls` 插件可用于将 APISIX 日志使用[腾讯云日志服务](https://cloud.tencent.com/document/product/614) API 推送到您的日志主题。

## 属性

| 名称              | 类型    | 必选项 | 默认值   | 有效值       | 描述                                                                           |
| ----------------- | ------- | ------ |-------| ------------ |------------------------------------------------------------------------------|
| cls_host          | string  | 是     |       |              | CLS API 域名，参考[使用 API 上传日志](https://cloud.tencent.com/document/api/614/16873)。|
| cls_topic         | string  | 是     |       |              | CLS 日志主题 id。                                                                 |
| secret_id         | string  | 是     |       |              | 云 API 密钥的 id。                                                                |
| secret_key        | string  | 是     |       |              | 云 API 密钥的 key。                                                               |
| sample_ratio      | number  | 否     | 1     | [0.00001, 1] | 采样的比例。设置为 `1` 时，将对所有请求进行采样。                                                  |
| include_req_body  | boolean | 否     | false | [false, true]| 当设置为 `true` 时，日志中将包含请求体。                                                     |
| include_req_body_expr | array | 否 |       |           | 当 `include_req_body` 属性设置为 `true` 时的过滤器。只有当此处设置的表达式求值为 `true` 时，才会记录请求体。有关更多信息，请参阅 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 。    |
| include_resp_body | boolean | 否     | false | [false, true]| 当设置为 `true` 时，日志中将包含响应体。                                                     |
| include_resp_body_expr | array | 否 |       |           | 当 `include_resp_body` 属性设置为 `true` 时进行过滤响应体，并且只有当此处设置的表达式计算结果为 `true` 时，才会记录响应体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |
| global_tag        | object  | 否     |       |              | kv 形式的 JSON 数据，可以写入每一条日志，便于在 CLS 中检索。                                        |
| log_format        | object  | 否   |          |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |

注意：schema 中还定义了 `encrypt_fields = {"secret_key"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

该插件支持使用批处理器来聚合并批量处理条目（日志/数据）。这样可以避免插件频繁地提交数据，默认情况下批处理器每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置)。

### 默认日志格式示例

```json
{
  "response": {
    "headers": {
      "content-type": "text/plain",
      "connection": "close",
      "server": "APISIX/3.7.0",
      "transfer-encoding": "chunked"
    },
    "size": 136,
    "status": 200
  },
  "route_id": "1",
  "upstream": "127.0.0.1:1982",
  "client_ip": "127.0.0.1",
  "apisix_latency": 100.99985313416,
  "service_id": "",
  "latency": 103.99985313416,
  "start_time": 1704525145772,
  "server": {
    "version": "3.7.0",
    "hostname": "localhost"
  },
  "upstream_latency": 3,
  "request": {
    "headers": {
      "connection": "close",
      "host": "localhost"
    },
    "url": "http://localhost:1984/opentracing",
    "querystring": {},
    "method": "GET",
    "size": 65,
    "uri": "/opentracing"
  }
}
```

## 插件元数据

| 名称             | 类型    | 必选项 | 默认值        | 有效值  | 描述                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| log_format       | object  | 否    |  |         | 日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过在前面加上 `$` 来引用 [APISIX 变量](../../../en/latest/apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| max_pending_entries | integer | 否 | | | 在批处理器中开始删除待处理条目之前可以购买的最大待处理条目数。|

:::info 重要

该设置全局生效。如果指定了 `log_format`，则所有绑定 `tencent-cloud-cls` 的路由或服务都将使用该日志格式。

:::

以下示例展示了如何通过 Admin API 配置插件元数据：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/tencent-cloud-cls \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr",
        "request": { "method": "$request_method", "uri": "$request_uri" },
        "response": { "status": "$status" }
    }
}'
```

配置完成后，你将在日志系统中看到如下类似日志：

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
        "tencent-cloud-cls": {
            "cls_host": "ap-guangzhou.cls.tencentyun.com",
            "cls_topic": "${your CLS topic name}",
            "global_tag": {
                "module": "cls-logger",
                "server_name": "YourApiGateWay"
            },
            "include_req_body": true,
            "include_resp_body": true,
            "secret_id": "${your secret id}",
            "secret_key": "${your secret key}"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "uri": "/hello"
}'
```

## 测试插件

现在你可以向 APISIX 发起请求：

```shell
curl -i http://127.0.0.1:9080/hello
```

```
HTTP/1.1 200 OK
...
hello, world
```

## 删除插件

当你需要删除该插件时，可通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

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
            "127.0.0.1:1980": 1
        }
    }
}'
```
