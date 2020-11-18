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

- [中文](../zh-cn/plugins/echo.md)

# Summary
- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)


## Name

`echo` is a a useful plugin to help users understand as fully as possible how to develop an APISIX plugin.

This plugin addresses the corresponding functionality in the common phases such as init, rewrite, access, balancer, header filer, body filter and log.

**NOTE: `echo` plugin is written as an example. There are some unhandled cases and you should not use it in the production!**

## Attributes

| Name        | Type   | Requirement | Default | Valid | Description                                  |
| ----------- | ------ | ----------- | ------- | ----- | -------------------------------------------- |
| before_body | string | optional    |         |       | Body before the filter phase.                |
| body        | string | optional    |         |       | Body to replace upstream response.           |
| after_body  | string | optional    |         |       | Body after the modification of filter phase. |
| headers     | object | optional    |         |       | New headers for response                     |
| auth_value  | string | optional    |         |       | Auth value                                   |

At least one of `before_body`, `body`, and `after_body` must be specified.

## How To Enable

The following is an example on how to enable the echo plugin for a specific route.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "plugins": {
        "echo": {
            "before_body": "before the body modification "
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

## Test Plugin

* success:

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
before the body modification hello world
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `echo`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
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
