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

- [中文](../zh-cn/plugins/error-log-logger.md)

# Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable And Disable**](#how-to-enable-and-disable)
- [**How To Update**](#how-to-update)

## Name

`error-log-logger` is a plugin which pushes the log data of APISIX's error.log to TCP servers.

This plugin will provide the ability to send the log data which selected by the level to Monitoring tools and other TCP servers.

This plugin provides the ability as a batch to push the log data to your external TCP servers. If not receive the log data, don't worry, it will automatically send the logs after the timer function expires in our Batch Processor.

For more info on Batch-Processor in Apache APISIX please refer.
[Batch-Processor](../batch-processor.md)

## Attributes

| Name             | Type    | Requirement | Default | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------- | ------- | ---------------------------------------------------------------------------------------- |
| host             | string  | required    |         |         | IP address or the Hostname of the TCP server.                                            |
| port             | integer | required    |         | [0,...] | Target upstream port.                                                                    |
| timeout          | integer | optional    | 3       | [1,...] | Timeout for the upstream to connect and send, unit: second.                                                   |
| keepalive        | integer | optional    | 30      | [1,...] | Time for keeping the cosocket alive, unit: second.                                                   |
| level            | string  | optional    | WARN    |         | The filter's log level, default warn, choose the level in ["STDERR", "EMERG", "ALERT", "CRIT", "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"], the value ERR equals ERROR.         |
| tls              | boolean | optional    | false   |         | Control whether to perform SSL verification                                              |
| tls_server_name  | string  | optional    |         |         | The server name for the new TLS extension  SNI                                                            |
| batch_max_size   | integer | optional    | 1000    | [1,...] | Max size of each batch                                                                   |
| inactive_timeout | integer | optional    | 3       | [1,...] | Maximum age in seconds when the buffer will be flushed if inactive                       |
| buffer_duration  | integer | optional    | 60      | [1,...] | Maximum age in seconds of the oldest entry in a batch before the batch must be processed |
| max_retry_count  | integer | optional    | 0       | [0,...] | Maximum number of retries before removing from the processing pipe line                  |
| retry_delay      | integer | optional    | 1       | [0,...] | Number of seconds the process execution should be delayed if the execution fails         |

## How To Enable And Disable

The error-log-logger is a global plugin of APISIX.

### Enable plugin

Enable the plug-in `error-log-logger` in `conf/config.yaml`, then this plugin can work fine.
It does not need to be bound in any route or service.

Here is an example of `conf/config.yaml`:

```yaml
plugins:                          # plugin list
  ... ...
  - request-id
  - hmac-auth
  - api-breaker
  - error-log-logger              # enable plugin `error-log-logger
```

### Disable plugin

Remove or comment out the plugin `error-log-logger` from `conf/config.yaml`.

```yaml
plugins:                          # plugin list
  ... ...
  - request-id
  - hmac-auth
  - api-breaker
  #- error-log-logger              # enable plugin `error-log-logger
```

## How to set the TCP server address

Step: update the attributes of the plugin

```shell
curl http://127.0.0.1:9080//apisix/admin/plugin_metadata/error-log-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "host": "127.0.0.1",
  "port": 1999,
  "inactive_timeout": 1
}'
```
