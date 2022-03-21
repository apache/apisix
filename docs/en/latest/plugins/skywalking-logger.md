---
title: skywalking-logger
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

`skywalking-logger` is a plugin which push Access Log data to `SkyWalking OAP` server over HTTP. If there is tracing context existing, it sets up the trace-log correlation automatically, and relies on [SkyWalking Cross Process Propagation Headers Protocol](https://skywalking.apache.org/docs/main/latest/en/protocols/skywalking-cross-process-propagation-headers-protocol-v3/).

This will provide the ability to send Access Log as JSON objects to `SkyWalking OAP` server.

## Attributes

| Name             | Type    | Requirement | Default       | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------------- | ------- | ---------------------------------------------------------------------------------------- |
| endpoint_addr    | string  | required    |               |         | The URI of the `SkyWalking OAP` server.                                                  |
| service_name     | string  | optional    | "APISIX"      |         | service name for SkyWalking reporter.                                                    |
| service_instance_name | string  | optional   |"APISIX Instance Name" |    | service instance name for SkyWalking reporter，  set it to `$hostname` to get local hostname directly.|
| timeout          | integer | optional    | 3             | [1,...] | Time to keep the connection alive after sending a request.                               |
| name             | string  | optional    | "skywalking logger" |         | A unique identifier to identity the logger.                                              |
| include_req_body | boolean | optional    | false         | [false, true] | Whether to include the request body. false: indicates that the requested body is not included; true: indicates that the requested body is included. |

The plugin supports the use of batch processors to aggregate and process entries(logs/data) in a batch. This avoids frequent data submissions by the plugin, which by default the batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. For information or custom batch processor parameter settings, see [Batch-Processor](../batch-processor.md#configuration) configuration section.

## How To Enable

The following is an example of how to enable the `skywalking-logger` for a specific route. Before that, an available `SkyWalking OAP` server was required and accessible.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

`skywalking-logger` also supports to custom log format like [http-logger](./http-logger.md).

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
