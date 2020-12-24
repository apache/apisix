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

- [中文](../zh-cn/plugins/syslog.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

`sys` is a plugin which push Log data requests to Syslog.

This will provide the ability to send Log data requests as JSON objects.

## Attributes

| Name             | Type    | Requirement | Default      | Valid         | Description                                                                                                                                                                                          |
| ---------------- | ------- | ----------- | ------------ | ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| host             | string  | required    |              |               | IP address or the Hostname.                                                                                                                                                                          |
| port             | integer | required    |              |               | Target upstream port.                                                                                                                                                                                |
| name             | string  | optional    | "sys logger" |               |                                                                                                                                                                                                      |
| timeout          | integer | optional    | 3            | [1, ...]      | Timeout for the upstream to send data.                                                                                                                                                               |
| tls              | boolean | optional    | false        |               | Control whether to perform SSL verification                                                                                                                                                          |
| flush_limit      | integer | optional    | 4096         | [1, ...]      | If the buffered messages' size plus the current message size reaches (>=) this limit (in bytes), the buffered log messages will be written to log server. Default to 4096 (4KB).                     |
| drop_limit       | integer | optional    | 1048576      |               | If the buffered messages' size plus the current message size is larger than this limit (in bytes), the current log message will be dropped because of limited buffer size. Default to 1048576 (1MB). |
| sock_type        | string  | optional    | "tcp"        | ["tcp", "udp] | IP protocol type to use for transport layer.                                                                                                                                                         |
| max_retry_times  | integer | optional    | 1            | [1, ...]      | Max number of retry times after a connect to a log server failed or send log messages to a log server failed.                                                                                        |
| retry_interval   | integer | optional    | 1            | [0, ...]      | The time delay (in ms) before retry to connect to a log server or retry to send log messages to a log server                                                                                         |
| pool_size        | integer | optional    | 5            | [5, ...]      | Keepalive pool size used by sock:keepalive.                                                                                                                                                          |
| batch_max_size   | integer | optional    | 1000         | [1, ...]      | Max size of each batch                                                                                                                                                                               |
| buffer_duration  | integer | optional    | 60           | [1, ...]      | Maximum age in seconds of the oldest entry in a batch before the batch must be processed                                                                                                             |
| include_req_body | boolean | optional    | false        |               | Whether to include the request body                                                                                                                                                                  |

## How To Enable

The following is an example on how to enable the sys-logger for a specific route.

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

## Test Plugin

* success:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `sys-logger`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
