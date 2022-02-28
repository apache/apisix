---
title: tcp-logger
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

- [Summary](#summary)
- [Name](#name)
- [Attributes](#attributes)
- [How To Enable](#how-to-enable)
- [Test Plugin](#test-plugin)
- [Disable Plugin](#disable-plugin)

## Name

`tcp-logger` is a plugin which push Log data requests to TCP servers.

This will provide the ability to send Log data requests as JSON objects to Monitoring tools and other TCP servers.

This plugin provides the ability to push Log data as a batch to your external TCP servers. In case if you did not receive the log data don't worry give it some time it will automatically send the logs after the timer function expires in our Batch Processor.

For more info on Batch-Processor in Apache APISIX please refer.
[Batch-Processor](../batch-processor.md)

## Attributes

| Name             | Type    | Requirement | Default | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------- | ------- | ---------------------------------------------------------------------------------------- |
| host             | string  | required    |         |         | IP address or the Hostname of the TCP server.                                            |
| port             | integer | required    |         | [0,...] | Target upstream port.                                                                    |
| timeout          | integer | optional    | 1000    | [1,...] | Timeout for the upstream to send data.                                                   |
| tls              | boolean | optional    | false   |         | Control whether to perform SSL verification                                              |
| tls_options      | string  | optional    |         |         | tls options                                                                              |
| include_req_body | boolean | optional    | false   |         | Whether to include the request body                                                      |

The plugin also has some common parameters that are handled by the batch processor(a component of APISIX ). The batch processor can be used to aggregate entries(logs/any data) and process them in a batch.
This helps in reducing the number of requests that are being sent from the plugin per time frame to improve performance.
Of course the batch processors provide an out-of-the-box configuration, so you don't have to worry about it.
A brief overview of the parameters is provided here to help you choose.

| Parameters       | Descriptions                                                                                                    |   |   |   |
|------------------|----------------------------------------------------------------------------------------------------------------|---|---|---|
| batch_max_size   | When the value is set to 0, the processor executes immediately. When the value is set to greater than or equal to 1, entries are aggregated until the maximum value or timeout is reached. |   |   |   |
| inactive_timeout | This parameter indicates the maximum age in seconds that the buffer will be flushed without plugin activity information.                                     |   |   |   |
| buffer_duration  | This parameter indicates the maximum age in seconds that the oldest entries in the batch must first be processed.                                               |   |   |   |
| max_retry_count  | This parameter indicates the maximum number of retries before removal from the processing pipeline.                                                             |   |   |   |
| retry_delay      | This parameter indicates the number of seconds the process should be delayed if it fails.                                                           |   |   |   |

If you want to learn more about batch processors, please refer to [Batch-Processor](../batch-processor.md#配置) configuration section.

## How To Enable

The following is an example on how to enable the tcp-logger for a specific route.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Test Plugin

* success:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `tcp-logger`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
