---
title: inspect
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - Inspect
  - Dynamic Lua Debugging
description: This document contains information about the Apache APISIX inspect Plugin.
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

It's useful to set arbitrary breakpoint in any Lua file to inspect the context information,
e.g. print local variables if some condition satisfied.

In this way, you don't need to modify the source code of your project, and just get diagnose information
on demand, i.e. dynamic logging.

This plugin supports setting breakpoints within both interpretd function and jit compiled function.
The breakpoint could be at any position within the function. The function could be global/local/module/ananymous.

## Features

* Set breakpoint at any position
* Dynamic breakpoint
* customized breakpoint handler
* You could define one-shot breakpoint
* Work for jit compiled function
* If function reference specified, then performance impact is only bound to that function (JIT compiled code will not trigger debug hook, so they would run fast even if hook is enabled)
* If all breakpoints deleted, jit could recover

## Operation Graph

![Operation Graph](https://raw.githubusercontent.com/apache/apisix/master/docs/assets/images/plugin/inspect.png)

## API to define hook in hooks file

### require("apisix.inspect.dbg").set_hook(file, line, func, filter_func)

The breakpoint is specified by `file` (full qualified or short file name) and the `line` number.

The `func` specified the scope (which function or global) of jit cache to flush:

* If the breakpoint is related to a module function or
global function, you should set it that function reference, then only the jit cache of that function would
be flushed, and it would not affect other caches to avoid slowing down other parts of the program.

* If the breakpointis related to local function or anonymous function,
then you have to set it to `nil` (because no way to get function reference), which would flush the whole jit cache of Lua vm.

You attach a `filter_func` function to the breakpoint. The function takes the `info` as an argument and returns
true or false to determine whether the breakpoint would be removed. This allows you to set up a one-shot breakpoint
at ease.

The `info` is a hash table which contains below keys:

* `finfo`: `debug.getinfo(level, "nSlf")`
* `uv`: upvalues hash table
* `vals`: local variables hash table

## Attributes

| Name               | Type    | Required | Default | Description                                                                                    |
|--------------------|---------|----------|---------|------------------------------------------------------------------------------------------------|
| delay           | integer | False     | 3 | Time in seconds specifying how often to check the hooks file.                                       |
| hooks_file           | string | False     | "/usr/local/apisix/plugin_inspect_hooks.lua"  | Lua file to define hooks, which could be a link file. Ensure only administrator could write this file, otherwise it may be a security risk. |

## Enable Plugin

Plugin is enabled by default:

```yaml title="apisix/cli/config.lua"
local _M = {
  plugins = {
    "inspect",
    ...
  },
  plugin_attr = {
    inspect = {
      delay = 3,
      hooks_file = "/usr/local/apisix/plugin_inspect_hooks.lua"
    },
    ...
  },
  ...
}
```

## Example usage

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```bash
# create test route
curl http://127.0.0.1:9180/apisix/admin/routes/test_limit_req -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/get",
    "plugins": {
        "limit-req": {
            "rate": 100,
            "burst": 0,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'

# create a hooks file to set a test breakpoint
# Note that the breakpoint is associated with the line number,
# so if the Lua code changes, you need to adjust the line number in the hooks file
cat <<EOF >/usr/local/apisix/example_hooks.lua
local dbg = require "apisix.inspect.dbg"

dbg.set_hook("limit-req.lua", 88, require("apisix.plugins.limit-req").access, function(info)
    ngx.log(ngx.INFO, debug.traceback("foo traceback", 3))
    ngx.log(ngx.INFO, dbg.getname(info.finfo))
    ngx.log(ngx.INFO, "conf_key=", info.vals.conf_key)
    return true
end)

--- more breakpoints could be defined via dbg.set_hook()
--- ...
EOF

# enable the hooks file
ln -sf /usr/local/apisix/example_hooks.lua /usr/local/apisix/plugin_inspect_hooks.lua

# check errors.log to confirm the test breakpoint is enabled
2022/09/01 00:55:38 [info] 2754534#2754534: *3700 [lua] init.lua:29: setup_hooks(): set hooks: err=nil, hooks=["limit-req.lua#88"], context: ngx.timer

# access the test route
curl -i http://127.0.0.1:9080/get

# check errors.log to confirm the test breakpoint is triggered
2022/09/01 00:55:52 [info] 2754534#2754534: *4070 [lua] resty_inspect_hooks.lua:4: foo traceback
stack traceback:
        /opt/lua-resty-inspect/lib/resty/inspect/dbg.lua:50: in function </opt/lua-resty-inspect/lib/resty/inspect/dbg.lua:17>
        /opt/apisix.fork/apisix/plugins/limit-req.lua:88: in function 'phase_func'
        /opt/apisix.fork/apisix/plugin.lua:900: in function 'run_plugin'
        /opt/apisix.fork/apisix/init.lua:456: in function 'http_access_phase'
        access_by_lua(nginx.conf:303):2: in main chunk, client: 127.0.0.1, server: _, request: "GET /get HTTP/1.1", host: "127.0.0.1:9080"
2022/09/01 00:55:52 [info] 2754534#2754534: *4070 [lua] resty_inspect_hooks.lua:5: /opt/apisix.fork/apisix/plugins/limit-req.lua:88 (phase_func), client: 127.0.0.1, server: _, request: "GET /get HTTP/1.1", host: "127.0.0.1:9080"
2022/09/01 00:55:52 [info] 2754534#2754534: *4070 [lua] resty_inspect_hooks.lua:6: conf_key=remote_addr, client: 127.0.0.1, server: _, request: "GET /get HTTP/1.1", host: "127.0.0.1:9080"
```

## Delete Plugin

To remove the `inspect` Plugin, you can remove it from your configuration file (`conf/config.yaml`):

```yaml title="conf/config.yaml"
plugins:
    # - inspect
```
