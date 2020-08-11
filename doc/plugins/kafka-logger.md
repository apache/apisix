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

- [中文](../zh-cn/plugins/kafka-logger.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**Info**](#info)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)


## Name

`kafka-logger` is a plugin which works as a Kafka client driver for the ngx_lua nginx module.

This will provide the ability to send Log data requests as JSON objects to external Kafka clusters.

This plugin provides the ability to push Log data as a batch to you're external Kafka topics. In case if you did not recieve the log data don't worry give it some time it will automatically send the logs after the timer function expires in our Batch Processor.

For more info on Batch-Processor in Apache APISIX please refer.
[Batch-Processor](../batch-processor.md)

## Attributes

|Name           |Requirement    |Description|
|---------      |--------       |-----------|
| broker_list   |required       | An array of Kafka brokers.|
| kafka_topic   |required       | Target topic to push data.|
| timeout       |optional       |Timeout for the upstream to send data.|
| key           |required       |Key for the message.|
|name           |optional       |A unique identifier to identity the batch processor|
|batch_max_size |optional       |Max size of each batch, default is 1000|
|inactive_timeout|optional      |maximum age in seconds when the buffer will be flushed if inactive, default is 5s|
|buffer_duration|optional       |Maximum age in seconds of the oldest entry in a batch before the batch must be processed, default is 5|
|max_retry_count|optional       |Maximum number of retries before removing from the processing pipe line; default is zero|
|retry_delay    |optional       |Number of seconds the process execution should be delayed if the execution fails; default is 1|

## Info

The `message` will write to the buffer first.
It will send to the kafka server when the buffer exceed the `batch_max_size`,
or every `buffer_duration` flush the buffer.

In case of success, returns `true`.
In case of errors, returns `nil` with a string describing the error (`buffer overflow`).

##### Sample broker list

This plugin supports to push in to more than one broker at a time. Specify the brokers of the external kafka servers as below
sample to take effect of this functionality.

```json
{
    "127.0.0.1":9092,
    "127.0.0.1":9093
}
```

## How To Enable

The following is an example on how to enable the kafka-logger for a specific route.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
       "kafka-logger": {
           "broker_list" :
             {
               "127.0.0.1":9092
             },
           "kafka_topic" : "test2",
           "key" : "key1",
           "batch_max_size": 1,
           "name": "kafka logger"
       }
    },
    "upstream": {
       "nodes": {
           "127.0.0.1:1980": 1
       },
       "type": "roundrobin"
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

Remove the corresponding json configuration in the plugin configuration to disable the `kafka-logger`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
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
