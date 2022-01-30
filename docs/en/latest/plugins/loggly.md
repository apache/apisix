---
title: loggly
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

- [Name](#name)
- [Attributes](#attributes)
- [Metadata](#metadata)
- [How To Enable](#how-to-enable)
  - [Full configuration](#full-configuration)
  - [Minimal configuration](#minimal-configuration)
- [Test Plugin](#test-plugin)
- [Disable Plugin](#disable-plugin)

## Name

The `loggly` plugin is used to forward the request log of `Apache APISIX` to `Loggly by SolarWinds` for analysis and storage. After the plugin is enabled, `Apache APISIX` will obtain request context information in `Log Phase` serialize it into [Loggly Syslog](https://documentation.solarwinds.com/en/success_center/loggly/content/admin/streaming-syslog-without-using-files.htm?cshid=loggly_streaming-syslog-without-using-files) data format which is actually syslog events with [RFC5424](https://datatracker.ietf.org/doc/html/rfc5424) compliant headers and submit it to the batch queue. When the maximum processing capacity of each batch of the batch processing queue or the maximum time to refresh the buffer is triggered, the data in the queue will be submitted to `Loggly` enterprise syslog endpoint.

> At present, APISIX loggly plugin supports sending logs to Loggly server via syslog protocol, support for more event protocols are coming soon.

For more info on Batch-Processor in Apache APISIX please refer to:
[Batch-Processor](../batch-processor.md)

## Attributes

| Name          | Type              | Requirement   | Default                                                                                                                                                                                           | Description                                                                                                                                                                      |
| ----------------------- | ---- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| customer_token           | string     | required      || A unique identifier is used when sending log data to Loggly to ensure that the logs are sent to the right organization account.                                                                                                                                           |
| severity | string (enum) | optional | INFO | Log event severity level (choose between: "DEBUG", "INFO", "NOTICE", "WARNING", "ERR", "CRIT", "ALERT", "EMEGR" ) [case insensitive] |
| tags         | array   | optional      |  | To aid in segmentation & filtering. They are metadata you can set and they will be included with any event that is transmitted to Loggly. |
| include_req_body | boolean | optional    | false          | Whether to include the request body. false: indicates that the requested body is not included; true: indicates that the requested body is included. Note: if the request body is too big to be kept in the memory, it can't be logged due to Nginx's limitation. |
| include_resp_body| boolean | optional    | false         | Whether to include the response body. The response body is included if and only if it is `true`. |
| include_resp_body_expr  | array  | optional    |          | When `include_resp_body` is true, control the behavior based on the result of the [lua-resty-expr](https://github.com/api7/lua-resty-expr) expression. If present, only log the response body when the result is true. |
| max_retry_count     | integer    | optional      | 0                                                                                                                                                                                                 | max number of retries before removing from the processing pipe line                                                                                                              |
| retry_delay        | integer     | optional      | 1                                                                                                                                                                                                 | number of seconds the process execution should be delayed if the execution fails                                                                                                 |
| buffer_duration      | integer   | optional      | 60                                                                                                                                                                                                | max age in seconds of the oldest entry in a batch before the batch must be processed                                                                                             |
| inactive_timeout     | integer   | optional      | 5                                                                                                                                                                                                 | max age in seconds when the buffer will be flushed if inactive                                                                                                                   |
| batch_max_size    | integer      | optional      | 1000                                                                                                                                                                                              | max size of each batch                                                                                                                                                           |

To generate a Customer Token, head over to `<your assigned subdomain>/loggly.com/tokens` or navigate to `Logs > Source Setup > Customer Tokens` to generate a new token.

## Metadata

| Name        | Type    | Requirement |     Default        | Valid         | Description                                                            |
| ----------- | ------  | ----------- |      -------       | -----         | ---------------------------------------------------------------------- |
| host        | string  | optional    |  "logs-01.loggly.com"       |               | The host address endpoint where logs are being sent.                                      |
| port        | integer | optional    |    514            |               | Loggly port (for "syslog" protocol only) to make a connection request.                                         |
| timeout   | integer  | optional    |    5000        |               | Loggly send data request timeout in milliseconds.                                        |
| protocol | string | optional    | "syslog" |  [ "syslog" , "http", "https" ]            | Protocol through which the logs are sent to Loggly from APISIX (currently supported protocol : "syslog", "http", "https") |
| log_format       | object  | optional    | nil |         | Log format declared as key value pair in JSON format. Only string is supported in the `value` part. If the value starts with `$`, it means to get [`APISIX` variables](../apisix-variable.md) or [Nginx variable](http://nginx.org/en/docs/varindex.html). If it is nil or empty object, APISIX generates full log info. |

## How To Enable

The following is an example of how to enable the `loggly` for a specific route.

### Full configuration

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins":{
        "loggly":{
            "customer_token":"0e6fe4bf-376e-40f4-b25f-1d55cb29f5a2",
            "tags":["apisix", "testroute"],
            "severity":"info",
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
            "127.0.0.1:80":1
        }
    },
    "uri":"/index.html"
}'
```

We support [Syslog](https://documentation.solarwinds.com/en/success_center/loggly/content/admin/streaming-syslog-without-using-files.htm), [HTTP/S](https://documentation.solarwinds.com/en/success_center/loggly/content/admin/http-bulk-endpoint.htm) (bulk endpoint) protocols to send log events to Loggly. By default, in APISIX side, the protocol is set to "syslog". It lets you send RFC5424 compliant syslog events with some fine-grained control (log severity mapping based on upstream HTTP response code). But HTTP/S bulk endpoint is great to send larger batches of log events with faster transmission speed. If you wish to update it, just update the metadata

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/loggly -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
   "protocol": "http"
}'
```

### Minimal configuration

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins":{
        "loggly":{
            "customer_token":"0e6fe4bf-376e-40f4-b25f-1d55cb29f5a2",
        }
    },
    "upstream":{
        "type":"roundrobin",
        "nodes":{
            "127.0.0.1:80":1
        }
    },
    "uri":"/index.html"
}'
```

## Test Plugin

* Send request to route configured with the `loggly` plugin

```shell
$ curl -i http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
...
<!DOCTYPE html>
<html>
```

* Login to Loggly Dashboard to search and view

![Loggly Dashboard](../../../assets/images/plugin/loggly-dashboard.png)

## Disable Plugin

Disabling the `loggly` plugin is very simple, just remove the `JSON` configuration corresponding to `loggly`. APISIX plugins are hot loaded, so no need to restart APISIX.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```
