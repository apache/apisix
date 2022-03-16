---
title: clickhouse-logger
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

`clickhouse-logger` is a plugin which push Log data requests to clickhouse.

## Attributes

| Name            | Type    | Requirement  | Default         | Valid  | Description                                             |
|-----------------|---------| ------ | ------------- | ------- | ------------------------------------------------ |
| endpoint_addr   | string  | required   |               |         | The `clickhouse` endpoint.                  |
| database        | string  | required   |               |         | The DB name to store log.                   |
| logtable        | string  | required   |               |         | The table name.                             |
| user            | string  | required   |               |         | clickhouse user.                             |
| password        | string  | required   |               |         | clickhouse password.                         |
| timeout         | integer | optional   | 3             | [1,...] | Time to keep the connection alive after sending a request.                   |
| name            | string  | optional   | "clickhouse logger" |         | A unique identifier to identity the logger.                             |
| ssl_verify      | boolean | optional   | true          | [true,false] | verify ssl.             |

The plugin supports the use of batch processors to aggregate and process entries(logs/data) in a batch. This avoids frequent data submissions by the plugin, which by default the batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. For information or custom batch processor parameter settings, see [Batch-Processor](../batch-processor.md#configuration) configuration section.

## How To Enable

The following is an example of how to enable the `clickhouse-logger` for a specific route.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "clickhouse-logger": {
                "user": "default",
                "password": "a",
                "database": "default",
                "logtable": "test",
                "endpoint_addr": "http://127.0.0.1:8123"
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

## Metadata

| Name             | Type    | Requirement | Default       | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------------- | ------- | ---------------------------------------------------------------------------------------- |
| log_format       | object  | optional    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | Log format declared as key value pair in JSON format. Only string is supported in the `value` part. If the value starts with `$`, it means to get [APISIX variable](../apisix-variable.md) or [Nginx variable](http://nginx.org/en/docs/varindex.html). |

 Note that **the metadata configuration is applied in global scope**, which means it will take effect on all Route or Service which use clickhouse-logger plugin.

### Example

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/clickhouse-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

create clickhouse log table

```sql
CREATE TABLE default.test (
  `host` String,
  `client_ip` String,
  `route_id` String,
  `@timestamp` String,
   PRIMARY KEY(`@timestamp`)
) ENGINE = MergeTree()
```

On clickhouse run `select * from default.test;`, will got below row:

```
┌─host──────┬─client_ip─┬─route_id─┬─@timestamp────────────────┐
│ 127.0.0.1 │ 127.0.0.1 │ 1        │ 2022-01-17T10:03:10+08:00 │
└───────────┴───────────┴──────────┴───────────────────────────┘
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `clickhouse-logger`.
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
