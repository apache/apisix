---
title: http-logger
keywords:
  - APISIX
  - API 网关
  - Plugin
  - HTTP Logger
description: This document contains information about the Apache APISIX http-logger Plugin. Using this Plugin, you can push APISIX log data to HTTP or HTTPS servers.
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

The `http-logger` Plugin is used to push log data requests to HTTP/HTTPS servers.

This will allow the ability to send log data requests as JSON objects to monitoring tools and other HTTP servers.

## Attributes

| Name                   | Type    | Required | Default       | Valid values         | Description                                                                                                                                                                                                              |
| ---------------------- | ------- | -------- | ------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| uri                    | string  | True     |               |                      | URI of the HTTP/HTTPS server.                                                                                                                                                                                            |
| auth_header            | string  | False    |               |                      | Authorization headers if required.                                                                                                                                                                                       |
| timeout                | integer | False    | 3             | [1,...]              | Time to keep the connection alive for after sending a request.                                                                                                                                                           |
| log_format | object | False    |      |               | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |
| include_req_body       | boolean | False    | false         | [false, true]        | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to Nginx's limitations.                                                         |
| include_resp_body      | boolean | False    | false         | [false, true]        | When set to `true` includes the response body in the log.                                                                                                                                                                |
| include_resp_body_expr | array   | False    |               |                      | When the `include_resp_body` attribute is set to `true`, use this to filter based on [lua-resty-expr](https://github.com/api7/lua-resty-expr). If present, only logs the response if the expression evaluates to `true`. |
| concat_method          | string  | False    | "json"        | ["json", "new_line"] | Sets how to concatenate logs. When set to `json`, uses `json.encode` for all pending logs and when set to `new_line`, also uses `json.encode` but uses the newline (`\n`) to concatenate lines.                          |
| ssl_verify             | boolean | False    | false         | [false, true]        | When set to `true` verifies the SSL certificate.                                                                                                                                                                         |

:::note

This Plugin supports using batch processors to aggregate and process entries (logs/data) in a batch. This avoids the need for frequently submitting the data. The batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. See [Batch Processor](../batch-processor.md#configuration) for more information or setting your custom configuration.

:::

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |

:::info IMPORTANT

Configuring the Plugin metadata is global in scope. This means that it will take effect on all Routes and Services which use the `http-logger` Plugin.

:::

The example below shows how you can configure through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/http-logger \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Enabling the Plugin

The example below shows how you can enable the Plugin on a specific Route:

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
      "plugins": {
            "http-logger": {
                "uri": "http://mockbin.org/bin/:ID"
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

As an example the [mockbin](http://mockbin.org/bin/create) server is used for mocking an HTTP server to see the logs produced by APISIX.

## Example usage

Now, if you make a request to APISIX, it will be logged in your mockbin server:

```shell
curl -i http://127.0.0.1:9080/hello
```

## Disable Plugin

To disable this Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
