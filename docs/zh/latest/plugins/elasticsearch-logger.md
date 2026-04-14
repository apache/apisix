---
title: elasticsearch-logger
keywords:
  - APISIX
  - API 网关
  - 插件
  - Elasticsearch-logger
  - 日志
description: elasticsearch-logger Plugin 将请求和响应日志批量推送到 Elasticsearch，并支持日志格式的自定义。
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
  <link rel="canonical" href="https://docs.api7.ai/hub/elasticsearch-logger" />
</head>

## 描述

`elasticsearch-logger` 插件将请求和响应日志批量推送到 [Elasticsearch](https://www.elastic.co)，并支持自定义日志格式。启用后，插件会将请求上下文信息序列化为 [Elasticsearch Bulk 格式](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html#docs-bulk) 并将其添加到队列中，然后再推送到 Elasticsearch。有关更多详细信息，请参阅 [批处理器](../batch-processor.md)。

## 属性

| 名称          | 类型    | 必选项 | 默认值               | 描述                                                         |
| ------------- | ------- | -------- | -------------------- | ------------------------------------------------------------ |
| endup_addrs | array[string] | 是 | | Elasticsearch API 端点地址。如果配置了多个端点，则会随机写入。 |
| field | object | 是 | | Elasticsearch `field` 配置。 |
| field.index | string | 是 | | Elasticsearch [_index 字段](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-index-field.html#mapping-index-field)。 |
| log_format | object | 否 | | 自定义日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过 `$` 前缀引用 [APISIX](../apisix-variable.md) 或 [NGINX 变量](http://nginx.org/en/docs/varindex.html)。 |
| auth | array | 否 | | Elasticsearch [身份验证](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) 配置。 |
| auth.username | string | 是 | | Elasticsearch [身份验证](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) 用户名​​。 |
| auth.password | string | 是 | | Elasticsearch [身份验证](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) 密码。 |
| headers | object | 否 | | 自定义请求标头，以键值对形式配置。例如 `{"Authorization": "Bearer token", "X-API-Key": "key"}`。 |
| ssl_verify | boolean | 否 | true | 如果为 true，则执行 SSL 验证。 |
| timeout | integer | 否 | 10 | Elasticsearch 发送数据超时（秒）。 |
| include_req_body | boolean | 否 | false |如果为 true，则将请求主体包含在日志中。请注意，如果请求主体太大而无法保存在内存中，则由于 NGINX 的限制而无法记录。|
| include_req_body_expr | array[array] | 否 | | 一个或多个条件的数组，形式为 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。在 `include_req_body` 为 true 时使用。仅当此处配置的表达式计算结果为 true 时，才会记录请求主体。|
| include_resp_body | boolean | 否 | false | 如果为 true，则将响应主体包含在日志中。|
| include_resp_body_expr | array[array] | 否 | | 一个或多个条件的数组，形式为 [lua-resty-expr](https://github.com/api7/lua-resty-expr)。在 `include_resp_body` 为 true 时使用。仅当此处配置的表达式计算结果为 true 时，才会记录响应主体。|

注意：schema 中还定义了 `encrypt_fields = {"auth.password"}`，这意味着该字段将会被加密存储在 etcd 中。具体参考 [加密存储字段](../plugin-develop.md#加密存储字段)。

本插件支持使用批处理器来聚合并批量处理条目（日志和数据）。这样可以避免插件频繁地提交数据，默认设置情况下批处理器会每 `5` 秒钟或队列中的数据达到 `1000` 条时提交数据，如需了解或自定义批处理器相关参数设置，请参考 [Batch-Processor](../batch-processor.md#配置) 配置部分。

## Plugin Metadata

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| log_format | object | 否 |  | 自定义日志格式以 JSON 的键值对声明。值支持字符串和嵌套对象（最多五层，超出部分将被截断）。字符串中可通过 `$` 前缀引用 [APISIX 变量](../apisix-variable.md) 和 [NGINX 变量](http://nginx.org/en/docs/varindex.html)。 |
| max_pending_entries | integer | 否 | | | 在批处理器中开始删除待处理条目之前可以购买的最大待处理条目数。|

## 示例

以下示例演示了如何为不同场景配置 `elasticsearch-logger` 插件。

要遵循示例，请在 Docker 中启动 Elasticsearch 实例：

```shell
docker run -d \
  --name elasticsearch \
  --network apisix-quickstart-net \
  -v elasticsearch_vol:/usr/share/elasticsearch/data/ \
  -p 9200:9200 \
  -p 9300:9300 \
  -e ES_JAVA_OPTS="-Xms512m -Xmx512m" \
  -e discovery.type=single-node \
  -e xpack.security.enabled=false \
  docker.elastic.co/elasticsearch/elasticsearch:7.17.1
```

在 Docker 中启动 Kibana 实例，以可视化 Elasticsearch 中的索引数据：

```shell
docker run -d \
  --name kibana \
  --network apisix-quickstart-net \
  -p 5601:5601 \
  -e ELASTICSEARCH_HOSTS="http://elasticsearch:9200" \
  docker.elastic.co/kibana/kibana:7.17.1
```

如果成功，您应该在 [localhost:5601](http://localhost:5601) 上看到 Kibana 仪表板。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### 以默认日志格式记录

以下示例演示如何在路由上启用 `elasticsearch-logger` 插件，该插件记录客户端对路由的请求和响应，并将日志推送到 Elasticsearch。

使用 `elasticsearch-logger` 创建路由，将 `index` 字段配置为 `gateway`：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "elasticsearch-logger-route",
    "uri": "/anything",
    "plugins": {
      "elasticsearch-logger": {
        "endpoint_addrs": ["http://elasticsearch:9200"],
        "field": {
          "index": "gateway"
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

向路由发送请求以生成日志条目：

```shell
curl -i "http://127.0.0.1:9080/anything"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

导航到 [localhost:5601](http://localhost:5601) 上的 Kibana 仪表板，并在 __Discover__ 选项卡下创建一个新的索引模式 `gateway` 以从 Elasticsearch 获取数据。配置完成后，导航回 __Discover__ 选项卡，您应该会看到生成的日志，类似于以下内容：

```json
{
  "_index": "gateway",
  "_id": "CE-JL5QBOkdYRG7kEjTJ",
  "_version": 1,
  "_score": 1,
  "_source": {
    "request": {
      "headers": {
        "host": "127.0.0.1:9080",
        "accept": "*/*",
        "user-agent": "curl/8.6.0"
      },
      "size": 85,
      "querystring": {},
      "method": "GET",
      "url": "http://127.0.0.1:9080/anything",
      "uri": "/anything"
    },
    "response": {
      "headers": {
        "content-type": "application/json",
        "access-control-allow-credentials": "true",
        "server": "APISIX/3.11.0",
        "content-length": "390",
        "access-control-allow-origin": "*",
        "connection": "close",
        "date": "Mon, 13 Jan 2025 10:18:14 GMT"
      },
      "status": 200,
      "size": 618
    },
    "route_id": "elasticsearch-logger-route",
    "latency": 585.00003814697,
    "apisix_latency": 18.000038146973,
    "upstream_latency": 567,
    "upstream": "50.19.58.113:80",
    "server": {
      "hostname": "0b9a772e68f8",
      "version": "3.11.0"
    },
    "service_id": "",
    "client_ip": "192.168.65.1"
  },
  "fields": {
    ...
  }
}
```

### 使用 Plugin Metadata 记录请求和响应标头

以下示例演示了如何使用 [Plugin Metadata](../terminology/plugin-metadata.md) 和 [NGINX 变量](http://nginx.org/en/docs/varindex.html) 自定义日志格式，以记录请求和响应中的特定标头。

在 APISIX 中，[Plugin Metadata](../terminology/plugin-metadata.md) 用于配置同一插件的所有插件实例的通用元数据字段。当插件在多个资源中启用并需要对其元数据字段进行通用更新时，它很有用。

首先，使用 `elasticsearch-logger` 创建路由，如下所示：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "elasticsearch-logger-route",
    "uri": "/anything",
    "plugins": {
      "elasticsearch-logger": {
        "endpoint_addrs": ["http://elasticsearch:9200"],
        "field": {
          "index": "gateway"
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

接下来，配置 `elasticsearch-logger` 的 Plugin Metadata：

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/elasticsearch-logger" -X PUT \
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

使用 `env` 标头向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -H "env: dev"
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

导航到 [localhost:5601](http://localhost:5601) 上的 Kibana 仪表板，并在 __Discover__ 选项卡下创建一个新的索引模式 `gateway` 以从 Elasticsearch 获取数据（如果您尚未这样做）。配置完成后，导航回 __Discover__ 选项卡，您应该会看到生成的日志，类似于以下内容：

```json
{
  "_index": "gateway",
  "_id": "Ck-WL5QBOkdYRG7kODS0",
  "_version": 1,
  "_score": 1,
  "_source": {
    "client_ip": "192.168.65.1",
    "route_id": "elasticsearch-logger-route",
    "@timestamp": "2025-01-06T10:32:36+00:00",
    "host": "127.0.0.1",
    "resp_content_type": "application/json"
  },
  "fields": {
    ...
  }
}
```

### 有条件地记录请求主体

以下示例演示了如何有条件地记录请求主体。

使用 `elasticsearch-logger` 创建路由，仅在 URL 查询字符串 `log_body` 为 `true` 时记录请求主体：

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "plugins": {
      "elasticsearch-logger": {
        "endpoint_addrs": ["http://elasticsearch:9200"],
        "field": {
          "index": "gateway"
        },
        "include_req_body": true,
        "include_req_body_expr": [["arg_log_body", "==", "yes"]]
      }
    },
    "upstream": {
      "nodes": {
        "httpbin.org:80": 1
      },
      "type": "roundrobin"
    },
  "uri": "/anything",
  "id": "elasticsearch-logger-route"
}'
```

使用满足以下条件的 URL 查询字符串向路由发送请求：

```shell
curl -i "http://127.0.0.1:9080/anything?log_body=yes" -X POST -d '{"env": "dev"}'
```

您应该会收到 `HTTP/1.1 200 OK` 响应。

导航到 [localhost:5601](http://localhost:5601) 上的 Kibana 仪表板，并在 __Discover__ 选项卡下创建一个新的索引模式 `gateway` 以从 Elasticsearch 获取数据（如果您尚未这样做）。配置完成后，导航回 __Discover__ 选项卡，您应该会看到生成的日志，类似于以下内容：

```json
{
  "_index": "gateway",
  "_id": "Dk-cL5QBOkdYRG7k7DSW",
  "_version": 1,
  "_score": 1,
  "_source": {
    "request": {
      "headers": {
        "user-agent": "curl/8.6.0",
        "accept": "*/*",
        "content-length": "14",
        "host": "127.0.0.1:9080",
        "content-type": "application/x-www-form-urlencoded"
      },
      "size": 182,
      "querystring": {
        "log_body": "yes"
      },
      "body": "{\"env\": \"dev\"}",
      "method": "POST",
      "url": "http://127.0.0.1:9080/anything?log_body=yes",
      "uri": "/anything?log_body=yes"
    },
    "start_time": 1735965595203,
    "response": {
      "headers": {
        "content-type": "application/json",
        "server": "APISIX/3.11.0",
        "access-control-allow-credentials": "true",
        "content-length": "548",
        "access-control-allow-origin": "*",
        "connection": "close",
        "date": "Mon, 13 Jan 2025 11:02:32 GMT"
      },
      "status": 200,
      "size": 776
    },
    "route_id": "elasticsearch-logger-route",
    "latency": 703.9999961853,
    "apisix_latency": 34.999996185303,
    "upstream_latency": 669,
    "upstream": "34.197.122.172:80",
    "server": {
      "hostname": "0b9a772e68f8",
      "version": "3.11.0"
    },
    "service_id": "",
    "client_ip": "192.168.65.1"
  },
  "fields": {
    ...
  }
}
```

向路由发送一个没有任何 URL 查询字符串的请求：

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST -d '{"env": "dev"}'
```

导航到 Kibana 仪表板 __Discover__ 选项卡，您应该看到生成的日志，但没有请求正文：

```json
{
  "_index": "gateway",
  "_id": "EU-eL5QBOkdYRG7kUDST",
  "_version": 1,
  "_score": 1,
  "_source": {
    "request": {
      "headers": {
        "content-type": "application/x-www-form-urlencoded",
        "accept": "*/*",
        "content-length": "14",
        "host": "127.0.0.1:9080",
        "user-agent": "curl/8.6.0"
      },
      "size": 169,
      "querystring": {},
      "method": "POST",
      "url": "http://127.0.0.1:9080/anything",
      "uri": "/anything"
    },
    "start_time": 1735965686363,
    "response": {
      "headers": {
        "content-type": "application/json",
        "access-control-allow-credentials": "true",
        "server": "APISIX/3.11.0",
        "content-length": "510",
        "access-control-allow-origin": "*",
        "connection": "close",
        "date": "Mon, 13 Jan 2025 11:15:54 GMT"
      },
      "status": 200,
      "size": 738
    },
    "route_id": "elasticsearch-logger-route",
    "latency": 680.99999427795,
    "apisix_latency": 4.9999942779541,
    "upstream_latency": 676,
    "upstream": "34.197.122.172:80",
    "server": {
      "hostname": "0b9a772e68f8",
      "version": "3.11.0"
    },
    "service_id": "",
    "client_ip": "192.168.65.1"
  },
  "fields": {
    ...
  }
}
```

:::info

如果您除了将 `include_req_body` 或 `include_resp_body` 设置为 `true` 之外还自定义了 `log_format`，则插件不会在日志中包含正文。

作为一种解决方法，您可以在日志格式中使用 NGINX 变量 `$request_body`，例如：

```json
{
  "elasticsearch-logger": {
    ...,
    "log_format": {"body": "$request_body"}
  }
}
```

:::
