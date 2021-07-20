---
title: error-log-logger
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
- [**How To Enable And Disable**](#how-to-enable-and-disable)
- [**How to set the SkyWalking Receiver**](#how-to-set-the-tcp-server-address)

## Name

`error-log-skywalking-logger` is a plugin which pushes the log data of APISIX's error.log to Apache SkyWalking over HTTP.

This plugin will provide the ability to send the log data which selected by the level to SkyWalking OAP server.

This plugin provides the ability as a batch to push the log data to your SkyWalking OAP server. If not receive the log data, don't worry, it will automatically send the logs after the timer function expires in our Batch Processor.

For more info on Batch-Processor in Apache APISIX please refer.
[Batch-Processor](../batch-processor.md)

## Attributes

| Name             | Type    | Requirement | Default | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------- | ------- | ---------------------------------------------------------------------------------------- |
| endpoint         | string  | required    |         |         | the http endpoint of Skywalking, for example: http://127.0.0.1:12800/v3/logs |
| service_name     | string  | optional    | "APISIX" |        | service name for skywalking reporter  |
| service_instance_name | string |optional | "APISIX Instance Name" | |service instance name for skywalking reporter，  set it to `$hostname` to get local hostname directly.|
| level            | string  | optional    | WARN    |         | The filter's log level, default warn, choose the level in ["STDERR", "EMERG", "ALERT", "CRIT", "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"], the value ERR equals ERROR.         |
| batch_max_size   | integer | optional    | 1000          | [1,...] | Set the maximum number of logs sent in each batch. When the number of logs reaches the set maximum, all logs will be automatically pushed to the `SkyWalking OAP Server`. |
| inactive_timeout | integer | optional    | 5             | [1,...] | The maximum time to refresh the buffer (in seconds). When the maximum refresh time is reached, all logs will be automatically pushed to the `HTTP/HTTPS` service regardless of whether the number of logs in the buffer reaches the maximum number set. |
| buffer_duration  | integer | optional    | 60            | [1,...] | Maximum age in seconds of the oldest entry in a batch before the batch must be processed.|
| max_retry_count  | integer | optional    | 0             | [0,...] | Maximum number of retries before removing from the processing pipe line.                 |
| retry_delay      | integer | optional    | 1             | [0,...] | Number of seconds the process execution should be delayed if the execution fails.        |


## How To Enable And Disable

The error-log-skywalking logger is a global plugin of APISIX.

### Enable plugin

Enable the plug-in `error-log-skywalking-logger` in `conf/config.yaml`, then this plugin can work fine.
It does not need to be bound in any route or service.

Here is an example of `conf/config.yaml`:

```yaml
plugins:                          # plugin list
  ... ...
  - request-id
  - hmac-auth
  - api-breaker
  - error-log-skywalking-logger              # enable plugin `error-log-skywalking-logger
```

### Disable plugin

Remove or comment out the plugin `error-log-skywalking-logger` from `conf/config.yaml`.

```yaml
plugins:                          # plugin list
  ... ...
  - request-id
  - hmac-auth
  - api-breaker
  #- error-log-skywalking-logger              # enable plugin `error-log-skywalking-logger
```

## How to set the TCP server address

Step: update the attributes of the plugin

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/error-log-skywalking-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "endpoint": "http://127.0.0.1:12800/v3/logs",
  "inactive_timeout": 1
}'
```
