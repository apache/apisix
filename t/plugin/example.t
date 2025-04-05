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
use t::APISIX 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({i = 1, s = "s", t = {1}})
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



=== TEST 2: missing args
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")

            local ok, err = plugin.check_schema({s = "s", t = {1}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "i" is required
done



=== TEST 3: small then minimum
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({i = -1, s = "s", t = {1, 2}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "i" validation failed: expected -1 to be at least 0
done



=== TEST 4: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({i = 1, s = 123, t = {1}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "s" validation failed: wrong type: expected string, got number
done



=== TEST 5: the size of array < minItems
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({i = 1, s = '123', t = {}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "t" validation failed: expect array to have at least 1 items
done



=== TEST 6: load plugins
--- config
    location /t {
        content_by_lua_block {
            local plugins, err = require("apisix.plugin").load()
            if not plugins then
                ngx.say("failed to load plugins: ", err)
            end

            local encode_json = require("toolkit.json").encode
            local conf = {}
            local ctx = {}
            for _, plugin in ipairs(plugins) do
                ngx.say("plugin name: ", plugin.name,
                        " priority: ", plugin.priority)

                plugin.rewrite(conf, ctx)
            end
        }
    }
--- request
GET /t
--- response_body
plugin name: example-plugin priority: 0
--- yaml_config
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379" # etcd address
    prefix: "/apisix"           # apisix configurations prefix
    timeout: 1
plugins:
  - example-plugin
  - not-exist-plugin
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr/module 'apisix.plugins.not-exist-plugin' not found/



=== TEST 7: filter plugins
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")

            local all_plugins, err = plugin.load()
            if not all_plugins then
                ngx.say("failed to load plugins: ", err)
            end

            local filter_plugins = plugin.filter(nil, {
                value = {
                    plugins = {
                        ["example-plugin"] = {i = 1, s = "s", t = {1, 2}},
                        ["new-plugin"] = {a = "a"},
                    }
                },
                modifiedIndex = 1,
            })

            local encode_json = require("toolkit.json").encode
            for i = 1, #filter_plugins, 2 do
                local plugin = filter_plugins[i]
                local plugin_conf = filter_plugins[i + 1]
                ngx.say("plugin [", plugin.name, "] config: ",
                        encode_json(plugin_conf))
            end
        }
    }
--- request
GET /t
--- response_body
plugin [example-plugin] config: {"i":1,"s":"s","t":[1,2]}



=== TEST 8: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "example-plugin": {
                                "i": 11,
                                "ip": "127.0.0.1",
                                "port": 1981
                            }
                        },
                        "uri": "/server_port"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 9: hit route
--- request
GET /server_port
--- response_body_like eval
qr/1981/



=== TEST 10: set disable = true
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({
                i = 1, s = "s", t = {1},
                disable = true,
            })
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



=== TEST 11: set disable = false
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({
                i = 1, s = "s", t = {1},
                disable = true,
            })
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



=== TEST 12: body filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "example-plugin": {
                                "i": 11,
                                "ip": "127.0.0.1",
                                "port": 1981
                            }
                        },
                        "uri": "/server_port"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 13: hit route
--- request
GET /server_port
--- grep_error_log eval
qr/plugin (body_filter|delayed_body_filter) phase, eof: (false|true)/
--- grep_error_log_out
plugin body_filter phase, eof: false
plugin delayed_body_filter phase, eof: false
plugin body_filter phase, eof: true
plugin delayed_body_filter phase, eof: true



=== TEST 14: lua body filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "example-plugin": {
                            "i": 0,
                            "lua_proxy_upstream": true,
                            "request_uri": "http://httpbin.org/get",
                            "method": "GET"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "httpbin.org:80": 1
                        }
                    }
                }]]
            )

            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                "some body",
                nil,
                {
                    ["Content-Type"] = "text/plain",
                }
            )
            local json = require("cjson.safe")
            local response_data = json.decode(actual_body)

            -- check the request uri is http://httpbin.org/get, not upstream uri http://httpbin.org/anything
            -- which means the response body is changed
            if response_data.url == 'http://httpbin.org/get' then
                ngx.say("passed")
            else
                ngx.say(actual_body)
            end
        }
    }
--- request
GET /t
--- response_body
passed
