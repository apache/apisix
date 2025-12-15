---
title: tcp-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - TCP Logger
  - tcp-logger
description: This document contains information about the Apache APISIX tcp-logger Plugin.
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

The `tcp-logger` Plugin can be used to push log data requests to TCP servers.

This provides the ability to send log data requests as JSON objects to monitoring tools and other TCP servers.

This plugin also allows to push logs as a batch to your external TCP server. It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name             | Type    | Required | Default | Valid values | Description                                              |
|------------------|---------|----------|---------|--------------|----------------------------------------------------------|
| host             | string  | True     |         |              | IP address or the hostname of the TCP server.            |
| port             | integer | True     |         | [0,...]      | Target upstream port.                                    |
| timeout          | integer | False    | 1000    | [1,...]      | Timeout for the upstream to send data.                   |
| log_format       | object  | False    |  |              | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| tls              | boolean | False    | false   |              | When set to `true` performs SSL verification.            |
| tls_options      | string  | False    |         |              | TLS options.                                             |
| include_req_body | boolean | False    | false   | [false, true] | When set to `true` includes the request body in the log. |
| include_req_body_expr  | array   | No       |         |               | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                          |
| include_resp_body | boolean | No       | false   | [false, true] | When set to `true` includes the response body in the log.                                                                                                        |
| include_resp_body_expr | array   | No  |         |               | Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                        |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### Example of default log format

```json
{
    "response": {
        "status": 200,
        "headers": {
            "server": "APISIX/3.7.0",
            "content-type": "text/plain",
            "content-length": "12",
            "connection": "close"
        },
        "size": 118
    },
    "server": {
        "version": "3.7.0",
        "hostname": "localhost"
    },
    "start_time": 1704527628474,
    "client_ip": "127.0.0.1",
    "service_id": "",
    "latency": 102.9999256134,
    "apisix_latency": 100.9999256134,
    "upstream_latency": 2,
    "request": {
        "headers": {
            "connection": "close",
            "host": "localhost"
        },
        "size": 59,
        "method": "GET",
        "uri": "/hello",
        "url": "http://localhost:1984/hello",
        "querystring": {}
    },
    "upstream": "127.0.0.1:1980",
    "route_id": "1"
}
```

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    |  | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `tcp-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/tcp-logger -H "X-API-KEY: $admin_key" -X PUT -d '
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

The example below shows how you can enable the `tcp-logger` Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
{
      "plugins": {
            "tcp-logger": {
                 "host": "127.0.0.1",
                 "port": 5044,
                 "tls": false,
                 "batch_max_size": 1,
                 "name": "tcp logger"
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

Now, if you make a request to APISIX, it will be logged in your TCP server:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Delete Plugin

To remove the `tcp-logger` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
