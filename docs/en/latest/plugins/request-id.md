---
title: request-id
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
- [**Disable Plugin**](#disable-plugin)

## Name

`request-id` plugin adds a unique ID (UUID) to each request proxied through APISIX. This plugin can be used to track an
API request. The plugin will not add a request id if the `header_name` is already present in the request.

## Attributes

| Name                | Type    | Requirement | Default        | Valid | Description                                                    |
| ------------------- | ------- | ----------- | -------------- | ----- | -------------------------------------------------------------- |
| header_name         | string  | optional    | "X-Request-Id" |       | Request ID header name                                         |
| include_in_response | boolean | optional    | true           |       | Option to include the unique request ID in the response header |
| algorithm           | string  | optional    | "uuid"         | ["uuid", "snowflake"] | ID generation algorithm |

## How To Enable

Create a route and enable the request-id plugin on the route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "request-id": {
            "include_in_response": true
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## Test Plugin

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
X-Request-Id: fe32076a-d0a5-49a6-a361-6c244c1df956
......
```

### Use the snowflake algorithm to generate an ID

> supports using the Snowflake algorithm to generate ID.
> read the documentation first before deciding to use snowflake. Because once the configuration information is enabled, you can not arbitrarily adjust the configuration information. Failure to do so may result in duplicate ID being generated.

The Snowflake algorithm is not enabled by default and needs to be configured in 'conf/config.yaml'.

```yaml
plugin_attr:
  request-id:
    snowflake:
      enable: true
      snowflake_epoc: 1609459200000
      data_machine_bits: 12
      sequence_bits: 10
      data_machine_ttl: 30
      data_machine_interval: 10
```

#### Configuration parameters

| Name                | Type    | Requirement   | Default        |  Valid  | Description                    |
| ------------------- | ------- | ------------- | -------------- | ------- | ------------------------------ |
| enable                     | boolean  | optional   | false          |  | When set it to true, enable the snowflake algorithm.  |
| snowflake_epoc             | integer  | optional   | 1609459200000  |  | Start timestamp (in milliseconds)       |
| data_machine_bits          | integer  | optional   | 12             |  | Maximum number of supported machines (processes) `1 << data_machine_bits` |
| sequence_bits              | integer  | optional   | 10             |  | Maximum number of generated ID per millisecond per node `1 << sequence_bits` |
| data_machine_ttl           | integer  | optional   | 30             |  | Valid time of registration of 'data_machine' in 'etcd' (unit: seconds) |
| data_machine_interval      | integer  | optional   | 10             |  | Time between 'data_machine' renewal in 'etcd' (unit: seconds) |

- `snowflake_epoc` default start time is  `2021-01-01T00:00:00Z`, and it can support `69 year` approximately to `2090-09-0715:47:35Z` according to the default configuration
- `data_machine_bits` corresponds to the set of workIDs and datacEnteridd in the snowflake definition. The plug-in aslocates a unique ID to each process. Maximum number of supported processes is `pow(2, data_machine_bits)`. The default number of `12 bits` is up to `4096`.
- `sequence_bits` defaults to `10 bits` and each process generates up to `1024` ID per second

#### example

> Snowflake supports flexible configuration to meet a wide variety of needs

- Snowflake original configuration

> - Start time 2014-10-20 T15:00:00.000z, accurate to milliseconds. It can last about 69 years
> - supports up to `1024` processes
> - Up to `4096` ID per second per process

```yaml
plugin_attr:
  request-id:
    snowflake:
      enable: true
      snowflake_epoc: 1413817200000
      data_machine_bits: 10
      sequence_bits: 12
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `request-id`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
