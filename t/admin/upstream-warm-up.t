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
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: create upstream with warm_up_conf, verify update_time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            
            local data = {
                nodes = {
                    {host = "127.0.0.1", port = 1980, weight = 1}
                },
                type = "roundrobin",
                warm_up_conf = {
                    slow_start_time_seconds = 10,
                    min_weight_percent = 5
                }
            }
            
            local code, message, res_body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            
            if code >= 300 then
                ngx.status = code
                ngx.say("fail: ", message)
                return
            end
            
            local res = core.json.decode(res_body)
            local node = res.value.nodes[1]
            if not node.update_time then
                ngx.say("update_time missing")
                return
            end
            
            if math.abs(node.update_time - ngx.time()) > 5 then
                ngx.say("update_time diff too large")
                return
            end
            
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: add new node, verify old node update_time unchanged and new node update_time set
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            
            -- 1. Get current upstream
            local code, message, res_body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_GET
            )
            
            if code >= 300 then
                ngx.status = code
                ngx.say("fail get: ", message)
                return
            end

            local res = core.json.decode(res_body)
            local root = res.node or res
            local original_update_time = root.value.nodes[1].update_time
            
            ngx.sleep(1.1) -- Ensure time passes
            
            -- 2. Add a new node
            local data = {
                nodes = {
                    {host = "127.0.0.1", port = 1980, weight = 1},
                    {host = "127.0.0.1", port = 1981, weight = 1}
                },
                type = "roundrobin",
                warm_up_conf = {
                    slow_start_time_seconds = 10,
                    min_weight_percent = 5
                }
            }
            
            code, message, res_body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            
            if code >= 300 then
                ngx.status = code
                ngx.say("fail update: ", message)
                return
            end

            local res2 = core.json.decode(res_body)
            local root2 = res2.node or res2
            local nodes = root2.value.nodes
            
            -- Sort nodes to identify them correctly
            table.sort(nodes, function(a, b) return a.port < b.port end)
            
            local old_node = nodes[1] -- port 1980
            local new_node = nodes[2] -- port 1981
            
            if old_node.port ~= 1980 or new_node.port ~= 1981 then
                ngx.say("unexpected nodes order")
                return
            end

            if old_node.update_time ~= original_update_time then
                ngx.say("old node update_time changed")
                return
            end
            
            if not new_node.update_time then
                ngx.say("new node update_time missing")
                return
            end
            
            if math.abs(new_node.update_time - ngx.time()) > 5 then
                ngx.say("new node update_time diff too large")
                return
            end
            
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 3: explicitly set update_time, verify saved
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            
            local explicit_time = ngx.time() - 100
            local data = {
                nodes = {
                    {host = "127.0.0.1", port = 1980, weight = 1, update_time = explicit_time}
                },
                type = "roundrobin",
                warm_up_conf = {
                    slow_start_time_seconds = 10,
                    min_weight_percent = 5
                }
            }
            
            local code, message, res_body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            
            if code >= 300 then
                ngx.status = code
                ngx.say("fail: ", message)
                return
            end

            local res = core.json.decode(res_body)
            local node = res.value.nodes[1]
            
            if node.update_time ~= explicit_time then
                ngx.say("update_time not saved correctly")
                return
            end
            
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: delete node and add back, verify update_time updated
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            
            -- 1. Create upstream with one node
            local data = {
                nodes = {
                    {host = "127.0.0.1", port = 1980, weight = 1}
                },
                type = "roundrobin",
                warm_up_conf = {
                    slow_start_time_seconds = 10,
                    min_weight_percent = 5
                }
            }
            
            local code, message, res_body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail 1: ", message)
                return
            end

            local res = core.json.decode(res_body)
            local time1 = res.value.nodes[1].update_time
            
            ngx.sleep(1.1) -- Ensure time passes
            
            -- 2. Remove node
            data.nodes = {}
            code, message, res_body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail 2: ", message)
                return
            end
            
            -- 3. Add node back
            data.nodes = {
                {host = "127.0.0.1", port = 1980, weight = 1}
            }
            code, message, res_body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail 3: ", message)
                return
            end
            
            res = core.json.decode(res_body)
            local time2 = res.value.nodes[1].update_time
            
            if time1 == time2 then
                ngx.say("update_time not updated")
                return
            end
             if time2 <= time1 then
                ngx.say("new update_time should be greater")
                return
            end
            
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: no warm_up_conf, verify no update_time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            
            local data = {
                nodes = {
                    {host = "127.0.0.1", port = 1980, weight = 1}
                },
                type = "roundrobin"
                -- No warm_up_conf
            }
            
            local code, message, res_body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            
            if code >= 300 then
                ngx.status = code
                ngx.say("fail: ", message)
                return
            end

            local res = core.json.decode(res_body)
            local node = res.value.nodes[1]
            
            if node.update_time then
                ngx.say("update_time should not be set")
                return
            end
            
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: route with embedded upstream, verify update_time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            
            local data = {
                uri = "/hello",
                upstream = {
                    nodes = {
                        {host = "127.0.0.1", port = 1980, weight = 1}
                    },
                    type = "roundrobin",
                    warm_up_conf = {
                        slow_start_time_seconds = 10,
                        min_weight_percent = 5
                    }
                }
            }
            
            local code, message, res_body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            
            if code >= 300 then
                ngx.status = code
                ngx.say("fail: ", message)
                return
            end
            
            local res = core.json.decode(res_body)
            local node = res.value.upstream.nodes[1]
            if not node.update_time then
                ngx.say("update_time missing")
                return
            end
            
            if math.abs(node.update_time - ngx.time()) > 5 then
                ngx.say("update_time diff too large")
                return
            end
            
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 7: service with embedded upstream, verify update_time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            
            local data = {
                upstream = {
                    nodes = {
                        {host = "127.0.0.1", port = 1980, weight = 1}
                    },
                    type = "roundrobin",
                    warm_up_conf = {
                        slow_start_time_seconds = 10,
                        min_weight_percent = 5
                    }
                }
            }
            
            local code, message, res_body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )
            
            if code >= 300 then
                ngx.status = code
                ngx.say("fail: ", message)
                return
            end
            
            local res = core.json.decode(res_body)
            local node = res.value.upstream.nodes[1]
            if not node.update_time then
                ngx.say("update_time missing")
                return
            end
            
            if math.abs(node.update_time - ngx.time()) > 5 then
                ngx.say("update_time diff too large")
                return
            end
            
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
