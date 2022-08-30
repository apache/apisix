---
title: request-id
keywords:
  - APISIX
  - API Gateway
  - Request ID
description: This document describes information about the Apache APISIX request-id Plugin, you can use it to track API requests by adding a unique ID to each request.
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

The `request-id` Plugin adds a unique ID to each request proxied through APISIX.

This Plugin can be used to track API requests.

:::note

The Plugin will not add a unique ID if the request already has a header with the configured `header_name`.

:::

## Attributes

| Name                | Type    | Required | Default        | Valid values                    | Description                                                            |
| ------------------- | ------- | -------- | -------------- | ------------------------------- | ---------------------------------------------------------------------- |
| header_name         | string  | False    | "X-Request-Id" |                                 | Header name for the unique request ID.                                 |
| include_in_response | boolean | False    | true           |                                 | When set to `true`, adds the unique request ID in the response header. |
| algorithm           | string  | False    | "uuid"         | ["uuid", "snowflake", "nanoid"] | Algorithm to use for generating the unique request ID.                 |

### Using snowflake algorithm to generate unique ID

:::caution

- When you need to use `snowflake` algorithm, make sure APISIX has the permission to write to the etcd.
- Please read this documentation before deciding to use the snowflake algorithm. Once it is configured, you cannot arbitrarily change the configuration. Failure to do so may result in duplicate IDs.

:::

The `snowflake` algorithm supports flexible configurations to cover a variety of needs. Attributes are as follows:

| Name                  | Type    | Required | Default       | Description                                                                                                                                                                                                                                                                                                                         |
| --------------------- | ------- | -------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| enable                | boolean | False    | false         | When set to `true`, enables the snowflake algorithm.                                                                                                                                                                                                                                                                                |
| snowflake_epoc        | integer | False    | 1609459200000 | Starting timestamp in milliseconds. Default is `2021-01-01T00:00:00Z` and supports to a 69 year time until `2090-09-0715:47:35Z`.                                                                                                                                                                                                   |
| data_machine_bits     | integer | False    | 12            | Maximum number of supported machines (processes) `1 << data_machine_bits`. Corresponds the set of `workIDs` and `dataCenterIDs` in the snowflake definition. Each process is associated to a unique ID. The maximum number of supported processes is `pow(2, data_machine_bits)`. So, for the default value of 12 bits, it is 4096. |
| sequence_bits         | integer | False    | 10            | Maximum number of generated ID per millisecond per node `1 << sequence_bits`. Each process generates up to 1024 IDs per millisecond.                                                                                                                                                                                                |
| data_machine_ttl      | integer | False    | 30            | Valid time in seconds of registration of `data_machine` in etcd.                                                                                                                                                                                                                                                                    |
| data_machine_interval | integer | False    | 10            | Time in seconds between `data_machine` renewals in etcd.                                                                                                                                                                                                                                                                            |

To use the snowflake algorithm, you have to enable it first on your configuration file `conf/config.yaml`:

```yaml title="conf/config.yaml"
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

## Enabling the Plugin

The example below enables the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Example usage

Once you have configured the Plugin as shown above, APISIX will create a unique ID for each request you make:

```shell
curl -i http://127.0.0.1:9080/hello
```

```shell
HTTP/1.1 200 OK
X-Request-Id: fe32076a-d0a5-49a6-a361-6c244c1df956
```

## Disable Plugin

To disable the `request-id` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
