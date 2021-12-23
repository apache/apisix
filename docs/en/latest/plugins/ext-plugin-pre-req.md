---
title: ext-plugin-pre-req
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
- [**Disable Plugin**](#disable-plugin)

## Name

The `ext-plugin-pre-req` runs specific external plugins in the plugin runner, before
executing most of the builtin Lua plugins.

To know what is the plugin runner, see [external plugin](../external-plugin.md) section.

The result of external plugins execution will affect the behavior of the current request.

## Attributes

| Name      | Type          | Requirement | Default    | Valid                                                                    | Description                                                                                                                                         |
| --------- | ------------- | ----------- | ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| conf     | array        | optional    |              | [{"name": "ext-plugin-A", "value": "{\"enable\":\"feature\"}"}] |     The plugins list which will be executed at the plugin runner with their configuration    |
| allow_degradation              | boolean  | optional                                | false       |                                                                     | Whether to enable plugin degradation when the plugin runner is temporarily unavailable. Allow requests to continue when the value is set to true, default false. |

## How To Enable

Here's an example, enable this plugin on the specified route:

```shell
curl -i http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "ext-plugin-pre-req": {
            "conf" : [
                {"name": "ext-plugin-A", "value": "{\"enable\":\"feature\"}"}
            ]
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## Test Plugin

Use curl to access:

```shell
curl -i http://127.0.0.1:9080/index.html
```

You will see the configured plugin runner will be hit and plugin `ext-plugin-A`
is executed at that side.

## Disable Plugin

When you want to disable this plugin, it is very simple,
you can delete the corresponding json configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

This plugin has been disabled now. It works for other plugins.
