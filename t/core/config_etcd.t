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

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");
add_block_preprocessor(sub {
    my ($block) = @_;
});

run_tests;

__DATA__


=== TEST 14: handle etcd restart with lower revision numbers
--- yaml_config
apisix:
    node_listen: 1984
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        host:
            - "http://127.0.0.1:2379"
--- config
    location /t {
        content_by_lua_block {
            local config_etcd = require("apisix.core.config_etcd")
            local core = require("apisix.core")
            
            -- Mock etcd client with revision simulation
            local test_revision = 50
            local etcd_cli = {
                readdir = function(_, key)
                    test_revision = test_revision  -- Force revision decrease
                    return {
                        status = 200,
                        headers = {["X-Etcd-Index"] = test_revision},
                        body = {
                            header = {revision = test_revision},
                            node = {
                                key = key,
                                nodes = {
                                    {
                                        key = key .. "/1",
                                        value = {uri = "/new_path"},
                                        modifiedIndex = test_revision
                                    }
                                }
                            }
                        }
                    }
                end
            }
            
            -- Create test config object
            local config = config_etcd.new("/routes", {
                automatic = true,
                item_schema =  {},
                checker = function(item) return true end
            })
            config.etcd_cli = etcd_cli
            
            -- First sync (initial load)
            local ok, err = config_etcd.test_sync_data(config)
            ngx.say("Initial sync: ", ok and "ok" or "failed: " .. tostring(err))
            ngx.say("Initial revision: ", config.prev_index)
            
            -- Simulate watch detection of lower revision
            config.prev_index = 100  -- Reset to higher value
            config.need_reload = true
            
            -- Second sync with revision mismatch
            ok, err = config_etcd.test_sync_data(config)
            ngx.say("Second sync: ", ok and "ok" or "failed: " .. tostring(err))
            ngx.say("Final revision: ", config.prev_index)
            
            -- Verify data reload
            if config.values and config.values[1] then
                ngx.say("Route value: ", config.values[1].value.uri)
            else
                ngx.say("No routes loaded")
            end
        }
    }
--- request
GET /t
--- response_body
Initial sync: ok
Initial revision: 50
Second sync: ok
Final revision: 50
Route value: /new_path
--- grep_error_log eval
qr/received smaller revision/
--- grep_error_log_out
received smaller revision (50 < 100). etcd might have restarted. resyncing...
--- no_error_log
[error]
--- timeout: 10
