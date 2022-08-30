---
title: splunk-hec-logging
keywords:
  - APISIX
  - Plugin
  - Splunk HTTP Event Collector
  - splunk-hec-logging
description: This document contains information about the Apache APISIX splunk-hec-logging Plugin.
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

The `splunk-hec-logging` Plugin is used to forward logs to [Splunk HTTP Event Collector (HEC)](https://docs.splunk.com/Documentation/Splunk/8.2.6/Data/UsetheHTTPEventCollector) for analysis and storage.

When the Plugin is enabled, APISIX will serialize the request context information to [Splunk Event Data format](https://docs.splunk.com/Documentation/Splunk/latest/Data/FormateventsforHTTPEventCollector#Event_metadata) and submit it to the batch queue. When the maximum batch size is exceeded, the data in the queue is pushed to Splunk HEC. See [batch processor](../batch-processor.md) for more details.

## Attributes

| Name             | Required | Default | Description                                                                                                                                                                      |
|------------------|----------|---------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| endpoint         | True     |         | Splunk HEC endpoint configurations.                                                                                                                                              |
| endpoint.uri     | True     |         | Splunk HEC event collector API endpoint.                                                                                                                                         |
| endpoint.token   | True     |         | Splunk HEC authentication token.                                                                                                                                                 |
| endpoint.channel | False    |         | Splunk HEC send data channel identifier. Read more: [About HTTP Event Collector Indexer Acknowledgment](https://docs.splunk.com/Documentation/Splunk/8.2.3/Data/AboutHECIDXAck). |
| endpoint.timeout | False    | 10      | Splunk HEC send data timeout in seconds.                                                                                                                                         |
| ssl_verify       | False    | true    | When set to `true` enables SSL verification as per [OpenResty docs](https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake).                                          |

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Enabling the Plugin

### Full configuration

The example below shows a complete configuration of the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins":{
        "splunk-hec-logging":{
            "endpoint":{
                "uri":"http://127.0.0.1:8088/services/collector",
                "token":"BD274822-96AA-4DA6-90EC-18940FB2414C",
                "channel":"FE0ECFAD-13D5-401B-847D-77833BD77131",
                "timeout":60
            },
            "buffer_duration":60,
            "max_retry_count":0,
            "retry_delay":1,
            "inactive_timeout":2,
            "batch_max_size":10
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    },
    "uri":"/splunk.do"
}'
```

### Minimal configuration

The example below shows a bare minimum configuration of the Plugin on a Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins":{
        "splunk-hec-logging":{
            "endpoint":{
                "uri":"http://127.0.0.1:8088/services/collector",
                "token":"BD274822-96AA-4DA6-90EC-18940FB2414C"
            }
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:1980":1
        }
    },
    "uri":"/splunk.do"
}'
```

## Example usage

Once you have configured the Route to use the Plugin, when you make a request to APISIX, it will be logged in your Splunk server:

```shell
curl -i http://127.0.0.1:9080/splunk.do?q=hello
```

You should be able to login and search these logs from your Splunk dashboard:

![splunk hec search view](../../../assets/images/plugin/splunk-hec-admin-en.png)

## Disable Plugin

To disable the `splunk-hec-logging` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
