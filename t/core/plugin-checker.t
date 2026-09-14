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

no_root_location();
no_long_string();

run_tests();

__DATA__

=== TEST 1: control-plane stream validation rejects an unavailable plugin
--- config
    location /t {
        content_by_lua_block {
            local checker = require("apisix.plugin").stream_plugin_checker
            local ok, err = checker({plugins = {missing = {}}}, true)
            ngx.say(ok or false, ": ", err)
        }
    }
--- request
GET /t
--- response_body
false: unknown plugin [missing]



=== TEST 2: an etcd key identifies tolerant data-plane stream validation
--- config
    location /t {
        content_by_lua_block {
            local checker = require("apisix.plugin").stream_plugin_checker
            local ok, err = checker({plugins = {missing = {}}},
                                    "/apisix/stream_routes/1")
            ngx.say(ok, ": ", err)
        }
    }
--- request
GET /t
--- response_body
true: nil
--- error_log
plugin [missing] is not enabled and will be skipped



=== TEST 3: an explicitly disabled unavailable stream plugin is silent
--- config
    location /t {
        content_by_lua_block {
            local checker = require("apisix.plugin").stream_plugin_checker
            local ok, err = checker({
                plugins = {missing = {_meta = {disable = true}}}
            }, "/apisix/stream_routes/1")
            ngx.say(ok, ": ", err)
        }
    }
--- request
GET /t
--- response_body
true: nil
--- no_error_log
plugin [missing] is not enabled and will be skipped



=== TEST 4: tolerant HTTP validation warns about an unavailable plugin
--- config
    location /t {
        content_by_lua_block {
            local checker = require("apisix.plugin").check_schema
            local ok, err = checker({missing = {}}, nil, true)
            ngx.say(ok, ": ", err)
        }
    }
--- request
GET /t
--- response_body
true: nil
--- error_log
plugin [missing] is not enabled and will be skipped



=== TEST 5: an explicitly disabled unavailable HTTP plugin is silent
--- config
    location /t {
        content_by_lua_block {
            local checker = require("apisix.plugin").check_schema
            local ok, err = checker({
                missing = {_meta = {disable = true}}
            }, nil, true)
            ngx.say(ok, ": ", err)
        }
    }
--- request
GET /t
--- response_body
true: nil
--- no_error_log
plugin [missing] is not enabled and will be skipped



=== TEST 6: single-item full loading passes the etcd key to its checker
--- config
    location /t {
        content_by_lua_block {
            local config_etcd = require("apisix.core.config_etcd")
            local etcd = require("apisix.core.etcd")
            local original_get_format = etcd.get_format
            local etcd_cli = {}

            function etcd_cli.readdir()
                return {
                    status = 200,
                    headers = {},
                    body = {header = {revision = 1}, kvs = {}},
                }
            end

            etcd.get_format = function(res)
                res.body = {
                    node = {
                        key = "/apisix/plugins",
                        value = {{name = "jwt-auth"}},
                        modifiedIndex = 1,
                    },
                }
                return res
            end

            config_etcd.test_sync_data({
                etcd_cli = etcd_cli,
                key = "/apisix/plugins",
                single_item = true,
                need_reload = true,
                checker = function(_, key)
                    ngx.say(key)
                    return true
                end,
                upgrade_version = function() end,
                conf_version = 1,
            })
            etcd.get_format = original_get_format
        }
    }
--- request
GET /t
--- response_body
/apisix/plugins



=== TEST 7: strict HTTP validation rejects an unavailable plugin
--- config
    location /t {
        content_by_lua_block {
            local checker = require("apisix.plugin").check_schema
            local ok, err = checker({missing = {}}, nil, false)
            ngx.say(ok or false, ": ", err)
        }
    }
--- request
GET /t
--- response_body
false: unknown plugin [missing]
