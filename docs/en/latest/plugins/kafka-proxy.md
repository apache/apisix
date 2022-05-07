---
title: kafka-proxy
keywords:
  - APISIX
  - Plugin
  - Kafka
  - consumer
description: This document contains information about the Apache APISIX kafka-proxy Plugin.
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

The `kafka-proxy` plugin can be used to configure advanced parameters for the kafka upstream of Apache APISIX, such as SASL authentication.

## Attributes

| Name              | Type    | Required | Default | Valid values  | Description                       |
|-------------------|---------|----------|---------|---------------|-----------------------------------|
| enable_tls        | boolean | False    | false   |               | Enable TLS for Kafka client       |
| ssl_verify        | boolean | False    | true    |               | Enable TLS certificate validation |
| enable_sasl       | boolean | False    | false   |               | Enable SASL authentication        |
| sasl_username     | string  | False    | ""      |               | SASL authentication username      |
| sasl_password     | string  | False    | ""      |               | SASL authentication passwrod      |

:::note
If SASL authentication is enabled, the `sasl_username` and `sasl_password` must be set.
:::

## Example usage

When we use scheme as the upstream of kafka, we can add kafka authentication configuration to it through this plugin.

```shell
curl -X PUT 'http://127.0.0.1:9080/apisix/admin/routes/r1' \
    -H 'X-API-KEY: <api-key>' \
    -H 'Content-Type: application/json' \
    -d '{
    "uri": "/kafka",
    "plugins": {
        "kafka-proxy": {
            "enable_sasl": true,
            "sasl_username": "user",
            "sasl_password": "pwd"
        }
    },
    "upstream": {
        "nodes": {
            "kafka-server1:9092": 1,
            "kafka-server2:9092": 1,
            "kafka-server3:9092": 1
        },
        "type": "none",
        "scheme": "kafka",
        "tls": {
            "verify": true
        }
    }
}'
```

Now, we can test it by connecting to the `/kafka` endpoint via websocket.

## Disable Plugin

To disable the `kafka-proxy` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.
