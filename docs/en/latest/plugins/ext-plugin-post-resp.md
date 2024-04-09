---
title: ext-plugin-post-resp
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ext-plugin-post-resp
description: This document contains information about the Apache APISIX ext-plugin-post-resp Plugin.
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

The `ext-plugin-post-resp` Plugin is for running specific external Plugins in the Plugin Runner before executing the built-in Lua Plugins.

The `ext-plugin-post-resp` plugin will be executed after the request gets a response from the upstream.

This plugin uses [lua-resty-http](https://github.com/api7/lua-resty-http) library under the hood to send requests to the upstream, due to which the [proxy-control](./proxy-control.md), [proxy-mirror](./proxy-mirror.md), and [proxy-cache](./proxy-cache.md) plugins are not available to be used alongside this plugin. Also, [mTLS Between APISIX and Upstream](../mtls.md#mtls-between-apisix-and-upstream) is not yet supported.

See [External Plugin](../external-plugin.md) to learn more.

:::note

Execution of External Plugins will affect the response of the current request.

:::

## Attributes

| Name              | Type    | Required | Default | Valid values                                                    | Description                                                                                                            |
|-------------------|---------|----------|---------|-----------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| conf              | array   | False    |         | [{"name": "ext-plugin-A", "value": "{\"enable\":\"feature\"}"}] | List of Plugins and their configurations to be executed on the Plugin Runner.                                          |
| allow_degradation | boolean | False    | false   |                                                                 | Sets Plugin degradation when the Plugin Runner is not available. When set to `true`, requests are allowed to continue. |

## Enable Plugin

The example below enables the `ext-plugin-post-resp` Plugin on a specific Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "ext-plugin-post-resp": {
            "conf" : [
                {"name": "ext-plugin-A", "value": "{\"enable\":\"feature\"}"}
            ]
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## Example usage

Once you have configured the External Plugin as shown above, you can make a request to execute the Plugin:

```shell
curl -i http://127.0.0.1:9080/index.html
```

This will reach the configured Plugin Runner and the `ext-plugin-A` will be executed.

## Delete Plugin

To remove the `ext-plugin-post-resp` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
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
