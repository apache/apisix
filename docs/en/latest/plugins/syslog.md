---
title: syslog
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Syslog
description: The syslog Plugin pushes request and response logs as JSON objects to syslog servers in batches, allowing for customizable log formats to enhance data management.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/syslog" />
</head>

## Description

The `syslog` Plugin pushes request and response logs as JSON objects to syslog servers in batches and supports the customization of log formats.

## Attributes

| Name                   | Type    | Required | Default      | Valid values          | Description                                                                                                                                                                                                               |
|------------------------|---------|----------|--------------|-----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| host                   | string  | True     |              |                       | IP address or hostname of the syslog server.                                                                                                                                                                              |
| port                   | integer | True     |              |                       | Target port of the syslog server.                                                                                                                                                                                         |
| timeout                | integer | False    | 3000         | greater than 0        | Timeout for the upstream to send data, in milliseconds.                                                                                                                                                                   |
| tls                    | boolean | False    | false        |                       | If true, verify TLS.                                                                                                                                                                                                      |
| flush_limit            | integer | False    | 4096         | greater than 0        | Maximum size of the buffer and the current message in bytes (B) before the logs are pushed to the syslog server.                                                                                                          |
| drop_limit             | integer | False    | 1048576      | greater than 0        | Maximum size of the buffer and the current message allowed in bytes (B) before the logs are dropped.                                                                                                                      |
| sock_type              | string  | False    | `tcp`        | `tcp` or `udp`        | Transport layer protocol to use.                                                                                                                                                                                          |
| pool_size              | integer | False    | 5            | greater than or equal to 5 | Keep-alive pool size used by `sock:keepalive`.                                                                                                                                                                       |
| log_format             | object  | False    |              |                       | Custom log format using key-value pairs in JSON format. Values can reference [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html). You can also configure log format on a global scale using the [plugin metadata](../plugin-metadata.md), which configures the log format for all `syslog` Plugin instances. If the log format configured on the individual Plugin instance differs from the log format configured on Plugin metadata, the log format configured on the individual Plugin instance takes precedence. |
| include_req_body       | boolean | False    | false        |                       | If true, include the request body in the log. Note that if the request body is too big to be kept in the memory, it cannot be logged due to NGINX's limitations.                                                          |
| include_req_body_expr  | array   | False    |              |                       | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr) expressions. Used when `include_req_body` is true. Request body is only logged when the expressions configured here evaluate to true. |
| include_resp_body      | boolean | False    | false        |                       | If true, include the response body in the log.                                                                                                                                                                            |
| include_resp_body_expr | array   | False    |              |                       | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr) expressions. Used when `include_resp_body` is true. Response body is only logged when the expressions configured here evaluate to true. |
| max_req_body_bytes     | integer | False    | 524288       | greater than or equal to 1 | Maximum request body size in bytes to include in the log. If the request body exceeds this value, it will be truncated. Available in APISIX from 3.16.0.                                                             |
| max_resp_body_bytes    | integer | False    | 524288       | greater than or equal to 1 | Maximum response body size in bytes to include in the log. If the response body exceeds this value, it will be truncated. Available in APISIX from 3.16.0.                                                           |
| name                   | string  | False    | `sys logger` |                       | Unique identifier of the Plugin for the batch processor. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                        |
| batch_max_size         | integer | False    | 1000         | greater than 0        | The number of log entries allowed in one batch. Once reached, the batch will be sent to the logging service. Setting this parameter to 1 means immediate processing.                                                     |
| inactive_timeout       | integer | False    | 5            | greater than 0        | The maximum time in seconds to wait for new logs before sending the batch to the logging service. The value should be smaller than `buffer_duration`.                                                                     |
| buffer_duration        | integer | False    | 60           | greater than 0        | The maximum time in seconds from the earliest entry allowed before sending the batch to the logging service.                                                                                                              |
| retry_delay            | integer | False    | 1            | greater than or equal to 0 | The time interval in seconds to retry sending the batch to the logging service if the batch was not successfully sent.                                                                                               |
| max_retry_count        | integer | False    | 60           | greater than or equal to 0 | The maximum number of unsuccessful retries allowed before dropping the log entries.                                                                                                                                  |

:::note

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

:::

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Description                                                                                                                                                              |
|------------|--------|----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format | object | False    | Custom log format using key-value pairs in JSON format. Values can reference [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html).                |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `syslog` Plugin.

:::

## Examples

The examples below demonstrate how you can configure the `syslog` Plugin for different scenarios.

To follow along the examples, start an example rsyslog server in Docker:

```shell
docker run -d -p 514:514 --name example-rsyslog-server rsyslog/syslog_appliance_alpine
```

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Push Log to Syslog Server

The following example demonstrates how you can enable the `syslog` Plugin on a Route, which logs client requests to the Route and pushes logs to the syslog server.

Create a Route with `syslog`, replacing the `host` and `port` with the address and port of your syslog server. Set `flush_limit` to 1 to push log to the syslog server immediately:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "syslog-route",
    "uri": "/anything",
    "plugins": {
      "syslog": {
        "host" : "172.0.0.1",
        "port" : 514,
        "flush_limit" : 1
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
curl -i "http://127.0.0.1:9080/anything"
```

You should receive an `HTTP/1.1 200 OK` response.

In the syslog server, you should see a log entry similar to the following:

```json
{
  "response": {
    "status": 200,
    "headers": {
      "access-control-allow-credentials": "true",
      "connection": "close",
      "date": "Sat, 02 Mar 2024 00:14:19 GMT",
      "access-control-allow-origin": "*",
      "server": "APISIX/3.8.0",
      "content-type": "application/json",
      "content-length": "387"
    },
    "size": 614
  },
  "service_id": "",
  "client_ip": "172.19.0.1",
  "server": {
    "hostname": "eff61bf7be4d",
    "version": "3.8.0"
  },
  "upstream": "35.171.123.176:80",
  "apisix_latency": 13.999900817871,
  "request": {
    "method": "GET",
    "url": "http://127.0.0.1:9080/anything",
    "querystring": {},
    "size": 86,
    "uri": "/anything",
    "headers": {
      "host": "127.0.0.1:9080",
      "accept": "*/*",
      "user-agent": "curl/7.29.0"
    }
  },
  "route_id": "syslog-route",
  "upstream_latency": 165,
  "latency": 178.99990081787,
  "start_time": 1709334859598
}
```

### Customize Log Format With Plugin Metadata

The following example demonstrates how you can customize log format using [plugin metadata](../plugin-metadata.md). The log format configured in Plugin metadata will apply to all `syslog` Plugin instances.

Create a Route with the `syslog` Plugin:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "syslog-route",
    "uri": "/anything",
    "plugins": {
      "syslog": {
        "host" : "172.0.0.1",
        "port" : 514,
        "flush_limit" : 1
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

Configure Plugin metadata for `syslog`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/syslog" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "log_format": {
      "host": "$host",
      "@timestamp": "$time_iso8601",
      "route_id": "$route_id",
      "client_ip": "$remote_addr",
      "resp_content_type": "$sent_http_Content_Type"
    }
  }'
```

Send a request to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

In the syslog server, you should see a log entry similar to the following:

```json
{
  "@timestamp": "2024-03-02T00:00:31+00:00",
  "resp_content_type": "application/json",
  "host": "127.0.0.1",
  "route_id": "syslog-route",
  "client_ip": "172.19.0.1"
}
```

### Log Request Bodies Conditionally

The following example demonstrates how you can conditionally log request body.

Create a Route with the `syslog` Plugin, enabling request body logging only when the URL query string `log_body` is `yes`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "syslog-route",
    "uri": "/anything",
    "plugins": {
      "syslog": {
        "host" : "172.0.0.1",
        "port" : 514,
        "flush_limit" : 1,
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
    "url": "http://127.0.0.1:9080/anything?log_body=yes",
    "querystring": {
      "log_body": "yes"
    },
    "size": 183,
    "body": "{\"env\": \"dev\"}",
    "uri": "/anything?log_body=yes",
    "headers": {
      "accept": "*/*",
      "user-agent": "curl/7.29.0",
      "host": "127.0.0.1:9080",
      "content-type": "application/x-www-form-urlencoded",
      "content-length": "14"
    }
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
  "syslog": {
    "log_format": {"body": "$request_body"}
  }
}
```

:::
