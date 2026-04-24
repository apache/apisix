---
title: http-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - HTTP Logger
description: The http-logger Plugin pushes request and response logs as JSON objects to HTTP(S) servers in batches, allowing for customizable log formats to enhance data management.
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

## Description

The `http-logger` Plugin pushes request and response logs as JSON objects to HTTP(S) servers in batches and supports the customization of log formats.

## Attributes

| Name                   | Type    | Required | Default | Valid values         | Description                                                                                                                                                                                                                                                                  |
|------------------------|---------|----------|---------|----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| uri                    | string  | True     |         |                      | URI of the HTTP(S) server.                                                                                                                                                                                                                                                   |
| auth_header            | string  | False    |         |                      | Authorization headers, if required by the HTTP(S) server.                                                                                                                                                                                                                   |
| timeout                | integer | False    | 3       | greater than 0       | Time to keep the connection alive after sending a request.                                                                                                                                                                                                                   |
| log_format             | object  | False    |         |                      | Custom log format using key-value pairs in JSON format. Values can reference [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html). You can also configure log format on a global scale using the [plugin metadata](../terminology/plugin-metadata.md), which configures the log format for all `http-logger` Plugin instances. If the log format configured on the individual Plugin instance differs from the log format configured on Plugin metadata, the log format configured on the individual Plugin instance takes precedence. |
| include_req_body       | boolean | False    | false   |                      | If true, include the request body in the log. Note that if the request body is too big to be kept in the memory, it cannot be logged due to NGINX's limitations.                                                                                                             |
| include_req_body_expr  | array   | False    |         |                      | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr) expressions. Used when `include_req_body` is true. Request body is only logged when the expressions configured here evaluate to true.                              |
| include_resp_body      | boolean | False    | false   |                      | If true, include the response body in the log.                                                                                                                                                                                                                               |
| include_resp_body_expr | array   | False    |         |                      | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr) expressions. Used when `include_resp_body` is true. Response body is only logged when the expressions configured here evaluate to true.                            |
| max_req_body_bytes     | integer | False    | 524288  | greater than or equal to 1 | Maximum request body size in bytes to include in the log. If the request body exceeds this value, it will be truncated.                                                                                                                                                |
| max_resp_body_bytes    | integer | False    | 524288  | greater than or equal to 1 | Maximum response body size in bytes to include in the log. If the response body exceeds this value, it will be truncated.                                                                                                                                              |
| concat_method          | string  | False    | `json`  | `json` or `new_line` | Method to concatenate logs. When set to `json`, use `json.encode` for all pending logs. When set to `new_line`, also use `json.encode` but use the newline character `\n` to concatenate lines.                                                                               |
| ssl_verify             | boolean | False    | false   |                      | If true, verify the server's SSL certificate.                                                                                                                                                                                                                                |

:::note

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

:::

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name                | Type    | Required | Description                                                                                                                                                                                                     |
|---------------------|---------|----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format          | object  | False    | Custom log format using key-value pairs in JSON format. Values can reference [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html).                                                       |
| max_pending_entries | integer | False    | Maximum number of unprocessed entries allowed in the batch processor. When this limit is reached, new entries will be dropped until the backlog is reduced. Available in APISIX from version 3.15.0.            |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `http-logger` Plugin.

:::

## Examples

The examples below demonstrate how you can configure the `http-logger` Plugin for different scenarios.

To follow along the examples, start a mock HTTP logging endpoint using [mockbin](https://mockbin.io) and note down the mockbin URL.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Log Requests in Default Log Format

The following example demonstrates how you can configure the `http-logger` Plugin on a Route to log information of requests hitting the Route.

Create a Route with the `http-logger` Plugin and configure the Plugin with your server URI:

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

Send a request to the Route:

```shell
curl "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response. In your mockbin, you should see a log entry similar to the following:

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

### Log Request and Response Headers With Plugin Metadata

The following example demonstrates how you can customize log format using [plugin metadata](../terminology/plugin-metadata.md) and NGINX variables to log specific headers from request and response.

In APISIX, [plugin metadata](../terminology/plugin-metadata.md) is used to configure the common metadata fields of all Plugin instances of the same Plugin. It is useful when a Plugin is enabled across multiple resources and requires a universal update to their metadata fields.

First, create a Route with the `http-logger` Plugin and configure the Plugin with your server URI:

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

Next, configure the Plugin metadata for `http-logger` to log the custom request header `env` and the response header `Content-Type`:

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

Send a request to the Route with the `env` header:

```shell
curl "http://127.0.0.1:9080/anything" -H "env: dev"
```

You should receive an `HTTP/1.1 200 OK` response. In your mockbin, you should see a log entry similar to the following:

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

### Log Request Bodies Conditionally

The following example demonstrates how you can conditionally log request body.

Create a Route with the `http-logger` Plugin as follows, enabling request body logging only when the URL query string `log_body` is `yes`:

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

Send a request to the Route with a URL query string satisfying the condition:

```shell
curl -i "http://127.0.0.1:9080/anything?log_body=yes" -X POST -d '{"env": "dev"}'
```

You should see the request body logged:

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
  "http-logger": {
    "log_format": {"body": "$request_body"}
  }
}
```

:::
