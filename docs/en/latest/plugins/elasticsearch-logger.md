---
title: elasticsearch-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Elasticsearch-logger
description: The elasticsearch-logger Plugin pushes request and response logs in batches to Elasticsearch and supports the customization of log formats.
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

## Description

The `elasticsearch-logger` Plugin pushes request and response logs in batches to [Elasticsearch](https://www.elastic.co) and supports the customization of log formats. When enabled, the Plugin will serialize the request context information to [Elasticsearch Bulk format](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html#docs-bulk) and add them to the queue, before they are pushed to Elasticsearch. See [batch processor](../batch-processor.md) for more details.

## Attributes

| Name          | Type    | Required | Default                     | Description                                                  |
| ------------- | ------- | -------- | --------------------------- | ------------------------------------------------------------ |
| endpoint_addrs  | array[string] | True     |                             | Elasticsearch API endpoint addresses. If multiple endpoints are configured, they will be written randomly.            |
| field         | object   | True     |                             | Elasticsearch `field` configuration.                          |
| field.index   | string  | True     |                             | Elasticsearch [_index field](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-index-field.html#mapping-index-field). |
| log_format | object | False    |                             | Custom log format as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX variables](http://nginx.org/en/docs/varindex.html) can be referenced by prefixing with `$`. |
| auth          | array   | False    |                             | Elasticsearch [authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) configuration. |
| auth.username | string  | True     |                             | Elasticsearch [authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) username. |
| auth.password | string  | True     |                             | Elasticsearch [authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html) password. |
| headers | object  | False     |                             | Custom headers to send with requests as key-value pairs. For example: `{"Authorization": "Bearer token", "X-API-Key": "key"}`. |
| ssl_verify    | boolean | False    | true                        | If true, perform SSL verification. |
| timeout       | integer | False    | 10                          | Elasticsearch send data timeout in seconds.                  |
| include_req_body       | boolean       | False    | false   |  If true, include the request body in the log. Note that if the request body is too big to be kept in the memory, it can not be logged due to NGINX's limitations.       |
| include_req_body_expr  | array[array]  | False    |         | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr). Used when the `include_req_body` is true. Request body would only be logged when the expressions configured here evaluate to true.      |
| include_resp_body      | boolean       | False    | false   | If true, include the response body in the log.       |
| include_resp_body_expr | array[array]  | False    |         | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr). Used when the `include_resp_body` is true. Response body would only be logged when the expressions configured here evaluate to true.     |

NOTE: `encrypt_fields = {"auth.password"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Plugin Metadata

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| log_format | object | False |  | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

## Examples

The examples below demonstrate how you can configure `elasticsearch-logger` Plugin for different scenarios.

To follow along the examples, start an Elasticsearch instance in Docker:

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

Start a Kibana instance in Docker to visualize the indexed data in Elasticsearch:

```shell
docker run -d \
  --name kibana \
  --network apisix-quickstart-net \
  -p 5601:5601 \
  -e ELASTICSEARCH_HOSTS="http://elasticsearch:9200" \
  docker.elastic.co/kibana/kibana:7.17.1
```

If successful, you should see the Kibana dashboard on [localhost:5601](http://localhost:5601).

:::note

You can fetch the APISIX `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Log in the Default Log Format

The following example demonstrates how you can enable the `elasticsearch-logger` Plugin on a route, which logs client requests and responses to the Route and pushes logs to Elasticsearch.

Create a Route with `elasticsearch-logger` to configure the `index` field as `gateway`:

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

Send a request to the Route to generate a log entry:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

Navigate to the Kibana dashboard on [localhost:5601](http://localhost:5601) and under __Discover__ tab, create a new index pattern `gateway` to fetch the data from Elasticsearch. Once configured, navigate back to the __Discover__ tab and you should see a log generated, similar to the following:

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

### Log Request and Response Headers With Plugin Metadata

The following example demonstrates how you can customize log format using [Plugin Metadata](../terminology/plugin-metadata.md) and [NGINX variables](http://nginx.org/en/docs/varindex.html) to log specific headers from request and response.

In APISIX, [Plugin Metadata](../terminology/plugin-metadata.md) is used to configure the common metadata fields of all Plugin instances of the same plugin. It is useful when a Plugin is enabled across multiple resources and requires a universal update to their metadata fields.

First, create a Route with `elasticsearch-logger` as follows:

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

Next, configure the Plugin metadata for `elasticsearch-logger`:

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

Send a request to the Route with the `env` header:

```shell
curl -i "http://127.0.0.1:9080/anything" -H "env: dev"
```

You should receive an `HTTP/1.1 200 OK` response.

Navigate to the Kibana dashboard on [localhost:5601](http://localhost:5601) and under __Discover__ tab, create a new index pattern `gateway` to fetch the data from Elasticsearch, if you have not done so already. Once configured, navigate back to the __Discover__ tab and you should see a log generated, similar to the following:

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

### Log Request Bodies Conditionally

The following example demonstrates how you can conditionally log request body.

Create a Route with `elasticsearch-logger` to only log request body if the URL query string `log_body` is `true`:

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

Send a request to the Route with an URL query string satisfying the condition:

```shell
curl -i "http://127.0.0.1:9080/anything?log_body=yes" -X POST -d '{"env": "dev"}'
```

You should receive an `HTTP/1.1 200 OK` response.

Navigate to the Kibana dashboard on [localhost:5601](http://localhost:5601) and under __Discover__ tab, create a new index pattern `gateway` to fetch the data from Elasticsearch, if you have not done so already. Once configured, navigate back to the __Discover__ tab and you should see a log generated, similar to the following:

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

Send a request to the Route without any URL query string:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST -d '{"env": "dev"}'
```

Navigate to the Kibana dashboard __Discover__ tab and you should see a log generated, but without the request body:

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

If you have customized the `log_format` in addition to setting `include_req_body` or `include_resp_body` to `true`, the Plugin would not include the bodies in the logs.

As a workaround, you may be able to use the NGINX variable `$request_body` in the log format, such as:

```json
{
  "elasticsearch-logger": {
    ...,
    "log_format": {"body": "$request_body"}
  }
}
```

:::
