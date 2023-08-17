---
title: elasticsearch-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Elasticsearch-logger
description: This document contains information about the Apache APISIX elasticsearch-logger Plugin.
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

## Description

The `elasticsearch-logger` Plugin is used to forward logs to [Elasticsearch](https://www.elastic.co/guide/en/welcome-to-elastic/current/getting-started-general-purpose.html) for analysis and storage.

When the Plugin is enabled, APISIX will serialize the request context information to [Elasticsearch Bulk format](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html#docs-bulk) and submit it to the batch queue. When the maximum batch size is exceeded, the data in the queue is pushed to Elasticsearch. See [batch processor](../batch-processor.md) for more details.

## Attributes

| Name          | Type    | Required | Default                     | Description                                                  |
| ------------- | ------- | -------- | --------------------------- | ------------------------------------------------------------ |
| endpoint_addr | string  | Deprecated     |                             | Deprecated. Use `endpoint_addrs` instead. Elasticsearch API.                                            |
| endpoint_addrs  | array  | True     |                             | Elasticsearch API. If multiple endpoints are configured, they will be written randomly.                                            |
| field         | array   | True     |                             | Elasticsearch `field` configuration.                          |
| field.index   | string  | True     |                             | Elasticsearch [_index field](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-index-field.html#mapping-index-field). |
| field.type    | string  | False    | Elasticsearch default value | Elasticsearch [_type field](https://www.elastic.co/guide/en/elasticsearch/reference/7.17/mapping-type-field.html#mapping-type-field). |
| log_format | object | False    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |
| auth          | array   | False    |                             | Elasticsearch [authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) configuration. |
| auth.username | string  | True     |                             | Elasticsearch [authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) username. |
| auth.password | string  | True     |                             | Elasticsearch [authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) password. |
| ssl_verify    | boolean | False    | true                        | When set to `true` enables SSL verification as per [OpenResty docs](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake). |
| timeout       | integer | False    | 10                          | Elasticsearch send data timeout in seconds.                  |

NOTE: `encrypt_fields = {"auth.password"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Enable Plugin

### Full configuration

The example below shows a complete configuration of the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

### Minimal configuration example

The example below shows a bare minimum configuration of the Plugin on a Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Example usage

Once you have configured the Route to use the Plugin, when you make a request to APISIX, it will be logged in your Elasticsearch server:

```shell
curl -i http://127.0.0.1:9080/elasticsearch.do\?q\=hello
HTTP/1.1 200 OK
...
hello, world
```

You should be able to get the log from elasticsearch:

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

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                      | Description                                                  |
| ---------- | ------ | -------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| log_format | object | False    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `elasticsearch-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/elasticsearch-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

With this configuration, your logs would be formatted as shown below:

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

 make a request to APISIX again:

```shell
curl -i http://127.0.0.1:9080/elasticsearch.do\?q\=hello
HTTP/1.1 200 OK
...
hello, world
```

You should be able to get this log from elasticsearch:

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

### Disable Metadata

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/elasticsearch-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X DELETE
```

## Delete Plugin

To remove the `elasticsearch-logger` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
