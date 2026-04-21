---
title: splunk-hec-logging
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Splunk HTTP Event Collector
  - splunk-hec-logging
description: The splunk-hec-logging Plugin serializes request and response context information to Splunk Event Data format and pushes to your Splunk HTTP Event Collector (HEC) in batches, allowing for customizable log formats to enhance data management.
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
  <link rel="canonical" href="https://docs.api7.ai/hub/splunk-hec-logging" />
</head>

## Description

The `splunk-hec-logging` Plugin serializes request and response context information to [Splunk Event Data format](https://docs.splunk.com/Documentation/Splunk/latest/Data/FormateventsforHTTPEventCollector#Event_metadata) and pushes to your [Splunk HTTP Event Collector (HEC)](https://docs.splunk.com/Documentation/Splunk/latest/Data/UsetheHTTPEventCollector) in batches. The Plugin also supports the customization of log formats.

## Attributes

| Name                       | Type    | Required | Default          | Valid values   | Description                                                                                                                                                                                                                                                                                                          |
|----------------------------|---------|----------|------------------|----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| endpoint                   | object  | True     |                  |                | Splunk HEC endpoint configurations.                                                                                                                                                                                                                                                                                  |
| endpoint.uri               | string  | True     |                  |                | Splunk HEC event collector API endpoint.                                                                                                                                                                                                                                                                             |
| endpoint.token             | string  | True     |                  |                | Splunk HEC authentication token.                                                                                                                                                                                                                                                                                     |
| endpoint.channel           | string  | False    |                  |                | Splunk HEC send data channel identifier. For more information, see [About HTTP Event Collector Indexer Acknowledgment](https://docs.splunk.com/Documentation/Splunk/latest/Data/AboutHECIDXAck).                                                                                                                     |
| endpoint.timeout           | integer | False    | 10               |                | Splunk HEC send data timeout in seconds.                                                                                                                                                                                                                                                                             |
| endpoint.keepalive_timeout | integer | False    | 60000            | >= 1000        | Keepalive timeout in milliseconds.                                                                                                                                                                                                                                                                                   |
| ssl_verify                 | boolean | False    | true             |                | If `true`, enables SSL verification as per [OpenResty docs](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake).                                                                                                                                                                                      |
| log_format                 | object  | False    |                  |                | Custom log format using key-value pairs in JSON format. Values can reference [APISIX variables](../apisix-variable.md) or [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) by prefixing with `$`. You can also configure log format on a global scale using [Plugin Metadata](#plugin-metadata). |
| name                       | string  | False    | splunk-hec-logging |              | Unique identifier of the Plugin for the batch processor.                                                                                                                                                                                                                                                             |
| batch_max_size             | integer | False    | 1000             | greater than 0 | The number of log entries allowed in one batch. Once reached, the batch will be sent to Splunk HEC. Setting this parameter to `1` means immediate processing.                                                                                                                                                        |
| inactive_timeout           | integer | False    | 5                | greater than 0 | The maximum time in seconds to wait for new logs before sending the batch to the logging service. The value should be smaller than `buffer_duration`.                                                                                                                                                                |
| buffer_duration            | integer | False    | 60               | greater than 0 | The maximum time in seconds from the earliest entry allowed before sending the batch to the logging service.                                                                                                                                                                                                         |
| retry_delay                | integer | False    | 1                | >= 0           | The time interval in seconds to retry sending the batch to the logging service if the batch was not successfully sent.                                                                                                                                                                                               |
| max_retry_count            | integer | False    | 60               | >= 0           | The maximum number of unsuccessful retries allowed before dropping the log entries.                                                                                                                                                                                                                                  |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Plugin Metadata

| Name               | Type    | Required | Default | Valid values | Description                                                                                                                                                                                                                                                                     |
|--------------------|---------|----------|---------|--------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format         | object  | False    |         |              | Custom log format using key-value pairs in JSON format. Values can reference [APISIX variables](../apisix-variable.md) or [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) by prefixing with `$`. This configuration is global and applies to all Routes and Services that use the `splunk-hec-logging` Plugin. |
| max_pending_entries | integer | False   |         | >= 1         | Maximum number of unprocessed entries allowed in the batch processor. When this limit is reached, new entries will be dropped until the backlog is reduced.                                                                                                                      |

## Examples

The examples below demonstrate how you can configure the `splunk-hec-logging` Plugin for different use cases.

To follow along with the examples, please complete the following steps to set up Splunk:

* Install [Splunk](https://www.splunk.com/en_us/download.html). Splunk Web should be running at `localhost:8000` by default.
* See [set up and use HTTP Event Collector in Splunk Web](https://docs.splunk.com/Documentation/Splunk/latest/Data/UsetheHTTPEventCollector) to set up an HTTP Event Collector.
* Navigate to **Settings > Data Inputs** at the upper-right corner of the console. You should see at least one input for the HTTP Event Collector. Note down the token value.
* Navigate to **Settings > Data Inputs** at the upper-right corner of the console and select **HTTP Event Collector**. In **Global Settings**, enable all tokens.
* In **Global Settings**, you should also find the collector's default port to be `8088`.

To verify the setup, execute the following command with your token:

```shell
curl "http://localhost:8088/services/collector/event" \ 
  -H "Authorization: Splunk <replace-with-your-token>" \
  -d '{"event": "hello world"}'
```

You should see a `success` response.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

### Push Log to Splunk

The following example demonstrates how to enable the `splunk-hec-logging` Plugin on a Route, which logs client requests and pushes logs to Splunk.

Create a Route as follows, replacing the `uri` with your Splunk HTTP collector's endpoint and IP address, and `token` with your collector's token:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "splunk-route",
    "uri": "/anything",
    "plugins": {
      "splunk-hec-logging":{
        "endpoint":{
          "uri":"http://192.168.2.108:8088/services/collector/event",
          "token":"26b15ddd-31db-455b-ak0c-9b5be3decc4a"
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

Send a few requests to the Route:

```shell
curl -i "http://127.0.0.1:9080/anything"
```

You should receive `HTTP/1.1 200 OK` responses.

Navigate to Splunk Web and select **Search & Reporting** in the left menu. In the search box, enter `source="apache-apisix-splunk-hec-logging"` and search for events from APISIX. You should see events corresponding to your requests, such as the following:

```json
{
  "response_size": 617,
  "response_headers": {
    "server": "APISIX/3.10.0",
    "connection": "close",
    "content-type": "application/json",
    "access-control-allow-credentials": "true",
    "access-control-allow-origin": "*",
    "date": "Wed, 27 Nov 2024 19:49:27 GMT",
    "content-length": "389"
  },
  "request_headers": {
    "host": "127.0.0.1:9080",
    "user-agent": "curl/8.6.0",
    "accept": "*/*"
  },
  "request_query": {},
  "request_url": "http://127.0.0.1:9080/anything",
  "upstream": "18.208.8.205:80",
  "latency": 746.00005149841,
  "request_method": "GET",
  "request_size": 85,
  "response_status": 200
}
```

### Log Request and Response Headers With Plugin Metadata

The following example demonstrates how to customize the log format using Plugin Metadata and [NGINX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html) to log specific headers from request and response.

Plugin Metadata is global in scope and applies to all instances of `splunk-hec-logging`. If the log format configured on an individual Plugin instance differs from the log format configured in Plugin Metadata, the instance-level configuration takes precedence.

Create a Route as follows, replacing the endpoint `uri` with your Splunk HTTP collector's endpoint and IP address, and `token` with your collector's token:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "splunk-route",
    "uri": "/anything",
    "plugins": {
      "splunk-hec-logging":{
        "endpoint":{
          "uri":"http://192.168.2.108:8088/services/collector/event",
          "token":"26b15ddd-31db-455b-ak0c-9b5be3decc4a"
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

Configure Plugin Metadata for `splunk-hec-logging` to log custom request header `env` and response header `Content-Type`:

```shell
curl "http://127.0.0.1:9180/apisix/admin/plugin_metadata/splunk-hec-logging" -X PUT \
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

Navigate to Splunk Web and select **Search & Reporting** in the left menu. In the search box, enter `source="apache-apisix-splunk-hec-logging"` and search for events. You should see the latest event corresponding to your request, similar to the following:

```json
{
  "host":"127.0.0.1",
  "env":"dev",
  "client_ip":"192.168.65.1",
  "@timestamp":"2024-11-27T20:59:28+00:00",
  "route_id":"splunk-route",
  "resp_content_type":"application/json"
}
```
