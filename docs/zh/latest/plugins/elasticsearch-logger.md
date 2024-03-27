---
title: elasticsearch-logger
keywords:
  - APISIX
  - API 网关
  - 插件
  - Elasticsearch-logger
  - 日志
description: 本文介绍了 API 网关 Apache APISIX 的 elasticsearch-logger 插件。使用该插件可以将 APISIX 的日志数据推送到 Elasticserach。
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

`elasticsearch-logger` 插件用于将 `Apache APISIX` 的请求日志转发到 `Elasticsearch` 中进行分析和存储。

启用该插件后 APISIX 将在 `Log Phase` 获取请求上下文信息并序列化为 [Bulk 格式](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html#docs-bulk) 后提交到批处理队列中，当触发批处理队列每批次最大处理容量或刷新缓冲区的最大时间时会将队列中的数据提交到 Elaticsearch 中。更多信息，请参考 [Batch-Processor](../batch-processor.md)。

## 属性

| 名称          | 类型    | 必选项 | 默认值               | 描述                                                         |
| ------------- | ------- | -------- | -------------------- | ------------------------------------------------------------ |
| endpoint_addr | string  | 废弃       |                      | Elasticsearch API 推荐使用 `endpoint_addrs`                                           |
| endpoint_addrs | array  | 是       |                      | Elasticsearch API。如果配置多个 `endpoints`，日志将会随机写入到各个 `endpoints`                                           |
| field         | array   | 是       |                      | Elasticsearch `field`配置信息。                                |
| field.index   | string  | 是       |                      | Elasticsearch [_index field](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-index-field.html#mapping-index-field) |
| field.type    | string  | 否       | Elasticsearch 默认值 | Elasticsearch [_type field](https://www.elastic.co/guide/en/elasticsearch/reference/7.17/mapping-type-field.html#mapping-type-field) |
| log_format    | object  | 否   |          | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../apisix-variable.md) 或 [NGINX 内置变量](http://nginx.org/en/docs/varindex.html)。 |
| auth          | array   | 否       |                      | Elasticsearch [authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) 配置信息 |
| auth.username | string  | 是       |                      | Elasticsearch [authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) 用户名。 |
| auth.password | string  | 是       |                      | Elasticsearch [authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) 密码。 |
| ssl_verify    | boolean | 否       | true                 | 当设置为 `true` 时则启用 SSL 验证。更多信息请参考 [lua-nginx-module](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake)。 |
| timeout       | integer | 否       | 10                   | 发送给 Elasticsearch 请求超时时间。                            |
| include_req_body        | boolean       | 否   | false | 当设置为 `true` 时，包含请求体。**注意**：如果请求体无法完全存放在内存中，由于 NGINX 的限制，APISIX 无法将它记录下来。               |
| include_req_body_expr   | array         | 否   |       | 当 `include_req_body` 属性设置为 `true` 时的过滤器。只有当此处设置的表达式求值为 `true` 时，才会记录请求体。有关更多信息，请参阅 [lua-resty-expr](https://github.com/api7/lua-resty-expr) 。 |
| include_resp_body       | boolean       | 否   | false | 当设置为 `true` 时，包含响应体。                                            |
| include_resp_body_expr  | array         | 否   |       | 当 `include_resp_body` 属性设置为 `true` 时进行过滤响应体，并且只有当此处设置的表达式计算结果为 `true` 时，才会记录响应体。更多信息，请参考 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。 |

注意：schema 中还定义了 `encrypt_fields = {"auth.password"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

本插件支持使用批处理器来聚合并批量处理条目（日志和数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

### 默认日志格式示例

```json
{
    "upstream_latency": 2,
    "apisix_latency": 100.9999256134,
    "request": {
        "size": 59,
        "url": "http://localhost:1984/hello",
        "method": "GET",
        "querystring": {},
        "headers": {
            "host": "localhost",
            "connection": "close"
        },
        "uri": "/hello"
    },
    "server": {
        "version": "3.7.0",
        "hostname": "localhost"
    },
    "client_ip": "127.0.0.1",
    "upstream": "127.0.0.1:1980",
    "response": {
        "status": 200,
        "headers": {
            "content-length": "12",
            "connection": "close",
            "content-type": "text/plain",
            "server": "APISIX/3.7.0"
        },
        "size": 118
    },
    "start_time": 1704524807607,
    "route_id": "1",
    "service_id": "",
    "latency": 102.9999256134
}
```

## 启用插件

你可以通过如下命令在指定路由上启用 `elasticsearch-logger` 插件：

### 完整配置示例

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins":{
        "elasticsearch-logger":{
            "endpoint_addr":"http://127.0.0.1:9200",
            "field":{
                "index":"services",
                "type":"collector"
            },
            "auth":{
                "username":"elastic",
                "password":"123456"
            },
            "ssl_verify":false,
            "timeout": 60,
            "retry_delay":1,
            "buffer_duration":60,
            "max_retry_count":0,
            "batch_max_size":1000,
            "inactive_timeout":5,
            "name":"elasticsearch-logger"
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    },
    "uri":"/elasticsearch.do"
}'
```

### 最小化配置示例

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins":{
        "elasticsearch-logger":{
            "endpoint_addr":"http://127.0.0.1:9200",
            "field":{
                "index":"services"
            }
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    },
    "uri":"/elasticsearch.do"
}'
```

## 测试插件

向配置 `elasticsearch-logger` 插件的路由发送请求

```shell
curl -i http://127.0.0.1:9080/elasticsearch.do\?q\=hello
HTTP/1.1 200 OK
...
hello, world
```

现在，你可以从 Elasticsearch 获取相关日志。

```shell
curl -X GET "http://127.0.0.1:9200/services/_search" | jq .
{
  "took": 0,
   ...
    "hits": [
      {
        "_index": "services",
        "_type": "_doc",
        "_id": "M1qAxYIBRmRqWkmH4Wya",
        "_score": 1,
        "_source": {
          "apisix_latency": 0,
          "route_id": "1",
          "server": {
            "version": "2.15.0",
            "hostname": "apisix"
          },
          "request": {
            "size": 102,
            "uri": "/elasticsearch.do?q=hello",
            "querystring": {
              "q": "hello"
            },
            "headers": {
              "user-agent": "curl/7.29.0",
              "host": "127.0.0.1:9080",
              "accept": "*/*"
            },
            "url": "http://127.0.0.1:9080/elasticsearch.do?q=hello",
            "method": "GET"
          },
          "service_id": "",
          "latency": 0,
          "upstream": "127.0.0.1:1980",
          "upstream_latency": 1,
          "client_ip": "127.0.0.1",
          "start_time": 1661170929107,
          "response": {
            "size": 192,
            "headers": {
              "date": "Mon, 22 Aug 2022 12:22:09 GMT",
              "server": "APISIX/2.15.0",
              "content-type": "text/plain; charset=utf-8",
              "connection": "close",
              "transfer-encoding": "chunked"
            },
            "status": 200
          }
        }
      }
    ]
  }
}
```

## 插件元数据设置

| 名称       | 类型   | 必选项 | 默认值                                                       | 有效值 | 描述                                                         |
| ---------- | ------ | ------ | ------------------------------------------------------------ | ------ | ------------------------------------------------------------ |
| log_format | object | 可选   |  |        | 以 JSON 格式的键值对来声明日志格式。对于值部分，仅支持字符串。如果是以 `$` 开头，则表明是要获取 [APISIX 变量](../apisix-variable.md) 或 [Nginx 内置变量](http://nginx.org/en/docs/varindex.html)。请注意，**该设置是全局生效的**，因此在指定 log_format 后，将对所有绑定 elasticsearch-logger 的 Route 或 Service 生效。 |

### 设置日志格式示例

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/elasticsearch-logger \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

在日志收集处，将得到类似下面的日志：

```json
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

向配置 `elasticsearch-logger` 插件的路由发送请求

```shell
curl -i http://127.0.0.1:9080/elasticsearch.do\?q\=hello
HTTP/1.1 200 OK
...
hello, world
```

现在，你可以从 Elasticsearch 获取相关日志。

```shell
curl -X GET "http://127.0.0.1:9200/services/_search" | jq .
{
  "took": 0,
  ...
  "hits": {
    "total": {
      "value": 1,
      "relation": "eq"
    },
    "max_score": 1,
    "hits": [
      {
        "_index": "services",
        "_type": "_doc",
        "_id": "NVqExYIBRmRqWkmH4WwG",
        "_score": 1,
        "_source": {
          "@timestamp": "2022-08-22T20:26:31+08:00",
          "client_ip": "127.0.0.1",
          "host": "127.0.0.1",
          "route_id": "1"
        }
      }
    ]
  }
}
```

### 删除插件元数据

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/elasticsearch-logger \
-H "X-API-KEY: $admin_key" -X DELETE
```

## 删除插件

当你需要删除该插件时，可以通过如下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins":{},
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    },
    "uri":"/elasticsearch.do"
}'
```
