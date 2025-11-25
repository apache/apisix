---
title: rocketmq-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - RocketMQ Logger
description: This document contains information about the Apache APISIX rocketmq-logger Plugin.
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

The `rocketmq-logger` Plugin provides the ability to push logs as JSON objects to your RocketMQ clusters.

It might take some time to receive the log data. It will be automatically sent after the timer function in the [batch processor](../batch-processor.md) expires.

## Attributes

| Name                   | Type    | Required | Default                                                                       | Valid values         | Description                                                                                                                                                                                                                    |
|------------------------|---------|----------|-------------------------------------------------------------------------------|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| nameserver_list        | object  | True     |                                                                               |                      | List of RocketMQ nameservers.                                                                                                                                                                                                  |
| topic                  | string  | True     |                                                                               |                      | Target topic to push the data to.                                                                                                                                                                                              |
| key                    | string  | False    |                                                                               |                      | Key of the messages.                                                                                                                                                                                                           |
| tag                    | string  | False    |                                                                               |                      | Tag of the messages.                                                                                                                                                                                                           |
| log_format             | object  | False    |  |                      | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| timeout                | integer | False    | 3                                                                             | [1,...]              | Timeout for the upstream to send data.                                                                                                                                                                                         |
| use_tls                | boolean | False    | false                                                                         |                      | When set to `true`, uses TLS.                                                                                                                                                                                                  |
| access_key             | string  | False    | ""                                                                            |                      | Access key for ACL. Setting to an empty string will disable the ACL.                                                                                                                                                           |
| secret_key             | string  | False    | ""                                                                            |                      | secret key for ACL.                                                                                                                                                                                                            |
| name                   | string  | False    | "rocketmq logger"                                                             |                      | Unique identifier for the batch processor. If you use Prometheus to monitor APISIX metrics, the name is exported in `apisix_batch_process_entries`. processor.                                                                                                                                                                                     |
| meta_format            | enum    | False    | "default"                                                                     | ["default"，"origin"] | Format to collect the request information. Setting to `default` collects the information in JSON format and `origin` collects the information with the original HTTP request. See [examples](#meta_format-example) below.      |
| include_req_body       | boolean | False    | false                                                                         | [false, true]        | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to Nginx's limitations.                                                               |
| include_req_body_expr  | array   | False    |                                                                               |                      | Filter for when the `include_req_body` attribute is set to `true`. Request body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.        |
| include_resp_body      | boolean | False    | false                                                                         | [false, true]        | When set to `true` includes the response body in the log.                                                                                                                                                                      |
| include_resp_body_expr | array   | False    |                                                                               |                      | Filter for when the `include_resp_body` attribute is set to `true`. Response body is only logged when the expression set here evaluates to `true`. See [lua-resty-expr](https://github.com/api7/lua-resty-expr) for more.      |

NOTE: `encrypt_fields = {"secret_key"}` is also defined in the schema, which means that the field will be stored encrypted in etcd. See [encrypted storage fields](../plugin-develop.md#encrypted-storage-fields).

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

:::info IMPORTANT

The data is first written to a buffer. When the buffer exceeds the `batch_max_size` or `buffer_duration` attribute, the data is sent to the RocketMQ server and the buffer is flushed.

If the process is successful, it will return `true` and if it fails, returns `nil` with a string with the "buffer overflow" error.

:::

### meta_format example

- default:

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

- origin:

```http
    GET /hello?ab=cd HTTP/1.1
    host: localhost
    content-length: 6
    connection: close

    abcdef
```

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

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                    |
|------------|--------|----------|-------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| log_format | object | False    |  | Log format declared as key-value pairs in JSON. Values support strings and nested objects (up to five levels deep; deeper fields are truncated). Within strings, [APISIX](../apisix-variable.md) or [NGINX](http://nginx.org/en/docs/varindex.html) variables can be referenced by prefixing with `$`. |
| max_pending_entries | integer | False | | Maximum number of pending entries that can be buffered in batch processor before it starts dropping them. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `rocketmq-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/rocketmq-logger -H "X-API-KEY: $admin_key" -X PUT -d '
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

The example below shows how you can enable the `rocketmq-logger` Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/5 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "plugins": {
       "rocketmq-logger": {
           "nameserver_list" : [ "127.0.0.1:9876" ],
           "topic" : "test2",
           "batch_max_size": 1,
           "name": "rocketmq logger"
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

This Plugin also supports pushing to more than one nameserver at a time. You can specify multiple nameserver in the Plugin configuration as shown below:

```json
"nameserver_list" : [
    "127.0.0.1:9876",
    "127.0.0.2:9876"
]
```

## Example usage

Now, if you make a request to APISIX, it will be logged in your RocketMQ server:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Delete Plugin

To remove the `rocketmq-logger` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload, and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
