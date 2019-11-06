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
- [**check dependencies**](#check dependencies)
- [**name and config**](#*name and config)
- [**schema and check**](#schema and check)
- [**choose phase to run**](#choose phase to run)
- [**implement the logic**](#implement the logic)
- [**write test case**](#write test case)


## check dependencies

If you have dependencies on external libraries, check the license first and add the license to the COPYRIGHT file.

If your plugin needs to use shared memory, it needs to declare in bin/apifix, for example:

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
If the dependency of the plugin needs to be initialized when nginx start, you may need to add logic to the initialization method http_init in the file Lua/apifix.lua,
And you may need to add some processing on generated part of nginx configuration file in bin/apisix file.

The plugin itself provides the init method. It is convenient for plugins to perform some initialization after the plugin is loaded in the init_worker phase.

## name and config

Determine the name and priority of the plugin, and add to conf/config.yaml;

For example, for the key-auth plugin, you need to specify the plugin name in the code (the name is the unique identifier of the plugin and cannot be duplicate),
you can see the code in file "lua/apisix/plugins/key-auth.lua"
```lua
   local plugin_name = "key-auth"
```
n the "conf/config.yaml" configuration file, the supported plugins (all specified by plugin name) are listed
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

## schema and check

Write schema descriptions and check functions;

similarly, take the key-auth plugin as an example to see its configuration data:
```json
 "key-auth": {
       "key": "auth-one"
  }
```
The configuration data of the plugin is relatively simple. 
Only one attribute named key is supported. Let's look at its schema description:
```lua
   local schema = {
       type = "object",
       properties = {
           key = {type = "string"},
       }
   }
```
At the same time, we need to implement the check_schema(conf) method to complete the specification verification.
```lua
   function _M.check_schema(conf)
       return core.schema.check(schema, conf)
   end
```
Note: the project has provided the public method "core.schema.check" , which can be used directly to complete JSON verification.

## choose phase to run

Determine which phase to run, generally access or rewrite; 

If you don't know the openresty life cycle, it's recommended to know it in advance.
key-auth is an authentication plugin, as long as the authentication is completed before the business response after the request comes in. The plugin can be executed in the rewrite and access phases,

In the project, the authentication logic is implemented in the rewrite phase. Generally, IP access and interface permission are completed in the access phase.

## implement the logic

Write the logic of the plugin in the corresponding phase;

## write test case

For functions, write and improve the test cases of various dimensions, do a comprehensive test for your plugin!
              
The test cases of plugins are all in the "t/plugin" directory. You can go ahead to find out.

the test framework [****test-nginx****](#https://github.com/openresty/test-nginx)  adopted by the project.

A test case, .t file is usually divided into prologue and data parts by "data". Here we will briefly introduce the data part, that is, the part of the real test case

For example, the key-auth plugin:              
              
              
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
A test case consists of three parts:
-Program code: configuration content of nginx location
-Input: http request information
-Output check: status, header, body, error log check


when we request /t , which config in the configuration file , the nginx will call "content_by_lua_block" instruction to complete the Lua script, and finally return. The assertion of the use case is response_body
return "done", "no_error_log" means to check the "error.log" of nginx. There must be no EORROR level record

###Attach the test-nginx execution process:

According to the path we configured in the makefile and some configuration items at the front of each .t file, the framework will assemble into a complete nginx.conf file. "t/servroot" is the working directory of nginx
and start the nginx instance. According to the information provided by the test case, initiate the http request and check that the return items of HTTP include HTTP status, HTTP response header, HTTP response body 
