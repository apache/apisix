---
title: http-logger
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

`http-logger` is a plugin which push Log data requests to HTTP/HTTPS servers.

This will provide the ability to send Log data requests as JSON objects to Monitoring tools and other HTTP servers.

## Attributes

| Name                   | Type    | Required | Default       | Valid values         | Description                                                                                                                                                                                                              |
| ---------------------- | ------- | -------- | ------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| uri                    | string  | True     |               |                      | URI of the HTTP/HTTPS server.                                                                                                                                                                                            |
| auth_header            | string  | False    |               |                      | Authorization headers if required.                                                                                                                                                                                       |
| timeout                | integer | False    | 3             | [1,...]              | Time to keep the connection alive for after sending a request.                                                                                                                                                           |
| name                   | string  | False    | "http logger" |                      | Unique identifier to identify the logger.                                                                                                                                                                                |
| include_req_body       | boolean | False    | false         | [false, true]        | When set to `true` includes the request body in the log. If the request body is too big to be kept in the memory, it can't be logged due to Nginx's limitations.                                                         |
| include_resp_body      | boolean | False    | false         | [false, true]        | When set to `true` includes the response body in the log.                                                                                                                                                                |
| include_resp_body_expr | array   | False    |               |                      | When the `include_resp_body` attribute is set to `true`, use this to filter based on [lua-resty-expr](https://github.com/api7/lua-resty-expr). If present, only logs the response if the expression evaluates to `true`. |
| concat_method          | string  | False    | "json"        | ["json", "new_line"] | Sets how to concatenate logs. When set to `json`, uses `json.encode` for all pending logs and when set to `new_line`, also uses `json.encode` but uses the newline (`\n`) to concatenate lines.                          |
| ssl_verify             | boolean | False    | false         | [false, true]        | When set to `true` verifies the SSL certificate.                                                                                                                                                                         |
The plugin supports the use of batch processors to aggregate and process entries(logs/data) in a batch. This avoids frequent data submissions by the plugin, which by default the batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. For information or custom batch processor parameter settings, see [Batch-Processor](../batch-processor.md#configuration) configuration section.

## How To Enable

The following is an example of how to enable the `http-logger` for a specific route. You could generate a mock HTTP server at [mockbin](http://mockbin.org/bin/create) to view the logs.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

 Note that **the metadata configuration is applied in global scope**, which means it will take effect on all Route or Service which use http-logger plugin.

### Example

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/http-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "log_format": {
        "host": "$host",
        "@timestamp": "$time_iso8601",
        "client_ip": "$remote_addr"
    }
}'
```

It is expected to see some logs like that:

```shell
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
{"host":"localhost","@timestamp":"2020-09-23T19:05:05-04:00","client_ip":"127.0.0.1","route_id":"1"}
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `http-logger`.
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
