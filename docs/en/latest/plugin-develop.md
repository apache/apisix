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

## where to put your plugins

There are two ways to add new features based on APISIX.

1. modify the source of APISIX and redistribute it (not so recommended)
1. setup the `extra_lua_path` and `extra_lua_cpath` in `conf/config.yaml` to load your own code. Your own code will be loaded instead of the builtin one with the same name, so you can use this way to override the builtin behavior if needed.

For example, you can create a directory structure like this:

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

If you need to customize the directory of plugin, please create a subdirectory of `/apisix/plugins` under this directory.

:::

Then add this configuration into your `conf/config.yaml`:

```yaml
apisix:
    ...
    extra_lua_path: "/path/to/example/?.lua"
```

Now using `require "apisix.plugins.3rd-party"` will load your plugin, just like `require "apisix.plugins.jwt-auth"` will load the `jwt-auth` plugin.

Sometimes you may want to override a method instead of a whole file. In this case, you can configure `lua_module_hook` in `conf/config.yaml`
to introduce your hook.

Assumed your configuration is:

```yaml
apisix:
    ...
    extra_lua_path: "/path/to/example/?.lua"
    lua_module_hook: "my_hook"
```

The `example/my_hook.lua` will be loaded when APISIX starts, and you can use this hook to replace a method in APISIX.
The example of [my_hook.lua](https://github.com/apache/apisix/blob/master/example/my_hook.lua) can be found under the `example` directory of this project.

## check dependencies

if you have dependencies on external libraries, check the dependent items. if your plugin needs to use shared memory, it
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
method "http_init" in the file __apisix/init.lua__, and you may need to add some processing on generated part of Nginx
configuration file in __apisix/cli/ngx_tpl.lua__ file. But it is easy to have an impact on the overall situation according to the
existing plugin mechanism, **we do not recommend this unless you have a complete grasp of the code**.

## name, priority and the others

Determine the name and priority of the plugin, and add to conf/config.yaml. For example, for the example-plugin plugin,
you need to specify the plugin name in the code (the name is the unique identifier of the plugin and cannot be
duplicate), you can see the code in file "__apisix/plugins/example-plugin.lua__" :

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

In the "__conf/config-default.yaml__" configuration file, the enabled plugins (all specified by plugin name) are listed.

```yaml
plugins:                          # plugin list
  - limit-req
  - limit-count
  - limit-conn
  - key-auth
  - prometheus
  - node-status
  - jwt-auth
  - zipkin
  - ip-restriction
  - grpc-transcode
  - serverless-pre-function
  - serverless-post-function
  - openid-connect
  - proxy-rewrite
  - redirect
  ...
```

Note: the order of the plugins is not related to the order of execution.

To enable your plugin, copy this plugin list into `conf/config.yaml`, and add your plugin name. For instance:

```yaml
plugins: # copied from config-default.yaml
  ...
  - your-plugin
```

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

`type` field is required to be set to `auth` if your plugin needs to work with consumer. See the section below.

## schema and check

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

At the same time, we need to implement the __check_schema(conf)__ method to complete the specification verification.

```lua
function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end
```

Note: the project has provided the public method "__core.schema.check__", which can be used directly to complete JSON
verification.

In addition, if the plugin needs to use some metadata, we can define the plugin `metadata_schema`, and then we can dynamically manage these metadata through the `Admin API`. Example:

```lua
local metadata_schema = {
    type = "object",
    properties = {
        ikey = {type = "number", minimum = 0},
        skey = {type = "string"},
    },
    required = {"ikey", "skey"},
}

local plugin_name = "example-plugin"

local _M = {
    version = 0.1,
    priority = 0,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}
```

You might have noticed the key-auth plugin has `type = 'auth'` in its definition.
When we set the type of plugin to `auth`, it means that this plugin is an authentication plugin.

An authentication plugin needs to choose a consumer after execution. For example, in key-auth plugin, it calls the `consumer.attach_consumer` to attach a consumer, which is chosen via the `apikey` header.

To interact with the `consumer` resource, this type of plugin needs to provide a `consumer_schema` to check the `plugins` configuration in the `consumer`.

Here is the consumer configuration for key-auth plugin:

```json
{
  "username": "Joe",
  "plugins": {
    "key-auth": {
      "key": "Joe's key"
    }
  }
}
```

It will be used when you try to create a [Consumer](https://github.com/apache/apisix/blob/master/docs/en/latest/admin-api.md#consumer)

To validate the configuration, the plugin uses a schema like this:

```lua
local consumer_schema = {
    type = "object",
    properties = {
        key = {type = "string"},
    },
    required = {"key"},
}
```

Note the difference between key-auth's __check_schema(conf)__ method to example-plugin's:

```lua
-- key-auth
function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end
end
```

```lua
-- example-plugin
function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end
```

### encrypted storage fields

Specify the parameters to be stored encrypted. (Requires APISIX version >= 3.1.0)

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

- When adding and updating resources via the `Admin API`, APISIX automatically encrypts the parameters declared in `encrypt_fields` and stores them in etcd
- When fetching resources via the `Admin API` and when running the plugin, APISIX automatically decrypts the parameters declared in `encrypt_fields`

How to enable this feature?

Enable `data_encryption` in `config.yaml`.

```yaml
apisix:
    data_encryption:
    enable: true
    keyring:
        - edd1c9f0985e76a2
        - qeddd145sfvddff4
```

APISIX will try to decrypt the data with keys in the order of the keys in the keyring (only for parameters declared in `encrypt_fields`). If the decryption fails, the next key will be tried until the decryption succeeds.

If none of the keys in `keyring` can decrypt the data, the original data is used.

## choose phase to run

Determine which phase to run, generally access or rewrite. If you don't know the [OpenResty lifecycle](https://github.com/openresty/lua-nginx-module/blob/master/README.markdown#directives), it's
recommended to know it in advance. For example key-auth is an authentication plugin, thus the authentication should be completed
before forwarding the request to any upstream service. Therefore, the plugin must be executed in the rewrite phases.
In APISIX, only the authentication logic can be run in the rewrite phase. Other logic needs to run before proxy should be in access phase.

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

## implement the logic

Write the logic of the plugin in the corresponding phase. There are two parameters `conf` and `ctx` in the phase method, take the `limit-conn` plugin configuration as an example.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "rejected_code": 503,
            "key": "remote_addr"
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

### conf parameter

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

### ctx parameter

The `ctx` parameter caches data information related to the request. You can use `core.log.warn(core.json.encode(ctx, true))` to output it to `error.log` for viewing, as shown below :

```lua
function _M.access(conf, ctx)
    core.log.warn(core.json.encode(ctx, true))
    ......
end
```

## register public API

A plugin can register API which exposes to the public. Take jwt-auth plugin as an example, this plugin registers `GET /apisix/plugin/jwt/sign` to allow client to sign its key:

```lua
local function gen_token()
    --...
end

function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/plugin/jwt/sign",
            handler = gen_token,
        }
    }
end
```

Note that the public API will not be exposed by default, you will need to use the [public-api plugin](plugins/public-api.md) to expose it.

## register control API

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

## register custom variable

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

## write test case

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

Additionally, there are some convenience testing endpoints which can be found [here](https://github.com/apache/apisix/blob/master/t/lib/server.lua#L36). For example, see [proxy-rewrite](https://github.com/apache/apisix/blob/master/t/plugin/proxy-rewrite.lua). In test 42, the upstream `uri` is made to redirect `/test?new_uri=hello` to `/hello` (which always returns `hello world`). In test 43, the response body is confirmed to equal `hello world`, meaning the proxy-rewrite configuration added with test 42 worked correctly.

Refer the following [document](building-apisix.md) to setup the testing framework.

### attach the test-nginx execution process:

According to the path we configured in the makefile and some configuration items at the front of each __.t__ file, the
framework will assemble into a complete nginx.conf file. "__t/servroot__" is the working directory of Nginx and start the
Nginx instance. according to the information provided by the test case, initiate the http request and check that the
return items of HTTP include HTTP status, HTTP response header, HTTP response body and so on.
