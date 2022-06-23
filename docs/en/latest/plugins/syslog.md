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
| max_retry_times  | integer | False    |              | [1, ...]      | Deprecated. Use `max_retry_count` instead. Maximum number of retries if a connection to a log server fails.              |
| retry_interval   | integer | False    |              | [0, ...]      | Deprecated. Use `retry_delay` instead. Time in ms before retrying the connection to the log server.                      |
| pool_size        | integer | False    | 5            | [5, ...]      | Keep-alive pool size used by `sock:keepalive`.                                                                           |
| include_req_body | boolean | False    | false        |               | When set to `true` includes the request body in the log.                                                                 |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Enabling the Plugin

The example below shows how you can enable the Plugin for a specific Route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
