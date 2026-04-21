---
title: rocketmq-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - RocketMQ Logger
description: The rocketmq-logger Plugin pushes request and response logs as JSON objects to RocketMQ clusters in batches, allowing for customizable log formats to enhance data management.
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

## Description

The `rocketmq-logger` Plugin pushes request and response logs as JSON objects to RocketMQ clusters in batches and supports the customization of log formats.

## Attributes

| Name                   | Type    | Required | Default            | Valid values          | Description                                                                                                                                                                                                                                                                                                    |
|------------------------|---------|----------|--------------------|-----------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| nameserver_list        | object  | True     |                    |                       | List of RocketMQ nameservers.                                                                                                                                                                                                                                                                                  |
| topic                  | string  | True     |                    |                       | Target topic to push the data to.                                                                                                                                                                                                                                                                              |
| key                    | string  | False    |                    |                       | Key of the message.                                                                                                                                                                                                                                                                                            |
| tag                    | string  | False    |                    |                       | Tag of the message.                                                                                                                                                                                                                                                                                            |
| log_format             | object  | False    |                    |                       | Custom log format using key-value pairs in JSON format. Values can reference [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html). You can also configure log format on a global scale using the [plugin metadata](../plugin-metadata.md), which configures the log format for all `rocketmq-logger` Plugin instances. If the log format configured on the individual Plugin instance differs from the log format configured on Plugin metadata, the log format configured on the individual Plugin instance takes precedence. |
| timeout                | integer | False    | 3                  |                       | Timeout for the upstream to send data.                                                                                                                                                                                                                                                                         |
| use_tls                | boolean | False    | false              |                       | If true, verify SSL.                                                                                                                                                                                                                                                                                           |
| access_key             | string  | False    |                    |                       | Access key for ACL. Setting to an empty string will disable the ACL.                                                                                                                                                                                                                                           |
| secret_key             | string  | False    |                    |                       | Secret key for ACL.                                                                                                                                                                                                                                                                                            |
| name                   | string  | False    | `rocketmq logger`  |                       | Unique identifier of the Plugin for the batch processor. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                                                                                                              |
| meta_format            | string  | False    | `default`          | `default` or `origin` | Format to collect the request information. Setting to `default` collects the information in JSON format and `origin` collects the information with the original HTTP request.                                                                                                                                   |
| include_req_body       | boolean | False    | false              |                       | If true, include the request body in the log. Note that if the request body is too big to be kept in the memory, it cannot be logged due to NGINX's limitations.                                                                                                                                               |
| include_req_body_expr  | array   | False    |                    |                       | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr) expressions. Used when `include_req_body` is true. Request body is only logged when the expressions configured here evaluate to true.                                                                |
| include_resp_body      | boolean | False    | false              |                       | If true, include the response body in the log.                                                                                                                                                                                                                                                                 |
| include_resp_body_expr | array   | False    |                    |                       | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr) expressions. Used when `include_resp_body` is true. Response body is only logged when the expressions configured here evaluate to true.                                                              |
| max_req_body_bytes     | integer | False    | 524288             | greater than or equal to 1 | Maximum request body size in bytes to include in the log. If the request body exceeds this value, it will be truncated. Available in APISIX from 3.16.0.                                                                                                                                                  |
| max_resp_body_bytes    | integer | False    | 524288             | greater than or equal to 1 | Maximum response body size in bytes to include in the log. If the response body exceeds this value, it will be truncated. Available in APISIX from 3.16.0.                                                                                                                                                |
| batch_max_size         | integer | False    | 1000               | greater than 0        | The number of log entries allowed in one batch. Once reached, the batch will be sent to the logging service. Setting this parameter to 1 means immediate processing.                                                                                                                                           |
| inactive_timeout       | integer | False    | 5                  | greater than 0        | The maximum time in seconds to wait for new logs before sending the batch to the logging service. The value should be smaller than `buffer_duration`.                                                                                                                                                           |
| buffer_duration        | integer | False    | 60                 | greater than 0        | The maximum time in seconds from the earliest entry allowed before sending the batch to the logging service.                                                                                                                                                                                                   |
| retry_delay            | integer | False    | 1                  | greater than or equal to 0 | The time interval in seconds to retry sending the batch to the logging service if the batch was not successfully sent.                                                                                                                                                                                    |
| max_retry_count        | integer | False    | 60                 | greater than or equal to 0 | The maximum number of unsuccessful retries allowed before dropping the log entries.                                                                                                                                                                                                                       |

NOTE: `encrypt_fields = {"secret_key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name                | Type    | Required | Description                                                                                                                                                                                                     |
|---------------------|---------|----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format          | object  | False    | Custom log format using key-value pairs in JSON format. Values can reference [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html).                                                       |
| max_pending_entries | integer | False    | Maximum number of unprocessed entries allowed in the batch processor. When this limit is reached, new entries will be dropped until the backlog is reduced. Available in APISIX from version 3.15.0.            |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `rocketmq-logger` Plugin.

:::

## Examples

The examples below demonstrate how you can configure the `rocketmq-logger` Plugin for different scenarios.

To follow along the examples, start a sample RocketMQ cluster:

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

Start containers:

```shell
docker compose up -d
```

In a few seconds, the name server and broker should start.

Create the `TopicTest` topic:

```shell
docker exec -i rmqnamesrv rm /home/rocketmq/rocketmq-4.6.0/conf/tools.yml
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rmqnamesrv:9876 -t TopicTest -c DefaultCluster
```

Wait for messages in the configured RocketMQ topic:

```shell
docker run -it --name rockemq_consumer -e NAMESRV_ADDR=localhost:9876 --net host apacherocketmq/rocketmq:4.6.0 sh tools.sh org.apache.rocketmq.example.quickstart.Consumer
```

In a few seconds, the consumer should start and listen for messages from APISIX:

```text
Consumer Started.
```

Open a new terminal session for the following steps working with APISIX.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Log in Different Meta Log Formats

The following example demonstrates how you can enable the `rocketmq-logger` Plugin on a Route, which logs client requests to the Route and pushes logs to RocketMQ. You will also understand the differences between the `default` and `origin` meta log formats.

Create a Route with `rocketmq-logger` with `meta_format` set to the `default` log format and `batch_max_size` set to 1 to send the log entry immediately:

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

Send a request to the Route to generate a log entry:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should see a log entry similar to the following:

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

Update the `rocketmq-logger` meta log format to `origin`:

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

Send a request to the Route again to generate a new log entry:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should see a log entry in the raw HTTP request format:

```text
GET /anything HTTP/1.1
host: 127.0.0.1:9080
user-agent: curl/8.6.0
accept: */*
```

### Log Request and Response Headers With Plugin Metadata

The following example demonstrates how you can customize log format using [plugin metadata](../plugin-metadata.md) and NGINX variables to log specific headers from request and response.

In APISIX, [plugin metadata](../plugin-metadata.md) is used to configure the common metadata fields of all Plugin instances of the same Plugin. It is useful when a Plugin is enabled across multiple resources and requires a universal update to their metadata fields.

Note that customizing log format with Plugin metadata requires `meta_format` to be set to `default`. If `meta_format` is set to `origin`, the log entries will remain in `origin` format.

First, create a Route with `rocketmq-logger` with `meta_format` set to `default` and `batch_max_size` set to 1 to send the log entry immediately:

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

Next, configure the Plugin metadata for `rocketmq-logger` to log the custom request header `env` and the response header `Content-Type`:

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

Send a request to the Route with the `env` header:

```shell
curl -i "http://127.0.0.1:9080/anything" -H "env: dev"
```

You should see a log entry similar to the following:

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

### Log Request Bodies Conditionally

The following example demonstrates how you can conditionally log request body.

Create a Route with `rocketmq-logger` as follows, enabling request body logging only when the URL query string `log_body` is `yes`:

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

Send a request to the Route with a URL query string satisfying the condition:

```shell
curl -i "http://127.0.0.1:9080/anything?log_body=yes" -X POST -d '{"env": "dev"}'
```

You should see the request body logged:

```json
{
  "request": {
    "method": "POST",
    "body": "{\"env\": \"dev\"}",
    "size": 183
  }
}
```

Send a request to the Route without any URL query string:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST -d '{"env": "dev"}'
```

You should not observe the request body in the log.

:::note

If you have customized the `log_format` in addition to setting `include_req_body` or `include_resp_body` to `true`, the Plugin would not include the bodies in the logs.

As a workaround, you may be able to use the NGINX variable `$request_body` in the log format, such as:

```json
{
  "rocketmq-logger": {
    "log_format": {"body": "$request_body"}
  }
}
```

:::
