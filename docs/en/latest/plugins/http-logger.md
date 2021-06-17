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

## Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Metadata**](#metadata)
- [**Disable Plugin**](#disable-plugin)

## Name

`http-logger` is a plugin which push Log data requests to HTTP/HTTPS servers.

This will provide the ability to send Log data requests as JSON objects to Monitoring tools and other HTTP servers.

## Attributes

| Name             | Type    | Requirement | Default       | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------------- | ------- | ---------------------------------------------------------------------------------------- |
| uri              | string  | required    |               |         | The URI of the `HTTP/HTTPS` server.                                                      |
| auth_header      | string  | optional    | ""            |         | Any authorization headers.                                                               |
| timeout          | integer | optional    | 3             | [1,...] | Time to keep the connection alive after sending a request.                               |
| name             | string  | optional    | "http logger" |         | A unique identifier to identity the logger.                                              |
| batch_max_size   | integer | optional    | 1000          | [1,...] | Set the maximum number of logs sent in each batch. When the number of logs reaches the set maximum, all logs will be automatically pushed to the `HTTP/HTTPS` service. |
| inactive_timeout | integer | optional    | 5             | [1,...] | The maximum time to refresh the buffer (in seconds). When the maximum refresh time is reached, all logs will be automatically pushed to the `HTTP/HTTPS` service regardless of whether the number of logs in the buffer reaches the maximum number set. |
| buffer_duration  | integer | optional    | 60            | [1,...] | Maximum age in seconds of the oldest entry in a batch before the batch must be processed.|
| max_retry_count  | integer | optional    | 0             | [0,...] | Maximum number of retries before removing from the processing pipe line.                 |
| retry_delay      | integer | optional    | 1             | [0,...] | Number of seconds the process execution should be delayed if the execution fails.        |
| include_req_body | boolean | optional    | false         | [false, true] | Whether to include the request body. false: indicates that the requested body is not included; true: indicates that the requested body is included. |
| concat_method    | string  | optional    | "json"        | ["json", "new_line"] | Enum type: `json` and `new_line`. **json**: use `json.encode` for all pending logs. **new_line**: use `json.encode` for each pending log and concat them with "\n" line. |

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
| log_format       | object  | optional    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | Log format declared as JSON object. Only string is supported in the `value` part. If the value starts with `$`, it means to get `APISIX` variables or [Nginx variable](http://nginx.org/en/docs/varindex.html). |

 Note that the metadata configuration is applied in global scope, which means it will take effect on all Route or Service which use http-logger plugin.

**APISIX Variables**

|   Variable Name  |      Description        | Usage Example  |
|------------------|-------------------------|----------------|
| route_id         | id of `route`          | $route_id      |
| route_name       | name of `route`        | $route_name    |
| service_id       | id of `service`        | $service_id    |
| service_name     | name of `service`      | $service_name  |
| consumer_name    | username of `consumer` | $consumer_name |

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
$ curl http://127.0.0.1:2379/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
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
