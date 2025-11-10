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
| log_format       | False    | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| project           | True     | Project name in Alibaba Cloud log service. Create SLS before using this Plugin.                                                                                                                                                                     |
| logstore          | True     | logstore name in Ali Cloud log service. Create SLS before using this Plugin.                                                                                                                                                                    |
| access_key_id     | True     | AccessKey ID in Alibaba Cloud. See [Authorization](https://www.alibabacloud.com/help/en/log-service/latest/create-a-ram-user-and-authorize-the-ram-user-to-access-log-service) for more details.                                                                     |
| access_key_secret | True     | AccessKey Secret in Alibaba Cloud. See [Authorization](https://www.alibabacloud.com/help/en/log-service/latest/create-a-ram-user-and-authorize-the-ram-user-to-access-log-service) for more details.                                                                 |
| include_req_body  | True     | When set to `true`, includes the request body in the log.                                                                                                                                                                                       |
| include_req_body_expr | No      | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                          |
| include_resp_body  | No  | When set to `true` includes the response body in the log.                                                                                                        |
| include_resp_body_expr | No  |  Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                        |
| name              | False    | Unique identifier for the batch processor. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                                                                                                                                                                                                      |

NOTE: `encrypt_fields = {"access_key_secret"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### Example of default log format

```json
{
    "route_conf": {
        "host": "100.100.99.135",
        "buffer_duration": 60,
        "timeout": 30000,
        "include_req_body": false,
        "logstore": "your_logstore",
        "log_format": {
            "vip": "$remote_addr"
        },
        "project": "your_project",
        "inactive_timeout": 5,
        "access_key_id": "your_access_key_id",
        "access_key_secret": "your_access_key_secret",
        "batch_max_size": 1000,
        "max_retry_count": 0,
        "retry_delay": 1,
        "port": 10009,
        "name": "sls-logger"
    },
    "data": "<46>1 2024-01-06T03:29:56.457Z localhost apisix 28063 - [logservice project=\"your_project\" logstore=\"your_logstore\" access-key-id=\"your_access_key_id\" access-key-secret=\"your_access_key_secret\"] {\"vip\":\"127.0.0.1\",\"route_id\":\"1\"}\n"
}
```

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    |  | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `sls-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/sls-logger -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr",
        "request": { "method": "$request_method", "uri": "$request_uri" },
        "response": { "status": "$status" }
    }
}'
```

With this configuration, your logs would be formatted as shown below:

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","request":{"method":"GET","uri":"/hello"},"response":{"status":200},"route_id":"1"}
```

## Enable Plugin

The example below shows how you can configure the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
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
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
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
