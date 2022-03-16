---
title: file-logger
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

`file-logger` is a plugin that pushes a stream of log data to a specified location. For example, the output path can be customized: `logs/file.log`.

## Attributes

| Name             | Type    | Requirement | Default        | Valid  | Description                                             |
| ---------------- | ------- | ------ | ------------- | ------- | ------------------------------------------------ |
| path              | string  | required   |               |         | Customise the output file path                   |

## How To Enable

This is an example of how to enable the `file-logger` plugin for a specific route.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "plugins": {
    "file-logger": {
      "path": "logs/file.log"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:9001": 1
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

You can then find the `file.log` file in the corresponding `logs` directory.

## Metadata

| Name             | Type    | Requirement | Default       | Valid   | Description                                                                              |
| ---------------- | ------- | ----------- | ------------- | ------- | ---------------------------------------------------------------------------------------- |
| log_format       | object  | optional    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} |         | Log format declared as key value pair in JSON format. Only string is supported in the `value` part. If the value starts with `$`, it means to get [APISIX variable](../apisix-variable.md) or [Nginx variable](http://nginx.org/en/docs/varindex.html). |

### Example

```shell
curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/file-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

Remove the corresponding json configuration in the plugin configuration to disable the `file-logger`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "methods": ["GET"],
  "uri": "/hello",
  "plugins": {},
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:9001": 1
    }
  }
}'
```
