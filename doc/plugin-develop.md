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
[中文](plugin-develop-cn.md)

# table of contents
- [**check dependencies**](#check-dependencies)
- [**name and config**](#name-and-config)
- [**schema and check**](#schema-and-check)
- [**choose phase to run**](#choose-phase-to-run)
- [**implement the logic**](#implement-the-logic)
- [**write test case**](#write-test-case)


## check dependencies

if you have dependencies on external libraries, check the dependent items. if your plugin needs to use shared memory, it
 needs to declare in __bin/apisix__, for example :

```nginx
    lua_shared_dict plugin-limit-req     10m;
    lua_shared_dict plugin-limit-count   10m;
    lua_shared_dict prometheus-metrics   10m;
    lua_shared_dict plugin-limit-conn    10m;
    lua_shared_dict upstream-healthcheck 10m;
    lua_shared_dict worker-events        10m;

    # for openid-connect plugin
    lua_shared_dict discovery             1m; # cache for discovery metadata documents
    lua_shared_dict jwks                  1m; # cache for JWKs
    lua_shared_dict introspection        10m; # cache for JWT verification results
```

The plugin itself provides the init method. It is convenient for plugins to perform some initialization after
 the plugin is loaded.

Note : if the dependency of some plugin needs to be initialized when Nginx start, you may need to add logic to the initialization
       method "http_init" in the file __Lua/apifix.lua__, And you may need to add some processing on generated part of Nginx
       configuration file in __bin/apisix__ file. but it is easy to have an impact on the overall situation according to the
       existing plugin mechanism, we do not recommend this unless you have a complete grasp of the code.

## name and config

determine the name and priority of the plugin, and add to conf/config.yaml. For example, for the key-auth plugin,
 you need to specify the plugin name in the code (the name is the unique identifier of the plugin and cannot be
 duplicate), you can see the code in file "__lua/apisix/plugins/key-auth.lua__" :

```lua
   local plugin_name = "key-auth"

   local _M = {
      version = 0.1,
      priority = 2500,
      type = 'auth',
      name = plugin_name,
      schema = schema,
   }
```

Note : The priority of the new plugin cannot be the same as the priority of any existing plugin. In addition, plugins with a high priority value will be executed first. For example, the priority of basic-auth is 2520 and the priority of ip-restriction is 3000. Therefore, the ip-restriction plugin will be executed first, then the basic-auth plugin.

in the "__conf/config.yaml__" configuration file, the enabled plugins (all specified by plugin name) are listed.

```yaml
plugins:                          # plugin list
  - example-plugin
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
```

Note : the order of the plugins is not related to the order of execution.

## schema and check

Write [Json Schema](https://json-schema.org) descriptions and check functions. similarly, take the key-auth plugin as an example to see its
 configuration data :

```json
 "key-auth" : {
       "key" : "auth-one"
  }
```

The configuration data of the plugin is relatively simple. Only one attribute named key is supported. Let's look
at its schema description :

```lua
   local schema = {
       type = "object",
       properties = {
           key = {type = "string"},
       }
   }
```

At the same time, we need to implement the __check_schema(conf)__ method to complete the specification verification.

```lua
   function _M.check_schema(conf)
       return core.schema.check(schema, conf)
   end
```

Note: the project has provided the public method "__core.schema.check__", which can be used directly to complete JSON
verification.

## choose phase to run

Determine which phase to run, generally access or rewrite. If you don't know the [Openresty life cycle](https://openresty-reference.readthedocs.io/en/latest/Directives/), it's
recommended to know it in advance. For example key-auth is an authentication plugin, thus the authentication should be completed
before forwarding the request to any upstream service. Therefore, the plugin can be executed in the rewrite and access phases.
In APISIX, the authentication logic is implemented in the rewrite phase. Generally, IP access and interface
permission are completed in the access phase.

The following code snippet shows how to implement any logic relevant to the plugin in the Openresty log phase.

```lua
function _M.log(conf)
-- Implement logic here
end
```

## implement the logic

Write the logic of the plugin in the corresponding phase.

## write test case

For functions, write and improve the test cases of various dimensions, do a comprehensive test for your plugin ! The
test cases of plugins are all in the "__t/plugin__" directory. You can go ahead to find out. APISIX uses
[****test-nginx****](https://github.com/openresty/test-nginx) as the test framework. A test case,.t file is usually
divided into prologue and data parts by \__data\__. Here we will briefly introduce the data part, that is, the part
of the real test case. For example, the key-auth plugin :

```perl
=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.key-auth")
            local ok, err = plugin.check_schema({key = 'test-key'})
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

Refer the following [document](how-to-build.md#test) to setup the testing framework.

### Attach the test-nginx execution process:

According to the path we configured in the makefile and some configuration items at the front of each __.t__ file, the
framework will assemble into a complete nginx.conf file. "__t/servroot__" is the working directory of Nginx and start the
Nginx instance. according to the information provided by the test case, initiate the http request and check that the
return items of HTTP include HTTP status, HTTP response header, HTTP response body and so on.
