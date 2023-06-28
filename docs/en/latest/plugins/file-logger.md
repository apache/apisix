---
title: file-logger
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - File Logger
description: This document contains information about the Apache APISIX file-logger Plugin.
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

The `file-logger` Plugin is used to push log streams to a specific location.

:::tip

- `file-logger` plugin can count request and response data for individual routes locally, which is useful for [debugging](../debug-mode.md).
- `file-logger` plugin can get [APISIX variables](../apisix-variable.md) and [NGINX variables](http://nginx.org/en/docs/varindex.html), while `access.log` can only use NGINX variables.
- `file-logger` plugin support hot-loaded so that we can change its configuration at any time with immediate effect.
- `file-logger` plugin saves every data in JSON format.
- The user can modify the functions executed by the `file-logger` during the `log phase` to collect the information they want.

:::

## Attributes

| Name | Type   | Required | Description   |
| ---- | ------ | -------- | ------------- |
| path | string | True     | Log file path. |
| log_format | object | False    | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |
| include_resp_body      | boolean | False     | When set to `true` includes the response body in the log file.                                                                                                                                                                |
| include_resp_body_expr | array   | False     | When the `include_resp_body` attribute is set to `true`, use this to filter based on [lua-resty-expr](https://github.com/api7/lua-resty-expr). If present, only logs the response into file if the expression evaluates to `true`. |
| vars        | array[] | False   |  Logs will be recorded only when the rule match is successful. See lua-resty-expr for a list of available expressions.   |

:::tip

`vars` 是由 [`lua-resty-expr`](https://github.com/api7/lua-resty-expr) 的表达式组成的列表，它可以灵活的实现规则之间的 AND/OR 关系，示例如下：：

```json
[
    [
        [ "arg_name","==","jack" ],
        [ "arg_age","==",18 ]
    ],
    [
        [ "arg_name2","==","allen" ]
    ]
]
```

以上示例表示前两个表达式之间的关系是 AND，而前两个和第三个表达式之间的关系是 OR。

:::

## Metadata

You can also set the format of the logs by configuring the Plugin metadata. The following configurations are available:

| Name       | Type   | Required | Default                                                                       | Description                                                                                                                                                                                                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| log_format | object | False    | {"host": "$host", "@timestamp": "$time_iso8601", "client_ip": "$remote_addr"} | Log format declared as key value pairs in JSON format. Values only support strings. [APISIX](../apisix-variable.md) or [Nginx](http://nginx.org/en/docs/varindex.html) variables can be used by prefixing the string with `$`. |

The example below shows how you can configure through the Admin API:

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/file-logger -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Example usage

Now, if you make a request, it will be logged in the path you specified:

```shell
curl -i http://127.0.0.1:9080/hello
```

You will be able to find the `file.log` file in the configured `logs` directory.

## Disable Plugin

To disable the `file-logger` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
