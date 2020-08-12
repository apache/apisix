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

- [中文](../zh-cn/plugins/tcp-logger.md)

# Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

`tcp-logger` is a plugin which push Log data requests to TCP servers.

This will provide the ability to send Log data requests as JSON objects to Monitoring tools and other TCP servers.

This plugin provides the ability to push Log data as a batch to you're external TCP servers. In case if you did not recieve the log data don't worry give it some time it will automatically send the logs after the timer function expires in our Batch Processor.

For more info on Batch-Processor in Apache APISIX please refer.
[Batch-Processor](../batch-processor.md)

## Attributes

|Name           |Requirement    |Description|
|---------      |--------       |-----------|
|host           |required       | IP address or the Hostname of the TCP server.|
|port           |required       | Target upstream port.|
|timeout        |optional       |Timeout for the upstream to send data.|
|tls            |optional       |Boolean value to control whether to perform SSL verification|
|tls_options    |optional       |tls options|
|name           |optional       |A unique identifier to identity the batch processor|
|batch_max_size |optional       |Max size of each batch, default is 1000|
|inactive_timeout|optional      |maximum age in seconds when the buffer will be flushed if inactive, default is 5s|
|buffer_duration|optional       |Maximum age in seconds of the oldest entry in a batch before the batch must be processed, default is 5|
|max_retry_count|optional       |Maximum number of retries before removing from the processing pipe line; default is zero|
|retry_delay    |optional       |Number of seconds the process execution should be delayed if the execution fails; default is 1|

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
$ curl http://127.0.0.1:2379/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
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
