---
title: sls-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - SLS Logger
  - Alibaba Cloud Log Service
description: This document contains information about the Apache APISIX sls-logger Plugin.
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

The `sls-logger` Plugin is used to push logs to [Alibaba Cloud log Service](https://www.alibabacloud.com/help/en/log-service/latest/use-the-syslog-protocol-to-upload-logs) using [RF5424](https://tools.ietf.org/html/rfc5424).

It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name              | Required | Description                                                                                                                                                                                                                                     |
|-------------------|----------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| host              | True     | IP address or the hostname of the TCP server. See [Alibaba Cloud log service documentation](https://www.alibabacloud.com/help/en/log-service/latest/endpoints) for details. Use IP address instead of domain. |
| port              | True     | Target upstream port. Defaults to `10009`.                                                                                                                                                                                                      |
| timeout           | False    | Timeout for the upstream to send data.                                                                                                                                                                                                          |
| log_format       | False    | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |
| project           | True     | Project name in Alibaba Cloud log service. Create SLS before using this Plugin.                                                                                                                                                                     |
| logstore          | True     | logstore name in Ali Cloud log service. Create SLS before using this Plugin.                                                                                                                                                                    |
| access_key_id     | True     | AccessKey ID in Alibaba Cloud. See [Authorization](https://www.alibabacloud.com/help/en/log-service/latest/create-a-ram-user-and-authorize-the-ram-user-to-access-log-service) for more details.                                                                     |
| access_key_secret | True     | AccessKey Secret in Alibaba Cloud. See [Authorization](https://www.alibabacloud.com/help/en/log-service/latest/create-a-ram-user-and-authorize-the-ram-user-to-access-log-service) for more details.                                                                 |
| include_req_body  | True     | When set to `true`, includes the request body in the log.                                                                                                                                                                                       |
| name              | False    | Unique identifier for the batch processor.                                                                                                                                                                                                      |

NOTE: `encrypt_fields = {"access_key_secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default | Description                                                                                                                                                                                                                    |
|------------|--------|----------|---------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format | object | False    |         | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `sls-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/sls-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

With this configuration, your logs would be formatted as shown below:

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## Enable Plugin

The example below shows how you can configure the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "sls-logger": {
            "host": "100.100.99.135",
            "port": 10009,
            "project": "your_project",
            "logstore": "your_logstore",
            "access_key_id": "your_access_key_id",
            "access_key_secret": "your_access_key_secret",
            "timeout": 30000
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

## Example usage

Now, if you make a request to APISIX, it will be logged in your Ali Cloud log server:

```shell
curl -i http://127.0.0.1:9080/hello
```

Now if you check your Ali Cloud log server, you will be able to see the logs:

![sls logger view](../../../assets/images/plugin/sls-logger-1.png "sls logger view")

## Delete Plugin

To remove the `sls-logger` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

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
