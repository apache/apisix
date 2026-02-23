---
title: Plugin Develop
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

This documentation is about developing plugin in Lua. For other languages,
see [external plugin](./external-plugin.md).

## Where to put your plugins

Use the `extra_lua_path` parameter in `conf/config.yaml` file to load your custom plugin code (or use `extra_lua_cpath` for compiled `.so` or `.dll` file).

For example, you can create a directory `/path/to/example`:

```yaml
apisix:
    ...
    extra_lua_path: "/path/to/example/?.lua"
```

The structure of the `example` directory should look like this:

```
├── example
│   └── apisix
│       ├── plugins
│       │   └── 3rd-party.lua
│       └── stream
│           └── plugins
│               └── 3rd-party.lua
```

:::note

The directory (`/path/to/example`) must contain the `/apisix/plugins` subdirectory.

:::

## Enable the plugin

To enable your custom plugin, add the plugin list to `conf/config.yaml` and append your plugin name. For instance:

```yaml
plugins: # See `conf/config.yaml.example` for an example
  - ... # Add existing plugins
  - your-plugin # Add your custom plugin name (name is the plugin name defined in the code)
```

:::warning

In particular, most APISIX plugins are enabled by default when the plugins field configuration is not defined (The default enabled plugins can be found in [apisix/cli/config.lua](https://github.com/apache/apisix/blob/master/apisix/cli/config.lua)).

Once the plugins configuration is defined in `conf/config.yaml`, the new plugins list will replace the default configuration instead of merging. Therefore, when defining the `plugins` field, make sure to include the built-in plugins that are being used. To maintain consistency with the default behavior, you can include all the default enabled plugins defined in `apisix/cli/config.lua`.

:::

## Writing plugins

The [`example-plugin`](https://github.com/apache/apisix/blob/master/apisix/plugins/example-plugin.lua) plugin in this repo provides an example.

### Naming and priority

Specify the plugin name (the name is the unique identifier of the plugin and cannot be duplicate) and priority in the code.

```lua
local plugin_name = "example-plugin"

local _M = {
    version = 0.1,
    priority = 0,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}
```

Note: The priority of the new plugin cannot be same to any existing ones, you can use the `/v1/schema` method of [control API](./control-api.md#get-v1schema) to view the priority of all plugins. In addition, plugins with higher priority value will be executed first in a given phase (see the definition of `phase` in [choose-phase-to-run](#choose-phase-to-run)). For example, the priority of example-plugin is 0 and the priority of ip-restriction is 3000. Therefore, the ip-restriction plugin will be executed first, then the example-plugin plugin. It's recommended to use priority 1 ~ 99 for your plugin unless you want it to run before some builtin plugins.

Note: the order of the plugins is not related to the order of execution.

### Schema and check

Write [JSON Schema](https://json-schema.org) descriptions and check functions. Similarly, take the example-plugin plugin as an example to see its
configuration data:

```json
{
  "example-plugin": {
    "i": 1,
    "s": "s",
    "t": [1]
  }
}
```

Let's look at its schema description :

```lua
local schema = {
    type = "object",
    properties = {
        i = {type = "number", minimum = 0},
        s = {type = "string"},
        t = {type = "array", minItems = 1},
        ip = {type = "string"},
        port = {type = "integer"},
    },
    required = {"i"},
}
```

The schema defines a non-negative number `i`, a string `s`, a non-empty array of `t`, and `ip` / `port`. Only `i` is required.

At the same time, we need to implement the __check_schema(conf, schema_type)__ method to complete the specification verification.

```lua
function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end
```

:::note

Note: the project has provided the public method "__core.schema.check__", which can be used directly to complete JSON
verification.

:::

The input parameter **schema_type** is used to distinguish between different schemas types. For example, many plugins need to use some [metadata](./terminology/plugin-metadata.md), so they define the plugin's `metadata_schema`.

```lua title="example-plugin.lua"
-- schema definition for metadata
local metadata_schema = {
    type = "object",
    properties = {
        ikey = {type = "number", minimum = 0},
        skey = {type = "string"},
    },
    required = {"ikey", "skey"},
}

function _M.check_schema(conf, schema_type)
    --- check schema for metadata
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    return core.schema.check(schema, conf)
end
```

Another example, the [key-auth](https://github.com/apache/apisix/blob/master/apisix/plugins/key-auth.lua) plugin needs to provide a `consumer_schema` to check the configuration of the `plugins` attribute of the `consumer` resource in order to be used with the [Consumer](./admin-api.md#consumer) resource.

```lua title="key-auth.lua"

local consumer_schema = {
    type = "object",
    properties = {
        key = {type = "string"},
    },
    required = {"key"},
}

function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end
end
```

### Choose phase to run

Determine which [phase](./terminology/plugin.md#plugins-execution-lifecycle) to run, generally access or rewrite. If you don't know the [OpenResty lifecycle](https://github.com/openresty/lua-nginx-module/blob/master/README.markdown#directives), it's
recommended to learn about it in advance. For example `key-auth` is an authentication plugin, thus the authentication should be completed
before forwarding the request to any upstream service. Therefore, the plugin must be executed in the rewrite phases.
Similarly, if you want to modify or process the response body or headers you can do that in the `body_filter` or in the `header_filter` phases respectively.

The following code snippet shows how to implement any logic relevant to the plugin in the OpenResty log phase.

```lua
function _M.log(conf, ctx)
-- Implement logic here
end
```

**Note : we can't invoke `ngx.exit`, `ngx.redirect` or `core.respond.exit` in rewrite phase and access phase. if need to exit, just return the status and body, the plugin engine will make the exit happen with the returned status and body. [example](https://github.com/apache/apisix/blob/35269581e21473e1a27b11cceca6f773cad0192a/apisix/plugins/limit-count.lua#L177)**

### extra phase

Besides OpenResty's phases, we also provide extra phases to satisfy specific purpose:

* `delayed_body_filter`

```lua
function _M.delayed_body_filter(conf, ctx)
    -- delayed_body_filter is called after body_filter
    -- it is used by the tracing plugins to end the span right after body_filter
end
```

### Implement the logic

Write the logic of the plugin in the corresponding phase. There are two parameters `conf` and `ctx` in the phase method, take the `limit-conn` plugin configuration as an example.

#### conf parameter

The `conf` parameter is the relevant configuration information of the plugin, you can use `core.log.warn(core.json.encode(conf))` to output it to `error.log` for viewing, as shown below:

```lua
function _M.access(conf, ctx)
    core.log.warn(core.json.encode(conf))
    ......
end
```

conf:

```json
{
  "rejected_code": 503,
  "burst": 0,
  "default_conn_delay": 0.1,
  "conn": 1,
  "key": "remote_addr"
}
```

#### ctx parameter

The `ctx` parameter caches data information related to the request. You can use `core.log.warn(core.json.encode(ctx, true))` to output it to `error.log` for viewing, as shown below :

```lua
function _M.access(conf, ctx)
    core.log.warn(core.json.encode(ctx, true))
    ......
end
```

### Others

If your plugin has a new code directory of its own, and you need to redistribute it with the APISIX source code, you will need to modify the `Makefile` to create directory, such as:

```
$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/skywalking
$(INSTALL) apisix/plugins/skywalking/*.lua $(INST_LUADIR)/apisix/plugins/skywalking/
```

There are other fields in the `_M` which affect the plugin's behavior.

```lua
local _M = {
    ...
    type = 'auth',
    run_policy = 'prefer_route',
}
```

`run_policy` field can be used to control the behavior of the plugin execution.
When this field set to `prefer_route`, and the plugin has been configured both
in the global and at the route level, only the route level one will take effect.

`type` field is required to be set to `auth` if your plugin needs to work with consumer.

## Load plugin and replace plugin

Using `require "apisix.plugins.3rd-party"` will load your plugin, just like `require "apisix.plugins.jwt-auth"` will load the `jwt-auth` plugin.

Sometimes you may want to override a method instead of a whole file. In this case, you can configure `lua_module_hook` in `conf/config.yaml`
to introduce your hook.

Assume that your configuration is as follows:

```yaml
apisix:
    ...
    extra_lua_path: "/path/to/example/?.lua"
    lua_module_hook: "my_hook"
```

The `example/my_hook.lua` will be loaded when APISIX starts, and you can use this hook to replace a method in APISIX.
The example of [my_hook.lua](https://github.com/apache/apisix/blob/master/example/my_hook.lua) can be found under the `example` directory of this project.

## Check external dependencies

If you have dependencies on external libraries, check the dependent items. If your plugin needs to use shared memory, it
needs to declare via [customizing Nginx configuration](./customize-nginx-configuration.md), for example :

```yaml
# put this in config.yaml:
nginx_config:
    http_configuration_snippet: |
        # for openid-connect plugin
        lua_shared_dict discovery             1m; # cache for discovery metadata documents
        lua_shared_dict jwks                  1m; # cache for JWKs
        lua_shared_dict introspection        10m; # cache for JWT verification results
```

The plugin itself provides the init method. It is convenient for plugins to perform some initialization after
the plugin is loaded. If you need to clean up the initialization, you can put it in the corresponding destroy method.

Note : if the dependency of some plugin needs to be initialized when Nginx start, you may need to add logic to the initialization
method "http_init" in the file `apisix/init.lua`, and you may need to add some processing on generated part of Nginx
configuration file in `apisix/cli/ngx_tpl.lua` file. But it is easy to have an impact on the overall situation according to the
existing plugin mechanism, **we do not recommend this unless you have a complete grasp of the code**.

## Encrypted storage fields

Some plugins require parameters to be stored encrypted, such as the `password` parameter of the `basic-auth` plugin. This plugin needs to specify in the `schema` which parameters need to be stored encrypted.

```lua
encrypt_fields = {"password"}
```

If it is a nested parameter, such as the `clickhouse.password` parameter of the `error-log-logger` plugin, it needs to be separated by `.`:

```lua
encrypt_fields = {"clickhouse.password"}
```

Currently not supported yet:

1. more than two levels of nesting
2. fields in arrays

Parameters can be stored encrypted by specifying `encrypt_fields = {"password"}` in the `schema`. APISIX will provide the following functionality.

- When adding and updating resources, APISIX automatically encrypts the parameters declared in `encrypt_fields` and stores them in etcd
- When fetching resources and when running the plugin, APISIX automatically decrypts the parameters declared in `encrypt_fields`

By default, APISIX has `data_encryption` enabled with [two default keys](https://github.com/apache/apisix/blob/85563f016c35834763376894e45908b2fb582d87/apisix/cli/config.lua#L75), you can modify them in `config.yaml`.

```yaml
apisix:
    data_encryption:
        enable: true
        keyring:
            - ...
```

APISIX will try to decrypt the data with keys in the order of the keys in the keyring (only for parameters declared in `encrypt_fields`). If the decryption fails, the next key will be tried until the decryption succeeds.

If none of the keys in `keyring` can decrypt the data, the original data is used.

## Register public API

A plugin can register API which exposes to the public. Take batch-requests plugin as an example, this plugin registers `POST /apisix/batch-requests` to allow developers to group multiple API requests into a single HTTP request/response cycle:

```lua
function batch_requests()
    -- ...
end

function _M.api()
    -- ...
    return {
        {
            methods = {"POST"},
            uri = "/apisix/batch-requests",
            handler = batch_requests,
        }
    }
end
```

Note that the public API will not be exposed by default, you will need to use the [public-api plugin](plugins/public-api.md) to expose it.

## Register control API

If you only want to expose the API to the localhost or intranet, you can expose it via [Control API](./control-api.md).

Take a look at example-plugin plugin:

```lua
local function hello()
    local args = ngx.req.get_uri_args()
    if args["json"] then
        return 200, {msg = "world"}
    else
        return 200, "world\n"
    end
end


function _M.control_api()
    return {
        {
            methods = {"GET"},
            uris = {"/v1/plugin/example-plugin/hello"},
            handler = hello,
        }
    }
end
```

If you don't change the default control API configuration, the plugin will be expose `GET /v1/plugin/example-plugin/hello` which can only be accessed via `127.0.0.1`. Test with the following command:

```shell
curl -i -X GET "http://127.0.0.1:9090/v1/plugin/example-plugin/hello"
```

[Read more about control API introduction](./control-api.md)

## Register custom variables

We can use variables in many places of APISIX. For example, customizing log format in http-logger, using it as the key of `limit-*` plugins. In some situations, the builtin variables are not enough. Therefore, APISIX allows developers to register their variables globally, and use them as normal builtin variables.

For instance, let's register a variable called `a6_labels_zone` to fetch the value of the `zone` label in a route:

```
local core = require "apisix.core"

core.ctx.register_var("a6_labels_zone", function(ctx)
    local route = ctx.matched_route and ctx.matched_route.value
    if route and route.labels then
        return route.labels.zone
    end
    return nil
end)
```

After that, any get operation to `$a6_labels_zone` will call the registered getter to fetch the value.

Note that the custom variables can't be used in features that depend on the Nginx directive, like `access_log_format`.

## Write test cases

For functions, write and improve the test cases of various dimensions, do a comprehensive test for your plugin! The
test cases of plugins are all in the "__t/plugin__" directory. You can go ahead to find out. APISIX uses
[****test-nginx****](https://github.com/openresty/test-nginx) as the test framework. A test case (.t file) is usually
divided into prologue and data parts by \__data\__. Here we will briefly introduce the data part, that is, the part
of the real test case. For example, the key-auth plugin:

```perl
=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.key-auth")
            local ok, err = plugin.check_schema({key = 'test-key'}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]
```

A test case consists of three parts :

- __Program code__ : configuration content of Nginx location
- __Input__ : http request information
- __Output check__ : status, header, body, error log check

When we request __/t__, which config in the configuration file, the Nginx will call "__content_by_lua_block__" instruction to
complete the Lua script, and finally return. The assertion of the use case is response_body return "done",
"__no_error_log__" means to check the "__error.log__" of Nginx. There must be no ERROR level record. The log files for the unit test
are located in the following folder: 't/servroot/logs'.

The above test case represents a simple scenario. Most scenarios will require multiple steps to validate. To do this, create multiple tests `=== TEST 1`, `=== TEST 2`, and so on. These tests will be executed sequentially, allowing you to break down scenarios into a sequence of atomic steps.

Additionally, there are some convenience testing endpoints which can be found [here](https://github.com/apache/apisix/blob/master/t/lib/server.lua#L36). For example, see [proxy-rewrite](https://github.com/apache/apisix/blob/master/t/plugin/proxy-rewrite.t). In test 42, the upstream `uri` is made to redirect `/test?new_uri=hello` to `/hello` (which always returns `hello world`). In test 43, the response body is confirmed to equal `hello world`, meaning the proxy-rewrite configuration added with test 42 worked correctly.

Refer the following [document](building-apisix.md) to setup the testing framework.

### Attach the test-nginx execution process:

According to the path we configured in the makefile and some configuration items at the front of each __.t__ file, the
framework will assemble into a complete nginx.conf file. "__t/servroot__" is the working directory of Nginx and start the
Nginx instance. according to the information provided by the test case, initiate the http request and check that the
return items of HTTP include HTTP status, HTTP response header, HTTP response body and so on.

## Additional Resource(s)

- Key Concepts - [Plugins](https://apisix.apache.org/docs/apisix/terminology/plugin/)
- [Apache APISIX Extensions Guide](https://apisix.apache.org/blog/2021/10/29/extension-guide/)
- [Create a Custom Plugin in Lua](https://docs.api7.ai/apisix/how-to-guide/custom-plugins/create-plugin-in-lua)
- [example-plugin code](https://github.com/apache/apisix/blob/master/apisix/plugins/example-plugin.lua)
