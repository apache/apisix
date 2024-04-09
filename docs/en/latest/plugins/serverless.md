---
title: serverless
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Serverless
description: This document contains information about the Apache APISIX serverless Plugin.
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

There are two `serverless` Plugins in APISIX: `serverless-pre-function` and `serverless-post-function`. The former runs at the beginning of the specified phase, while the latter runs at the end of the specified phase.

Both Plugins have the same attributes.

## Attributes

| Name      | Type          | Required | Default    | Valid values                                                                 | Description                                                      |
|-----------|---------------|----------|------------|------------------------------------------------------------------------------|------------------------------------------------------------------|
| phase     | string        | False    | ["access"] | ["rewrite", "access", "header_filter", "body_filter", "log", "before_proxy"] | Phase before or after which the serverless function is executed. |
| functions | array[string] | True     |            |                                                                              | List of functions that are executed sequentially.                |

:::info IMPORTANT

Only Lua functions are allowed here and not other Lua code.

For example, anonymous functions are legal:

```lua
return function()
    ngx.log(ngx.ERR, 'one')
end
```

Closures are also legal:

```lua
local count = 1
return function()
    count = count + 1
    ngx.say(count)
end
```

But code other than functions are illegal:

```lua
local count = 1
ngx.say(count)
```

:::

:::note

From v2.6, `conf` and `ctx` are passed as the first two arguments to a serverless function like regular Plugins.

Prior to v2.12.0, the phase `before_proxy` was called `balancer`. This was updated considering that this method would run after `access` and before the request goes Upstream and is unrelated to `balancer`.

:::

## Enable Plugin

The example below enables the Plugin on a specific Route:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions" : ["return function() ngx.log(ngx.ERR, \"serverless pre function\"); end"]
        },
        "serverless-post-function": {
            "phase": "rewrite",
            "functions" : ["return function(conf, ctx) ngx.log(ngx.ERR, \"match uri \", ctx.curr_req_matched and ctx.curr_req_matched._path); end"]
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

Once you have configured the Plugin as shown above, you can make a request as shown below:

```shell
curl -i http://127.0.0.1:9080/index.html
```

You will find a message "serverless pre-function" and "match uri /index.html" in the error.log.

## Delete Plugin

To remove the `serverless` Plugin, you can delete the corresponding JSON configuration from the Plugin configuration. APISIX will automatically reload and you do not have to restart for this to take effect.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
