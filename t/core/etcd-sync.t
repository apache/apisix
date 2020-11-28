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

run_tests;

__DATA__

=== TEST 1: minus timeout to watch repeatedly 
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local consumers, _ = core.config.new("/consumers", {
                automatic = true,
                item_schema = core.schema.consumer,
                timeout = 0.2
            })

            ngx.sleep(0.6)
            local idx = consumers.prev_index

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jobs",
                    "plugins": {
                        "basic-auth": {
                            "username": "jobs",
                            "password": "123456"
                        }
                    }
                }]])

            ngx.sleep(2)
            local new_idx = consumers.prev_index
            core.log.info("idx:", idx, " new_idx: ", new_idx)
            if new_idx > idx then
                ngx.say("prev_index updated")
            else
                ngx.say("prev_index not update")
            end
        }
    }
--- request
GET /t
--- response_body
prev_index updated
--- no_error_log
[error]
--- error_log
cancel watch connection success



=== TEST 2: using default timeout
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local consumers, _ = core.config.new("/consumers", {
                automatic = true,
                item_schema = core.schema.consumer,
            })

            ngx.sleep(0.6)
            local idx = consumers.prev_index

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jobs",
                    "plugins": {
                        "basic-auth": {
                            "username": "jobs",
                            "password": "678901"
                        }
                    }
                }]])

            ngx.sleep(2)
            local new_idx = consumers.prev_index
            core.log.info("idx:", idx, " new_idx: ", new_idx)
            if new_idx > idx then
                ngx.say("prev_index updated")
            else
                ngx.say("prev_index not update")
            end
        }
    }
--- request
GET /t
--- response_body
prev_index updated
--- no_error_log
[error]
--- error_log
waitdir key



=== TEST 3: no update
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local consumers, _ = core.config.new("/consumers", {
                automatic = true,
                item_schema = core.schema.consumer
            })

            ngx.sleep(0.6)
            local idx = consumers.prev_index

            local key = "/test_key"
            local val = "test_value"
            core.etcd.set(key, val)

            ngx.sleep(2)

            local new_idx = consumers.prev_index
            core.log.info("idx:", idx, " new_idx: ", new_idx)
            if new_idx > idx then
                ngx.say("prev_index updated")
            else
                ngx.say("prev_index not update")
            end
        }
    }
--- request
GET /t
--- response_body
prev_index not update
--- no_error_log
[error]



=== TEST 4: bad plugin configuration (validated via incremental sync)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            assert(core.etcd.set("/global_rules/etcdsync",
                {id = 1, plugins = { ["proxy-rewrite"] = { uri =  1 }}}
            ))
            -- wait for sync
            ngx.sleep(0.6)
        }
    }
--- request
GET /t
--- error_log
property "uri" validation failed



=== TEST 5: bad plugin configuration (validated via full sync)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            -- wait for full sync finish
            ngx.sleep(0.6)

            assert(core.etcd.delete("/global_rules/etcdsync"))
        }
    }
--- request
GET /t
--- error_log
property "uri" validation failed
