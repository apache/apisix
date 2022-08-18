---
title: Plugin Development
description: Cloud Native API Gateway Apache APISIX supports using Lua, Rust, WASM, Golang, Python, JavaScript to develop custom plugins.
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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Apache APISIX supports using Lua or [other languages](https://apisix.apache.org/docs/apisix/external-plugin/) to develop custom plugins, and we can find all built-in plugins [here](https://github.com/apache/apisix/tree/master/apisix/plugins).

![External Plugin](https://raw.githubusercontent.com/apache/apisix/release/2.15/docs/assets/images/external-plugin.png)

Let's use the [example-plugin](https://github.com/apache/apisix/blob/master/apisix/plugins/example-plugin.lua) plugin to explain how to develop the custom plugin.

## Prerequisite

### Dependencies

Before developing a custom plugin, please check if the custom logic has dependencies.

For example, the [openid-connect](https://github.com/apache/apisix/blob/master/apisix/plugins/openid-connect.lua) plugin needs `Nginx shared memory` functionality, we have to inject Nginx snippet like the following to make it work as expected:

```yaml title="conf/config.yaml"
nginx_config:
  http_configuration_snippet: |
    lua_shared_dict discovery             1m; # cache for discovery metadata documents
    lua_shared_dict jwks                  1m; # cache for JWKs
    lua_shared_dict introspection        10m; # cache for JWT verification results
```

### Lua Language

:::tip

Read [Why Apache APISIX chooses Nginx and Lua to build API Gateway](https://apisix.apache.org/blog/2021/08/25/why-apache-apisix-chose-nginx-and-lua/) to know why.

:::

APISIX uses the [Lua](http://www.lua.org/docs.html) language to implement [built-in plugins](https://github.com/apache/apisix/tree/master/apisix/plugins), but we can also rely on [Plugin Runner](https://apisix.apache.org/docs/apisix/external-plugin) to use [WASM](https://apisix.apache.org/docs/apisix/wasm/), Rust, [Golang](https://apisix.apache.org/docs/go-plugin-runner/getting-started/), [Java](https://apisix.apache.org/docs/java-plugin-runner/development/), [Python](https://apisix.apache.org/docs/python-plugin-runner/getting-started/), and [Node.js](https://github.com/zenozeng/apisix-javascript-plugin-runner) to implement plugins.

## Structure

In APISIX, we use a standalone `.lua` file to contain all custom logics usually.

```lua title="apisix/plugins/example-plugin.lua"
local schema = {}

local metadata_schema = {}

local plugin_name = "example-plugin"

local _M = {
  version = 0.1,
  priority = 0,
  name = plugin_name,
  schema = schema,
  metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
  ...
end


function _M.init()
  ...
end


function _M.destroy()
  ...
end


function _M.rewrite(conf, ctx)
  ...
end


function _M.access(conf, ctx)
  ...
end


function _M.body_filter(conf, ctx)
  ...
end


function _M.delayed_body_filter(conf, ctx)
  ...
end


function _M.control_api()
  ...
end


return _M
```

## Attributes

### Basic

#### `_M.name` {#attribute-name}

The custom plugin's name, all plugins should **pick a unique name**.

#### `_M.version` {#attribute-version}

The custom plugin's version, APISIX's built-in plugins use `0.1` as version currently.

#### `_M.priority` {#attribute-priority}

Each plugin should pick a unique priority, please check the `conf/config-default.yaml` file to get all plugins' priority.

:::tip

As shown in the example above, the plugin can perform different actions at different execution phases. When different plugins perform actions in the same phase, the plugin with higher priority will be executed first.

:::

When setting the priority, in order to avoid unexpected cases caused by prioritizing the execution of built-in plugins, it is recommended to set the priority range from `1 to 99`.

#### `_M.type` (optional) {#attribute-type}

:::tip

<!-- TODO: depends on what? -->

1. Not all Authentication plugins must have the `_M.type = "auth"` attribute, e.g., [authz-keycloak](https://github.com/apache/apisix/blob/master/apisix/plugins/authz-keycloak.lua).
2. Don't forget to work with the [\_M.consumer_schema](#consumer_schema) attribute.

:::

Please check the built-in `Authentication` plugins for reference, e.g., [basic-auth](https://github.com/apache/apisix/blob/master/apisix/plugins/basic-auth.lua#L56), [key-auth](https://github.com/apache/apisix/blob/master/apisix/plugins/key-auth.lua#L57), [jwt-auth](https://github.com/apache/apisix/blob/master/apisix/plugins/jwt-auth.lua#L125).

#### `_M.run_policy` (optional) {#attribute-run_policy}

If set `_M.run_policy = "prefer_route"`, then when we enable the same plugin both at the [Global](https://apisix.apache.org/docs/apisix/admin-api/#global-rule) level and the `Route` level, only the `Route` level will work.

#### `_M.init()` (optional) {#attribute-init}

The `_M.init()` function executes after the plugin is loaded.

#### `_M.destroy()` (optional) {#attribute-destroy}

The `_M.destroy()` function executes after the plugin is unloaded.

### Schema

APISIX uses the [jsonschema](https://github.com/api7/jsonschema) project to validate JSON documents (e.g., Route Rule Configuration).

We will continue using the [example-plugin](https://github.com/apache/apisix/blob/master/apisix/plugins/example-plugin.lua) plugin to explain this section.

#### `_M.schema` {#attribute-schema}

The [JSONSchema](https://github.com/api7/jsonschema) rules saved by the `_M.schema` attribute will be used to verify whether the plugin configuration meets the requirements or not.

:::tip

Not each plugin needs a schema to validate the configuration, it depends on the business requirements.

```lua title="Example Schema"
local schema = {}
```

For this kind of plugin, we only need to set empty object in the plugin configuration.

```json title="Example Configuration"
{
  "example-plugin": {}
}
```

:::

```lua title="apisix/plugins/example-plugin.lua"
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

The `schema.properties` attribute shows that this plugin has 5 properties:

1. `i`: This property is a **Number**, and its minimum is **0**.
2. `s`: This property is a **String**.
3. `t`: This property is an **Array**, and it must contain at least **1** iterm.
4. `ip`: This property is a **String**.
5. `port`: This property is an **Integer**.

The `schema.required` attribute shows that this plugin must contain the **i** property in the configuration data.

Here are 2 valid configuration examples:

```json title="Example 1"
{
  "example-plugin": {
    "i": 1,
    "s": "s",
    "t": [1]
  }
}
```

```json title="Example 2"
{
  "example-plugin": {
    "i": 1
  }
}
```

#### `_M.metadata_schema` {#metadata_schema}

Apache APISIX provides the Plugin Metadata mechanism to store global configuration of plugins, e.g., sensitive key/secret, shared configuration. We could use the [Plugin Metadata API](https://apisix.apache.org/docs/apisix/admin-api/#plugin-metadata) to operate it dynamically.

The `_M.metadata_schema` attribute is similar with the `_M.schema` attribute, we could set schema rules to validate the [Plugin Metadata API](https://apisix.apache.org/docs/apisix/admin-api/#plugin-metadata)'s request body.

```lua title="apisix/plugins/example-plugin.lua"
local metadata_schema = {
  type = "object",
  properties = {
    ikey = {type = "number", minimum = 0},
    skey = {type = "string"},
  },
  required = {"ikey", "skey"},
}
```

#### `_M.consumer_schema` {#consumer_schema}

Apache APISIX provides the [Consumer](https://apisix.apache.org/docs/apisix/terminology/consumer/) entity to bind with a human, a 3rd party service or a client, because they consume services managed by APISIX.

Usually, we will use the `_M.consumer_schema` field in **Authentication** plugins, e.g., [basic-auth](https://github.com/apache/apisix/blob/master/apisix/plugins/basic-auth.lua), [jwt-auth](https://github.com/apache/apisix/blob/master/apisix/plugins/jwt-auth.lua), [key-auth](https://github.com/apache/apisix/blob/master/apisix/plugins/key-auth.lua).

:::tip

Don't forget to work with the [\_M.type](#attribute-type) attribute.

:::

```lua title="apisix/plugins/basic-auth.lua"
local consumer_schema = {
  type = "object",
  title = "work with consumer object",
  properties = {
    username = { type = "string" },
    password = { type = "string" },
  },
  required = {"username", "password"},
}
```

```json title="Create a Consumer with the basic-auth plugin"
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "username": "foo",
  "plugins": {
    "basic-auth": {
      "username": "foo",
      "password": "bar"
    }
  }
}'
```

#### `_M.check_schema()` {#check_schema}

After setting the [\_M.schema](#attribute-schema) attribute, the [\_M.metadata_schema](#metadata_schema) attribute (optional), and the [\_M.consumer_schema](#consumer_schema) attribute (optional), we need to use the `_M.check_schema` function to validate configurations.

:::tip

We could visit [all built-in plugins](https://github.com/apache/apisix/blob/master/apisix/plugins) for reference.

:::

Apache APISIX provides a public validate function [core.schema.check](https://github.com/apache/apisix/blob/master/apisix/core/schema.lua#L59), usually the `_M.check_schema` function has three kinds of implementations:

```lua title="Example: Normal Plugin"
function _M.check_schema(conf, schema_type)
  return core.schema.check(schema, conf)
end
```

```lua title="Example: Metadata Plugin"
function _M.check_schema(conf, schema_type)
  if schema_type == core.schema.TYPE_METADATA then
    return core.schema.check(metadata_schema, conf)
  end
  return core.schema.check(schema, conf)
end
```

```lua title="Example: Authentication plugin"
function _M.check_schema(conf, schema_type)
  if schema_type == core.schema.TYPE_CONSUMER then
    return core.schema.check(consumer_schema, conf)
  end
  return core.schema.check(schema, conf)
end
```

### Execution Phases

![OpenResty-Execution-Phases](https://moonbingbing.gitbooks.io/openresty-best-practices/content/images/openresty_phases.png)

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

:::note
We can't invoke `ngx.exit`, `ngx.redirect` or `core.respond.exit` in rewrite phase and access phase. if need to exit, just return the status and body, the plugin engine will make the exit happen with the returned status and body. [example](https://github.com/apache/apisix/blob/35269581e21473e1a27b11cceca6f773cad0192a/apisix/plugins/limit-count.lua#L177)
:::

#### `_M.rewrite`

TBD

#### `_M.access`

TBD

#### `_M.body_filter`

TBD

#### `_M.delayed_body_filter`

Besides OpenResty's phases, we also provide extra phases to satisfy specific purpose:

- `delayed_body_filter`

```lua
function _M.delayed_body_filter(conf, ctx)
    -- delayed_body_filter is called after body_filter
    -- it is used by the tracing plugins to end the span right after body_filter
end
```

## Logics

TBD

### Public API

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

### Control API

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

### Custom variable

We can use variables in many places of APISIX. For example, customizing log format in http-logger, using it as the key of `limit-*` plugins. In some situations, the builtin variables are not enough. Therefore, APISIX allows developers to register their variables globally, and use them as normal builtin variables.

For instance, let's register a variable called `a6_labels_zone` to fetch the value of the `zone` label in a route:

```lua
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

## Testcases

TBD

## Usage

### Load plugins

Apache APISIX's built-in plugins are under the `path/to/apisix/plugins` directory, and it supports two ways to load custom plugins.

:::tip

1. If the custom plugin has the same name (`_M.name`) as a built-in plugin, the custom plugin will override the built-in plugin.
<!-- TODO: Does Tip 2 work for "extra_lua_path"? -->
2. We could use `require "apisix.plugins.<_M.name>"` in Lua to require the custom plugin.

:::

<!-- Why recommended? -->
<Tabs>
  <TabItem value="config.yaml" label="Update config.yaml (recommended)" default>

1. Add the following snippet in the `config.yaml` file to load custom Lua files. For example:

```yaml title="conf/config.yaml"
apisix:
  extra_lua_path: "/path/to/?.lua"
  extra_lua_cpath: "/path/to/?.lua"
```

2. Restart APISIX instance.

</TabItem>
<TabItem value="update-source-codes" label="Update source codes">

1. Open the [path/to/apisix/plugins](https://github.com/apache/apisix/blob/master/apisix/plugins) directory, edit a built-in plugin or add a new plugin.
2. For example, add the `3rd-party` plugin:

```
├── apisix
│   └── apisix
│       ├── plugins
│       │   └── 3rd-party.lua
│       └── stream
│           └── plugins
│               └── 3rd-party.lua
```

3. [Rebuild APISIX](./building-apisix.md) or distribute it in different formats.

</TabItem>
</Tabs>

### Enable plugins

<!-- TODO: check all reload/restart APISIX text's description; How? -->

After loading the custom plugins, we need to explicitly add them to the `config.yaml` file and restart APISIX.

:::tip

APISIX can't merge the `plugins` attribute from `config.yaml` to `config-default.yaml` file, please copy **all plugin names** to the `config.yaml` file.

:::

```yaml title="config.yaml"
plugins:                           # plugin list (sorted by priority)
  - real-ip
  - ...
  - 3rd-party                      # Custom plugin names
```

### Disable plugins

TBD

### Unload plugins

TBD
