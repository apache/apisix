---
title: syslog
keywords:
  - APISIX
  - API Gateway
  - Plugin
  - Syslog
description: This document contains information about the Apache APISIX syslog Plugin.
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

The `syslog` Plugin is used to push logs to a Syslog server.

Logs can be set as JSON objects.

## Attributes

| Name             | Type    | Required | Default      | Valid values  | Description                                                                                                              |
|------------------|---------|----------|--------------|---------------|--------------------------------------------------------------------------------------------------------------------------|
| host             | string  | True     |              |               | IP address or the hostname of the Syslog server.                                                                         |
| port             | integer | True     |              |               | Target port of the Syslog server.                                                                                        |
| name             | string  | False    | "sys logger" |               | Identifier for the server.                                                                                               |
| timeout          | integer | False    | 3000         | [1, ...]      | Timeout in ms for the upstream to send data.                                                                             |
| tls              | boolean | False    | false        |               | When set to `true` performs TLS verification.                                                                            |
| flush_limit      | integer | False    | 4096         | [1, ...]      | Maximum size of the buffer (KB) and the current message before it is flushed and written to the server.                  |
| drop_limit       | integer | False    | 1048576      |               | Maximum size of the buffer (KB) and the current message before the current message is dropped because of the size limit. |
| sock_type        | string  | False    | "tcp"        | ["tcp", "udp] | Transport layer protocol to use.                                                                                         |
| pool_size        | integer | False    | 5            | [5, ...]      | Keep-alive pool size used by `sock:keepalive`.                                                                           |
| log_format       | object  | False    |              |              | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |
| include_req_body | boolean | False    | false        |               | When set to `true` includes the request body in the log.                                                                 |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `syslog` Plugin.

:::

The example below shows how you can configure through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/syslog -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Enabling the Plugin

The example below shows how you can enable the Plugin for a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "syslog": {
                "host" : "127.0.0.1",
                "port" : 5044,
                "flush_limit" : 1
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

Now, if you make a request to APISIX, it will be logged in your Syslog server:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Disable Plugin

To disable the `syslog` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
