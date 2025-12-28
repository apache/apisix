---
title: clickhouse-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ClickHouse Logger
description: This document contains information about the Apache APISIX clickhouse-logger Plugin.
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

The `clickhouse-logger` Plugin is used to push logs to [ClickHouse](https://clickhouse.com/) database.

## Attributes

| Name          | Type    | Required | Default             | Valid values | Description                                                    |
|---------------|---------|----------|---------------------|--------------|----------------------------------------------------------------|
| endpoint_addr | Deprecated   | True     |                |              | Use `endpoint_addrs` instead. ClickHouse endpoints.            |
| endpoint_addrs | array  | True     |                     |              | ClickHouse endpoints.                                          |
| database      | string  | True     |                     |              | Name of the database to store the logs.                        |
| logtable      | string  | True     |                     |              | Table name to store the logs.                                  |
| user          | string  | True     |                     |              | ClickHouse username.                                           |
| password      | string  | True     |                     |              | ClickHouse password.                                           |
| timeout       | integer | False    | 3                   | [1,...]      | Time to keep the connection alive for after sending a request. |
| name          | string  | False    | "clickhouse logger" |              | Unique identifier for the logger. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`.                              |
| ssl_verify    | boolean | False    | true                | [true,false] | When set to `true`, verifies SSL.                              |
| log_format       | object  | False    |  |              | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| include_req_body       | boolean | False    | false          | [false, true]         | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to Nginx's limitations.                                                                                                                                                                                 |
| include_req_body_expr  | array   | False    |                |                       | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                          |
| include_resp_body      | boolean | False    | false          | [false, true]         | When set to `true` includes the response body in the log.                                                                                                                                                                                                                                                                                        |
| include_resp_body_expr | array   | False    |                |                       | Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.                                                                                                                        |

NOTE: `encrypt_fields = {"password"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

### Example of default log format

```json
{
    "response": {
        "status": 200,
        "size": 118,
        "headers": {
            "content-type": "text/plain",
            "connection": "close",
            "server": "APISIX/3.7.0",
            "content-length": "12"
        }
    },
    "client_ip": "127.0.0.1",
    "upstream_latency": 3,
    "apisix_latency": 98.999998092651,
    "upstream": "127.0.0.1:1982",
    "latency": 101.99999809265,
    "server": {
        "version": "3.7.0",
        "hostname": "localhost"
    },
    "route_id": "1",
    "start_time": 1704507612177,
    "service_id": "",
    "request": {
        "method": "POST",
        "querystring": {
            "foo": "unknown"
        },
        "headers": {
            "host": "localhost",
            "connection": "close",
            "content-length": "18"
        },
        "size": 110,
        "uri": "/hello?foo=unknown",
        "url": "http://localhost:1984/hello?foo=unknown"
    }
}
```

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False |  | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `clickhouse-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/clickhouse-logger -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

You can use the clickhouse docker image to create a container like so:

```shell
docker run -d -p 8123:8123 -p 9000:9000 -p 9009:9009 --name some-clickhouse-server --ulimit nofile=262144:262144 clickhouse/clickhouse-server
```

Then create a table in your ClickHouse database to store the logs.

```shell
curl -X POST 'http://localhost:8123/' \
--data-binary 'CREATE TABLE default.test (host String, client_ip String, route_id String, service_id String, `@timestamp` String, PRIMARY KEY(`@timestamp`)) ENGINE = MergeTree()' --user default:
```

## Enable Plugin

If multiple endpoints are configured, they will be written randomly.
The example below shows how you can enable the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
      "plugins": {
            "clickhouse-logger": {
                "user": "default",
                "password": "",
                "database": "default",
                "logtable": "test",
                "endpoint_addrs": ["http://127.0.0.1:8123"]
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

Now, if you make a request to APISIX, it will be logged in your ClickHouse database:

```shell
curl -i http://127.0.0.1:9080/hello
```

Now, if you check for the rows in the table, you will get the following output:

```shell
curl 'http://localhost:8123/?query=select%20*%20from%20default.test'
127.0.0.1	127.0.0.1	1		2023-05-08T19:15:53+05:30
```

## Delete Plugin

To remove the `clickhouse-logger` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
