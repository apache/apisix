---
title: udp-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - UDP Logger
description: This document contains information about the Apache APISIX udp-logger Plugin.
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

The `udp-logger` Plugin can be used to push log data requests to UDP servers.

This provides the ability to send log data requests as JSON objects to monitoring tools and other UDP servers.

This plugin also allows to push logs as a batch to your external UDP server. It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name             | Type    | Required | Default      | Valid values | Description                                              |
|------------------|---------|----------|--------------|--------------|----------------------------------------------------------|
| host             | string  | True     |              |              | IP address or the hostname of the UDP server.            |
| port             | integer | True     |              | [0,...]      | Target upstream port.                                    |
| timeout          | integer | False    | 3            | [1,...]      | Timeout for the upstream to send data.                   |
| log_format       | object  | False    |  |              | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| name             | string  | False    | "udp logger" |              | Unique identifier for the batch processor. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`. processor.               |
| include_req_body | boolean | False    | false        | [false, true] | When set to `true` includes the request body in the log. |
| include_req_body_expr  | array   | No       |         |               | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                          |
| include_resp_body | boolean | No       | false   | [false, true] | When set to `true` includes the response body in the log.                                                                                                        |
| include_resp_body_expr | array   | No  |         |               | Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                        |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### Example of default log format

```json
{
  "apisix_latency": 99.999988555908,
  "service_id": "",
  "server": {
    "version": "3.7.0",
    "hostname": "localhost"
  },
  "request": {
    "method": "GET",
    "headers": {
      "connection": "close",
      "host": "localhost"
    },
    "url": "http://localhost:1984/opentracing",
    "size": 65,
    "querystring": {},
    "uri": "/opentracing"
  },
  "start_time": 1704527399740,
  "client_ip": "127.0.0.1",
  "response": {
    "status": 200,
    "size": 136,
    "headers": {
      "server": "APISIX/3.7.0",
      "content-type": "text/plain",
      "transfer-encoding": "chunked",
      "connection": "close"
    }
  },
  "upstream": "127.0.0.1:1982",
  "route_id": "1",
  "upstream_latency": 12,
  "latency": 111.99998855591
}
```

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    |  | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `udp-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/udp-logger -H "X-API-KEY: $admin_key" -X PUT -d '
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

With this configuration, your logs would be formatted as shown below:

```json
{"@timestamp":"2023-01-09T14:47:25+08:00","route_id":"1","host":"localhost","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200}}
```

## Enable Plugin

The example below shows how you can enable the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
{
      "plugins": {
            "udp-logger": {
                 "host": "127.0.0.1",
                 "port": 3000,
                 "batch_max_size": 1,
                 "name": "udp logger"
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

## Example usage

Now, if you make a request to APISIX, it will be logged in your UDP server:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Delete Plugin

To remove the `udp-logger` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
