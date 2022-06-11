---
title: kafka-logger
keywords:
  - APISIX
  - Plugin
  - Kafka Logger
  - kafka-logger
description: This document contains information about the Apache APISIX kafka-logger Plugin.
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

The `kafka-logger` Plugin is used to push logs as JSON objects to Apache Kafka clusters. It works as a Kafka client driver for the ngx_lua Nginx module.

It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name                   | Type    | Required | Default        | Valid values          | Description                                                                                                                                                                                                                                                                                                                                      |
|------------------------|---------|----------|----------------|-----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| broker_list            | object  | True     |                |                       | List of Kafka brokers (nodes).                                                                                                                                                                                                                                                                                                                   |
| kafka_topic            | string  | True     |                |                       | Target topic to push the logs for organisation.                                                                                                                                                                                                                                                                                                  |
| producer_type          | string  | False    | async          | ["async", "sync"]     | Message sending mode of the producer.                                                                                                                                                                                                                                                                                                            |
| required_acks          | integer | False    | 1              | [0, 1, -1]            | Number of acknowledgements the leader needs to receive for the producer to consider the request complete. This controls the durability of the sent records. The attribute follows the same configuration as the Kafka `acks` attribute. See [Apache Kafka documentation](https://kafka.apache.org/documentation/#producerconfigs_acks) for more. |
| key                    | string  | False    |                |                       | Key used for allocating partitions for messages.                                                                                                                                                                                                                                                                                                 |
| timeout                | integer | False    | 3              | [1,...]               | Timeout for the upstream to send data.                                                                                                                                                                                                                                                                                                           |
| name                   | string  | False    | "kafka logger" |                       | Unique identifier for the batch processor.                                                                                                                                                                                                                                                                                                       |
| meta_format            | enum    | False    | "default"      | ["default"，"origin"] | Format to collect the request information. Setting to `default` collects the information in JSON format and `origin` collects the information with the original HTTP request. See [examples](#meta_format-example) below.                                                                                                                    |
| include_req_body       | boolean | False    | false          | [false, true]         | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to Nginx's limitations.                                                                                                                                                                                 |
| include_req_body_expr  | array   | False    |                |                       | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                          |
| include_resp_body      | boolean | False    | false          | [false, true]         | When set to `true` includes the response body in the log.                                                                                                                                                                                                                                                                                        |
| include_resp_body_expr | array   | False    |                |                       | Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                        |
| cluster_name           | integer | False    | 1              | [0,...]               | Name of the cluster. Used when there are two or more Kafka clusters. Only works if the `producer_type` attribute is set to `async`.                                                                                                                                                                                                              |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### meta_format example

- `default`:

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

- `origin`:

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
