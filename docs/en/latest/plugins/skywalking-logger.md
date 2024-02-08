---
title: skywalking-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - SkyWalking Logger
  - skywalking-logger
description: This document contains information about the Apache APISIX skywalking-logger Plugin.
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

The `skywalking-logger` Plugin can be used to push access log data to SkyWalking OAP server of HTTP.

If there is an existing tracing context, it sets up the trace-log correlation automatically and relies on [SkyWalking Cross Process Propagation Headers Protocol](https://skywalking.apache.org/docs/main/next/en/api/x-process-propagation-headers-v3/). This provides the ability to send access logs as JSON objects to the SkyWalking OAP server.

## Attributes

| Name                  | Type    | Required | Default                | Valid values  | Description                                                                                                  |
|-----------------------|---------|----------|------------------------|---------------|--------------------------------------------------------------------------------------------------------------|
| endpoint_addr         | string  | True     |                        |               | URI of the SkyWalking OAP server.                                                                            |
| service_name          | string  | False    | "APISIX"               |               | Service name for the SkyWalking reporter.                                                                    |
| service_instance_name | string  | False    | "APISIX Instance Name" |               | Service instance name for the SkyWalking reporter. Set it to `$hostname` to directly get the local hostname. |
| log_format | object | False    |   |            | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |
| timeout               | integer | False    | 3                      | [1,...]       | Time to keep the connection alive for after sending a request.                                               |
| name                  | string  | False    | "skywalking logger"    |               | Unique identifier to identify the logger. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                                    |
| include_req_body      | boolean | False    | false                  | [false, true] | When set to `true` includes the request body in the log.                                                     |
| include_req_body_expr  | array         | False    |         |               | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.        |
| include_resp_body      | boolean       | False    | false   | [false, true] | When set to `true` includes the response body in the log.                                                                                                                                                                      |
| include_resp_body_expr | array         | False    |         |               | When the `include_resp_body` attribute is set to `true`, use this to filter based on [lua-resty-expr](https://github.com/api7/lua-resty-expr). If present, only logs the response if the expression evaluates to `true`.       |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### Example of default log format

  ```json
   {
      "serviceInstance": "APISIX Instance Name",
      "body": {
        "json": {
          "json": "body-json"
        }
      },
      "endpoint": "/opentracing",
      "service": "APISIX"
    }
  ```

For body-json data, it is an escaped json string

  ```json
    {
      "response": {
        "status": 200,
        "headers": {
          "server": "APISIX/3.7.0",
          "content-type": "text/plain",
          "transfer-encoding": "chunked",
          "connection": "close"
        },
        "size": 136
      },
      "route_id": "1",
      "upstream": "127.0.0.1:1982",
      "upstream_latency": 8,
      "apisix_latency": 101.00020599365,
      "client_ip": "127.0.0.1",
      "service_id": "",
      "server": {
        "hostname": "localhost",
        "version": "3.7.0"
      },
      "start_time": 1704429712768,
      "latency": 109.00020599365,
      "request": {
        "headers": {
          "content-length": "9",
          "host": "localhost",
          "connection": "close"
        },
        "method": "POST",
        "body": "body-data",
        "size": 94,
        "querystring": {},
        "url": "http://localhost:1984/opentracing",
        "uri": "/opentracing"
      }
    }
  ```

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    |  | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `skywalking-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/skywalking-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Enable Plugin

Once you have set up your SkyWalking OAP server, you can enable the Plugin on a specific Route as shown below:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "skywalking-logger": {
                "endpoint_addr": "http://127.0.0.1:12800"
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

Now, if you make a request to APISIX, it will be logged in your SkyWalking OAP server:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Delete Plugin

To remove the `skywalking-logger` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
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
