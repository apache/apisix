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

## Attributes

|Name          |Requirement  |Description|
|---------     |--------|-----------|
| broker_list |required| An array of Kafka brokers.|
| kafka_topic |required| Target topic to push data.|
| timeout |optional|Timeout for the upstream to send data.|
| async |optional|Boolean value to control whether to perform async push.|
| key |required|Key for the message.|
| max_retry |optional|No of retries|

## Info

Difference between async and the sync data push.

1. In sync model

    In case of success, returns the offset (** cdata: LL **) of the current broker and partition.
    In case of errors, returns `nil` with a string describing the error.

2. In async model

    The `message` will write to the buffer first.
    It will send to the kafka server when the buffer exceed the `batch_num`,
    or every `flush_time` flush the buffer.

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

1. Here is an examle on how to enable kafka-logger plugin for a specific route.

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "foo",
    "plugins": {
       "kafka-logger": {
           "broker_list" :
             {
               "127.0.0.1":9092
             },
           "kafka_topic" : "test2",
           "key" : "key1"
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

When you want to disable the `kafka-logger` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1 -X PUT -d value='
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
