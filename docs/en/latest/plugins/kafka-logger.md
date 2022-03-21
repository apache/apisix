---
title: kafka-logger
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

`kafka-logger` is a plugin which works as a Kafka client driver for the ngx_lua nginx module.

This plugin provides the ability to push requests log data as JSON objects to your external Kafka clusters. In case if you did not receive the log data don't worry give it some time it will automatically send the logs after the timer function expires in our Batch Processor.

For more info on Batch-Processor in Apache APISIX please refer.
[Batch-Processor](../batch-processor.md)

## Attributes

| Name             | Type    | Requirement | Default        | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | -------------- | ------- | ---------------------------------------------------------------------------------------- |
| broker_list      | object  | required    |                |         | An array of Kafka brokers.                                                               |
| kafka_topic      | string  | required    |                |         | Target  topic to push data.                                                              |
| producer_type    | string  | optional    | async          | ["async", "sync"]        | Producer's mode of sending messages.          |
| required_acks          | integer | optional    | 1              | [0, 1, -1] | The number of acknowledgments the producer requires the leader to have received before considering a request complete. This controls the durability of records that are sent. Semantics is the same as kafka producer acks(If set `acks=0`  then the producer will not wait for any acknowledgment from the server at all. The record will be immediately added to the socket buffer and considered sent. `acks=1` This will mean the leader will write the record to its local log but will respond without awaiting full acknowledgement from all followers. `acks=-1` This means the leader will wait for the full set of in-sync replicas to acknowledge the record.).      |
| key              | string  | optional    |                |         | Used for partition allocation of messages.                                               |
| timeout          | integer | optional    | 3              | [1,...] | Timeout for the upstream to send data.                                                   |
| name             | string  | optional    | "kafka logger" |         | A  unique identifier to identity the batch processor.                                     |
| meta_format      | enum    | optional    | "default"      | ["default"，"origin"] | `default`: collect the request information with default JSON way. `origin`: collect the request information with original HTTP request. [example](#examples-of-meta_format)|
| include_req_body | boolean | optional    | false          | [false, true] | Whether to include the request body. false: indicates that the requested body is not included; true: indicates that the requested body is included. Note: if the request body is too big to be kept in the memory, it can't be logged due to Nginx's limitation. |
| include_req_body_expr  | array  | optional    |          |         | When `include_req_body` is true, control the behavior based on the result of the [lua-resty-expr](https://github.com/api7/lua-resty-expr) expression. If present, only log the request body when the result is true. |
| include_resp_body| boolean | optional    | false         | [false, true] | Whether to include the response body. The response body is included if and only if it is `true`. |
| include_resp_body_expr  | array  | optional    |          |         | When `include_resp_body` is true, control the behavior based on the result of the [lua-resty-expr](https://github.com/api7/lua-resty-expr) expression. If present, only log the response body when the result is true. |
| cluster_name     | integer | optional    | 1              | [0,...] | the name of the cluster. When there are two or more kafka clusters, you can specify different names. And this only works with async producer_type.|

The plugin supports the use of batch processors to aggregate and process entries(logs/data) in a batch. This avoids frequent data submissions by the plugin, which by default the batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. For information or custom batch processor parameter settings, see [Batch-Processor](../batch-processor.md#configuration) configuration section.

### examples of meta_format

- **default**:

    ```json
    {
     "upstream": "127.0.0.1:1980",
     "start_time": 1619414294760,
     "client_ip": "127.0.0.1",
     "service_id": "",
     "route_id": "1",
     "request": {
       "querystring": {
         "ab": "cd"
       },
       "size": 90,
       "uri": "/hello?ab=cd",
       "url": "http://localhost:1984/hello?ab=cd",
       "headers": {
         "host": "localhost",
         "content-length": "6",
         "connection": "close"
       },
       "body": "abcdef",
       "method": "GET"
     },
     "response": {
       "headers": {
         "connection": "close",
         "content-type": "text/plain; charset=utf-8",
         "date": "Mon, 26 Apr 2021 05:18:14 GMT",
         "server": "APISIX/2.5",
         "transfer-encoding": "chunked"
       },
       "size": 190,
       "status": 200
     },
     "server": {
       "hostname": "localhost",
       "version": "2.5"
     },
     "latency": 0
    }
    ```

- **origin**:

    ```http
    GET /hello?ab=cd HTTP/1.1
    host: localhost
    content-length: 6
    connection: close

    abcdef
    ```

## Info

The `message` will write to the buffer first.
It will send to the kafka server when the buffer exceed the `batch_max_size`,
or every `buffer_duration` flush the buffer.

In case of success, returns `true`.
In case of errors, returns `nil` with a string describing the error (`buffer overflow`).

### Sample broker list

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

success:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## Metadata

| Name             | Type    | Requirement | Default       | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------------- | ------- | ---------------------------------------------------------------------------------------- |
| log_format       | object  | optional    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | Log format declared as key value pair in JSON format. Only string is supported in the `value` part. If the value starts with `$`, it means to get [APISIX variable](../apisix-variable.md) or [Nginx variable](http://nginx.org/en/docs/varindex.html). |

 Note that **the metadata configuration is applied in global scope**, which means it will take effect on all Route or Service which use kafka-logger plugin.

### Example

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/kafka-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

It is expected to see some logs like that:

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `kafka-logger`.
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
