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

## Description

`error-log-logger` is a plugin which pushes the log data of APISIX's `error.log` to TCP servers or [Apache SkyWalking](https://skywalking.apache.org/).

This plugin will provide the ability to send the log data which selected by the level to Monitoring tools and other TCP servers, and SkyWalking over HTTP.

This plugin provides the ability as a batch to push the log data to your external TCP servers or monitoring tools. If not receive the log data, don't worry, it will automatically send the logs after the timer function expires in our Batch Processor.

For more info on Batch-Processor in Apache APISIX please refer.
[Batch-Processor](../batch-processor.md)

## Attributes

| Name                             | Type    | Requirement | Default                        | Valid   | Description                                                                                          |
| -------------------------------- | ------- | ----------- | ------------------------------ | ------- | ---------------------------------------------------------------------------------------------------- |
| tcp.host                         | string  | required    |                                |         | IP address or the Hostname of the TCP server.                                                        |
| tcp.port                         | integer | required    |                                | [0,...] | Target upstream port.                                                                                |
| tcp.tls                          | boolean | optional    | false                          |         | Control whether to perform SSL verification.                                                         |
| tcp.tls_server_name              | string  | optional    |                                |         | The server name for the new TLS extension  SNI.                                                      |
| skywalking.endpoint_addr         | string  | optional   | http://127.0.0.1:12900/v3/logs |         | the http endpoint of Skywalking.                                                                     |
| skywalking.service_name          | string  | optional    | APISIX                         |         | service name for skywalking reporter                                                                 |
| skywalking.service_instance_name | String  | optional    | APISIX Instance Name           |         | Service instance name for skywalking reporter, set it to `$hostname` to get local hostname directly. |
| clickhouse.endpoint_addr         | String  | optional   | http://127.0.0.1:8213          |          |  clickhouse HTTP endpoint, default http://127.0.0.1:8213                    |
| clickhouse.user                  | String  | optional   | default                        |          |  clickhouse user                                                           |
| clickhouse.password              | String  | optional   |                                |          |  clickhouse password                                                          |
| clickhouse.database              | String  | optional   |                                |          |  clickhouse for error log DB name                                             |
| clickhouse.logtable              | String  | optional   |                                |          |  clickhouse for error log table name                                            |
| host                             | string  | optional    |                                |         | (`Deprecated`, use `tcp.host` instead) IP address or the Hostname of the TCP server.               |
| port                             | integer | optional    |                                | [0,...] | (`Deprecated`, use `tcp.port` instead) Target upstream port.                                       |
| tls                              | boolean | optional    | false                          |         | (`Deprecated`, use `tcp.tls` instead) Control whether to perform SSL verification.                 |
| tls_server_name                  | string  | optional    |                                |         | (`Deprecated`, use `tcp.tls_server_name` instead) The server name for the new TLS extension SNI.   |
| timeout                          | integer | optional    | 3                              | [1,...] | Timeout for the upstream to connect and send, unit: second.                                          |
| keepalive                        | integer | optional    | 30                             | [1,...] | Time for keeping the cosocket alive, unit: second.                                                   |
| level                            | string  | optional    | WARN                           |         | The filter's log level, default warn, choose the level in ["STDERR", "EMERG", "ALERT", "CRIT", "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"], the value ERR equals ERROR.         |

The plugin supports the use of batch processors to aggregate and process entries(logs/data) in a batch. This avoids frequent data submissions by the plugin, which by default the batch processor submits data every `5` seconds or when the data in the queue reaches `1000`. For information or custom batch processor parameter settings, see [Batch-Processor](../batch-processor.md#configuration) configuration section.

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
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/error-log-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "tcp": {
    "host": "127.0.0.1",
    "port": 1999
  },
  "inactive_timeout": 1
}'
```

## How to set the SkyWalking OAP server address

Step: update the attributes of the plugin

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/error-log-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "skywalking": {
    "endpoint_addr":"http://127.0.0.1:12800/v3/logs"
  },
  "inactive_timeout": 1
}'
```

## How to set the clickhouse

The plugin sends the error log as a string to the `data` field of the clickhouse table.
*TODO Here save error log as a whole string to clickhouse 'data' column. We will add more columns in the future.*
Step: update the attributes of the plugin

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/error-log-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "clickhouse": {
      "user": "default",
      "password": "a",
      "database": "error_log",
      "logtable": "t",
      "endpoint_addr": "http://127.0.0.1:8123"
  }
}'
```
