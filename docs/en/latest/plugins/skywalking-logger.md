---
title: http-logger
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

## Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Metadata**](#metadata)
- [**Disable Plugin**](#disable-plugin)

## Name

`skywalking-logger` is a plugin which push Access Log data to `SkyWalking OAP` server over HTTP.

This will provide the ability to send Access Log as JSON objects to `SkyWalking OAP` server.

## Attributes

| Name             | Type    | Requirement | Default       | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------------- | ------- | ---------------------------------------------------------------------------------------- |
| endpoint_addr    | string  | required    |               |         | The URI of the `SkyWalking OAP` server.                                                  |
| service_name     | string  | optional    | "APISIX"      |         | service name for SkyWalking reporter.                                                    |
| service_instance_name | string  | optional   |"APISIX Instance Name" |    | service instance name for SkyWalking reporter，  set it to `$hostname` to get local hostname directly.|
| timeout          | integer | optional    | 3             | [1,...] | Time to keep the connection alive after sending a request.                               |
| name             | string  | optional    | "skywalking logger" |         | A unique identifier to identity the logger.                                              |
| batch_max_size   | integer | optional    | 1000          | [1,...] | Set the maximum number of logs sent in each batch. When the number of logs reaches the set maximum, all logs will be automatically pushed to the `SkyWalking OAP` server. |
| inactive_timeout | integer | optional    | 5             | [1,...] | The maximum time to refresh the buffer (in seconds). When the maximum refresh time is reached, all logs will be automatically pushed to the `SkyWalking OAP` server regardless of whether the number of logs in the buffer reaches the maximum number set. |
| buffer_duration  | integer | optional    | 60            | [1,...] | Maximum age in seconds of the oldest entry in a batch before the batch must be processed.|
| max_retry_count  | integer | optional    | 0             | [0,...] | Maximum number of retries before removing from the processing pipe line.                 |
| retry_delay      | integer | optional    | 1             | [0,...] | Number of seconds the process execution should be delayed if the execution fails.        |
| include_req_body | boolean | optional    | false         | [false, true] | Whether to include the request body. false: indicates that the requested body is not included; true: indicates that the requested body is included. |

## How To Enable

The following is an example of how to enable the `skywalking-logger` for a specific route. Before that, an available `SkyWalking OAP` server was required and accessable.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "http-logger": {
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

## Test Plugin

> success:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

Completion of the steps, could find the Log details on `SkyWalking UI`.

## Metadata

`skywalking-logger` is also support to custom log format like [http-logger](/http-logger.md).

| Name             | Type    | Requirement | Default       | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------------- | ------- | ---------------------------------------------------------------------------------------- |
| log_format       | object  | optional    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | Log format declared as key value pair in JSON format. Only string is supported in the `value` part. If the value starts with `$`, it means to get `APISIX` variables or [Nginx variable](http://nginx.org/en/docs/varindex.html). |

 Note that **the metadata configuration is applied in global scope**, which means it will take effect on all Route or Service which use `skywalking-logger` plugin.

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `skywalking-logger`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
