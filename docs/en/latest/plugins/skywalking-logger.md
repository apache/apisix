---
title: skywalking-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - SkyWalking Logger
  - skywalking-logger
description: The skywalking-logger pushes request and response logs as JSON objects to SkyWalking OAP server in batches and supports the customization of log formats.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/skywalking-logger" />
</head>

## Description

The `skywalking-logger` Plugin pushes request and response logs as JSON objects to SkyWalking OAP server in batches and supports the customization of log formats.

If there is an existing tracing context, it sets up the trace-log correlation automatically and relies on [SkyWalking Cross Process Propagation Headers Protocol](https://skywalking.apache.org/docs/main/next/en/api/x-process-propagation-headers-v3/).

## Attributes

| Name                  | Type    | Required | Default                | Valid values  | Description                                                                                                  |
|-----------------------|---------|----------|------------------------|---------------|--------------------------------------------------------------------------------------------------------------|
| endpoint_addr         | string  | True     |                        |               | URI of the SkyWalking OAP server.                                                                            |
| service_name          | string  | False    | "APISIX"               |               | Service name for the SkyWalking reporter.                                                                    |
| service_instance_name | string  | False    | "APISIX Instance Name" |               | Service instance name for the SkyWalking reporter. Set it to `$hostname` to directly get the local hostname. |
| log_format | object | False    |                             | Custom log format as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX variables](http://nginx.org/en/docs/varindex.html) can be referenced by prefixing with `$`. |
| timeout               | integer | False    | 3                      | [1,...]       | Time to keep the connection alive for after sending a request.                                               |
| name                  | string  | False    | "skywalking logger"    |               | Unique identifier to identify the logger. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                                    |
| include_req_body       | boolean       | False    | false   |  If true, include the request body in the log. Note that if the request body is too big to be kept in the memory, it can not be logged due to NGINX's limitations.       |
| include_req_body_expr  | array[array]  | False    |         | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr). Used when the `include_req_body` is true. Request body would only be logged when the expressions configured here evaluate to true.      |
| include_resp_body      | boolean       | False    | false   | If true, include the response body in the log.       |
| include_resp_body_expr | array[array]  | False    |         | An array of one or more conditions in the form of [lua-resty-expr](https://github.com/api7/lua-resty-expr). Used when the `include_resp_body` is true. Response body would only be logged when the expressions configured here evaluate to true.     |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    |  | Custom log format as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX variables](http://nginx.org/en/docs/varindex.html) can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

## Examples

The examples below demonstrate how you can configure `skywalking-logger` Plugin for different scenarios.

To follow along the example, start a storage, OAP and Booster UI with Docker Compose, following [Skywalking's documentation](https://skywalking.apache.org/docs/main/next/en/setup/backend/backend-docker/). Once set up, the OAP server should be listening on `12800` and you should be able to access the UI at [http://localhost:8080](http://localhost:8080).

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Log Requests in Default Log Format

The following example demonstrates how you can configure the `skywalking-logger` Plugin on a Route to log information of requests hitting the Route.

Create a Route with the `skywalking-logger` Plugin and configure the Plugin with your OAP server URI:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "skywalking-logger-route",
    "uri": "/anything",
    "plugins": {
      "skywalking-logger": {
        "endpoint_addr": "http://192.168.2.103:12800"
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

In [Skywalking UI](http://localhost:8080), navigate to __General Service__ > __Services__. You should see a service called `APISIX` with a log entry corresponding to your request:

```json
{
  "upstream_latency": 674,
  "request": {
    "method": "GET",
    "headers": {
      "user-agent": "curl/8.6.0",
      "host": "127.0.0.1:9080",
      "accept": "*/*"
    },
    "url": "http://127.0.0.1:9080/anything",
    "size": 85,
    "querystring": {},
    "uri": "/anything"
  },
  "client_ip": "192.168.65.1",
  "route_id": "skywalking-logger-route",
  "start_time": 1736945107345,
  "upstream": "3.210.94.60:80",
  "server": {
    "version": "3.11.0",
    "hostname": "7edbcebe8eb3"
  },
  "service_id": "",
  "response": {
    "size": 619,
    "status": 200,
    "headers": {
      "content-type": "application/json",
      "date": "Thu, 16 Jan 2025 12:45:08 GMT",
      "server": "APISIX/3.11.0",
      "access-control-allow-origin": "*",
      "connection": "close",
      "access-control-allow-credentials": "true",
      "content-length": "391"
    }
  },
  "latency": 764.9998664856,
  "apisix_latency": 90.999866485596
}
```

### Log Request and Response Headers With Plugin Metadata

The following example demonstrates how you can customize log format using Plugin metadata and built-in variables to log specific headers from request and response.

In APISIX, Plugin metadata is used to configure the common metadata fields of all Plugin instances of the same Plugin. It is useful when a Plugin is enabled across multiple resources and requires a universal update to their metadata fields.

First, create a Route with the `skywalking-logger` Plugin and configure the Plugin with your OAP server URI:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "skywalking-logger-route",
    "uri": "/anything",
    "plugins": {
      "skywalking-logger": {
        "endpoint_addr": "http://192.168.2.103:12800"
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

Next, configure the Plugin metadata for `skywalking-logger` to log the custom request header `env` and the response header `Content-Type`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/skywalking-logger" -X PUT \
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

You should receive an `HTTP/1.1 200 OK` response. In [Skywalking UI](http://localhost:8080), navigate to __General Service__ > __Services__. You should see a service called `APISIX` with a log entry corresponding to your request:

```json
[
  {
    "route_id": "skywalking-logger-route",
    "client_ip": "192.168.65.1",
    "@timestamp": "2025-01-16T12:51:53+00:00",
    "host": "127.0.0.1",
    "env": "dev",
    "resp_content_type": "application/json"
  }
]
```

### Log Request Bodies Conditionally

The following example demonstrates how you can conditionally log request body.

Create a Route with the `skywalking-logger` Plugin as such, to only include request body if the URL query string `log_body` is `yes`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "skywalking-logger-route",
    "uri": "/anything",
    "plugins": {
      "skywalking-logger": {
        "endpoint_addr": "http://192.168.2.103:12800",
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

You should receive an `HTTP/1.1 200 OK` response. In [Skywalking UI](http://localhost:8080), navigate to __General Service__ > __Services__. You should see a service called `APISIX` with a log entry corresponding to your request, with the request body logged:

```json
[
  {
    "request": {
      "url": "http://127.0.0.1:9080/anything?log_body=yes",
      "querystring": {
        "log_body": "yes"
      },
      "uri": "/anything?log_body=yes",
      ...,
      "body": "{\"env\": \"dev\"}",
    },
    ...
  }
]
```

Send a request to the Route without any URL query string:

```shell
curl -i "http://127.0.0.1:9080/anything" -X POST -d '{"env": "dev"}'
```

You should not observe a log entry without the request body.

:::info

If you have customized the `log_format` in addition to setting `include_req_body` or `include_resp_body` to `true`, the Plugin would not include the bodies in the logs.

As a workaround, you may be able to use the NGINX variable `$request_body` in the log format, such as:

```json
{
  "skywalking-logger": {
    ...,
    "log_format": {"body": "$request_body"}
  }
}
```

:::

### Associate Traces with Logs

The following example demonstrates how you can configure the `skywalking-logger` Plugin on a Route to log information of requests hitting the route.

Create a Route with the `skywalking-logger` Plugin and configure the Plugin with your OAP server URI:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "skywalking-logger-route",
    "uri": "/anything",
    "plugins": {
      "skywalking": {
        "sample_ratio": 1
      },
      "skywalking-logger": {
        "endpoint_addr": "http://192.168.2.103:12800"
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

Generate a few requests to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive `HTTP/1.1 200 OK` responses.

In [Skywalking UI](http://localhost:8080), navigate to __General Service__ > __Services__. You should see a service called `APISIX` with a trace corresponding to your request, where you can view the associated logs:

![trace context](https://static.apiseven.com/uploads/2025/01/16/soUpXm6b_trace-view-logs.png)

![associated log](https://static.apiseven.com/uploads/2025/01/16/XD934LvU_associated-logs.png)
