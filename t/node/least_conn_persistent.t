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
log_level('info');
no_long_string();
no_root_location();

run_tests();

__DATA__

=== TEST 1: Test upstream schema with persistent_conn_counting
--- yaml_config
upstreams:
    -
        id: 1
        type: least_conn
        nodes:
            "127.0.0.1:1980": 1
            "127.0.0.1:1981": 1
        persistent_conn_counting: true
routes:
    -
        uri: /echo
        upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            -- Test upstream schema validation with persistent_conn_counting
            local upstream = {
                id = 1,
                type = "least_conn",
                nodes = {
                    ["127.0.0.1:1980"] = 1,
                    ["127.0.0.1:1981"] = 1
                },
                persistent_conn_counting = true
            }

            local ok, err = core.schema.check(require("apisix.schema_def").upstream, upstream)
            if not ok then
                ngx.say("upstream schema validation failed: ", err)
                return
            end

            ngx.say("Upstream schema validation: PASSED")
        }
    }
--- request
GET /t
--- response_body
Upstream schema validation: PASSED



=== TEST 2: Test persistent_conn_counting parameter in upstream schema
--- yaml_config
upstreams:
    -
        id: 1
        type: least_conn
        nodes:
            "127.0.0.1:1980": 1
        persistent_conn_counting: true
routes:
    -
        uri: /echo
        upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            -- Test persistent_conn_counting validation
            local test_cases = {
                {persistent_conn_counting = true, desc = "true"},
                {persistent_conn_counting = false, desc = "false"},
                {persistent_conn_counting = nil, desc = "nil (default)"}
            }

            for i, test_case in ipairs(test_cases) do
                local upstream = {
                    type = "least_conn",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    persistent_conn_counting = test_case.persistent_conn_counting
                }

                local ok, err = core.schema.check(require("apisix.schema_def").upstream, upstream)
                if ok then
                    ngx.say("persistent_conn_counting(", test_case.desc, "): PASSED")
                else
                    ngx.say("persistent_conn_counting(", test_case.desc, "): FAILED - ", err)
                end
            end
        }
    }
--- request
GET /t
--- response_body
persistent_conn_counting(true): PASSED
persistent_conn_counting(false): PASSED
persistent_conn_counting(nil (default)): PASSED



=== TEST 3: Test least_conn balancer module loading and functions
--- yaml_config
routes:
    -
        uri: /echo
        upstream_id: 1
upstreams:
    -
        id: 1
        type: least_conn
        nodes:
            "127.0.0.1:1980": 1
        persistent_conn_counting: true
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")

            ngx.say("least_conn module loaded: SUCCESS")

            -- Check if required functions exist
            ngx.say("function new: EXISTS")

            -- Create a test balancer to check other functions
            local test_up_nodes = {["127.0.0.1:1980"] = 1}
            local test_upstream = {}
            local test_balancer = least_conn.new(test_up_nodes, test_upstream)

            if test_balancer then
                local functions = {"get", "after_balance", "before_retry_next_priority"}
                for _, func_name in ipairs(functions) do
                    if test_balancer[func_name] then
                        ngx.say("function ", func_name, ": EXISTS")
                    else
                        ngx.say("function ", func_name, ": MISSING")
                    end
                end
            else
                ngx.say("ERROR: Could not create test balancer to check functions")
            end
        }
    }
--- request
GET /t
--- response_body
least_conn module loaded: SUCCESS
function new: EXISTS
function get: EXISTS
function after_balance: EXISTS
function before_retry_next_priority: EXISTS



=== TEST 4: Test shared dictionary for connection counting
--- yaml_config
routes:
    -
        uri: /echo
        upstream_id: 1
upstreams:
    -
        id: 1
        type: least_conn
        nodes:
            "127.0.0.1:1980": 1
        persistent_conn_counting: true
--- config
    location /t {
        content_by_lua_block {
            local ngx_shared = ngx.shared

            -- Check if shared dictionary exists
            local conn_count_dict = ngx_shared["balancer-least-conn"]
            if conn_count_dict then
                ngx.say("shared dictionary 'balancer-least-conn': EXISTS")

                -- Test basic operations
                local ok, err = conn_count_dict:set("test_key", 100)
                if ok then
                    ngx.say("shared dictionary set operation: SUCCESS")

                    local value = conn_count_dict:get("test_key")
                    ngx.say("shared dictionary get operation: ", value)
                else
                    ngx.say("shared dictionary set operation: FAILED - ", err)
                end
            else
                ngx.say("shared dictionary 'balancer-least-conn': NOT_FOUND")
                ngx.say("Available shared dictionaries:")
                local count = 0
                for name, dict in pairs(ngx_shared) do
                    ngx.say("  - ", name)
                    count = count + 1
                end
                if count == 0 then
                    ngx.say("  (none)")
                end
            end
        }
    }
--- request
GET /t
--- response_body_like
shared dictionary 'balancer-least-conn': EXISTS
shared dictionary set operation: SUCCESS
shared dictionary get operation: 100



=== TEST 5: Test route configuration validation
--- yaml_config
routes:
    -
        uri: /echo
        upstream_id: 1
upstreams:
    -
        id: 1
        type: least_conn
        nodes:
            "127.0.0.1:1980": 1
        persistent_conn_counting: true
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            -- Test route configuration
            local route_obj = {
                uri = "/echo",
                upstream_id = 1
            }

            local ok, err = core.schema.check(require("apisix.schema_def").route, route_obj)
            if not ok then
                ngx.say("route schema validation failed: ", err)
            else
                ngx.say("Route configuration: VALID")
            end
        }
    }
--- request
GET /t
--- response_body
Route configuration: VALID



=== TEST 6: Test least_conn balancer with proper parameters
--- yaml_config
routes:
    -
        uri: /echo
        upstream_id: 1
upstreams:
    -
        id: 1
        type: least_conn
        nodes:
            "127.0.0.1:1980": 1
            "127.0.0.1:1981": 1
        persistent_conn_counting: true
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            local ngx_shared = ngx.shared

            -- Test creating least_conn balancer with proper parameters
            local upstream = {
                id = 1,
                nodes = {
                    ["127.0.0.1:1980"] = 1,
                    ["127.0.0.1:1981"] = 1
                },
                persistent_conn_counting = true
            }

            -- Use upstream nodes directly in expected format for least_conn
            local up_nodes = upstream.nodes

            -- Create balancer
            local balancer = least_conn.new(up_nodes, upstream)
            if balancer then
                ngx.say("least_conn balancer creation: SUCCESS")
            else
                ngx.say("least_conn balancer creation: FAILED")
                return
            end

            -- Test get function with empty ctx (should be protected)
            local ctx = {}
            local server, info = balancer.get(ctx)
            if server then
                ngx.say("balancer.get() with ctx: SUCCESS - selected ", server)
            else
                ngx.say("balancer.get() with ctx: FAILED - ", info)
            end

            ngx.say("least_conn balancer basic functionality: PASSED")
        }
    }
--- request
GET /t
--- response_body_like
least_conn balancer creation: SUCCESS
balancer\.get\(\) with ctx: SUCCESS - selected 127\.0\.0\.1:(1980|1981)
least_conn balancer basic functionality: PASSED



=== TEST 7: Test connection counting integration
--- yaml_config
routes:
    -
        uri: /echo
        upstream_id: 1
upstreams:
    -
        id: 1
        type: least_conn
        nodes:
            "127.0.0.1:1980": 1
            "127.0.0.1:1981": 1
        persistent_conn_counting: true
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            local ngx_shared = ngx.shared

            -- Get shared dictionary
            local conn_count_dict = ngx_shared["balancer-least-conn"]
            if not conn_count_dict then
                ngx.say("ERROR: shared dictionary not available")
                return
            end

            -- Setup test data
            local upstream = {
                id = 1,
                nodes = {
                    ["127.0.0.1:1980"] = 1,
                    ["127.0.0.1:1981"] = 1
                },
                persistent_conn_counting = true
            }

            -- Set initial connection counts to test least_conn logic
            local key1 = "conn_count:1:127.0.0.1:1980"
            local key2 = "conn_count:1:127.0.0.1:1981"

            conn_count_dict:set(key1, 10)
            conn_count_dict:set(key2, 5)

            -- Verify connection counts
            local count1 = conn_count_dict:get(key1) or 0
            local count2 = conn_count_dict:get(key2) or 0

            ngx.say("server1 (127.0.0.1:1980) connections: ", count1)
            ngx.say("server2 (127.0.0.1:1981) connections: ", count2)

            -- Create balancer and test server selection
            local up_nodes = upstream.nodes  -- Use the original upstream nodes format
            local balancer = least_conn.new(up_nodes, upstream)

            local ctx = {}
            local server, info = balancer.get(ctx)

            if server then
                -- Server with fewer connections should be selected
                local expected_server = count2 < count1 and "127.0.0.1:1981" or "127.0.0.1:1980"
                local selected_server = server  -- server should be the host:port string
                ngx.say("least_conn selected server: ", selected_server)

                if selected_server == expected_server then
                    ngx.say("connection counting logic: CORRECT")
                else
                    ngx.say("connection counting logic: INCORRECT (expected ", expected_server, ")")
                end
            else
                ngx.say("server selection: FAILED - ", info)
            end

            ngx.say("persistent connection counting integration: COMPLETED")
        }
    }
--- request
GET /t
--- response_body_like
server1 \(127\.0\.0\.1:1980\) connections: 10
server2 \(127\.0\.0\.1:1981\) connections: 5
least_conn selected server: 127\.0\.0\.1:1981
connection counting logic: CORRECT
persistent connection counting integration: COMPLETED



=== TEST 8: Test least_conn algorithm with multiple iterations
--- yaml_config
routes:
    -
        uri: /echo
        upstream_id: 1
upstreams:
    -
        id: 1
        type: least_conn
        nodes:
            "127.0.0.1:1980": 1
            "127.0.0.1:1981": 1
            "127.0.0.1:1982": 1
        persistent_conn_counting: true
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            local ngx_shared = ngx.shared

            -- Get shared dictionary
            local conn_count_dict = ngx_shared["balancer-least-conn"]
            if not conn_count_dict then
                ngx.say("ERROR: shared dictionary not available")
                return
            end

            -- Clear previous test data
            conn_count_dict:flush_all()

            -- Setup test data with 3 servers
            local upstream = {
                id = 2,
                nodes = {
                    ["127.0.0.1:1980"] = 1,
                    ["127.0.0.1:1981"] = 1,
                    ["127.0.0.1:1982"] = 1
                },
                persistent_conn_counting = true
            }

            local servers = {"127.0.0.1:1980", "127.0.0.1:1981", "127.0.0.1:1982"}
            local key_prefix = "conn_count:2:"

            -- Set varying initial connection counts
            conn_count_dict:set(key_prefix .. servers[1], 10)  -- server1: 10 connections
            conn_count_dict:set(key_prefix .. servers[2], 5)   -- server2: 5 connections
            conn_count_dict:set(key_prefix .. servers[3], 8)   -- server3: 8 connections

            ngx.say("[Initial connection counts]")
            for i, server in ipairs(servers) do
                local count = conn_count_dict:get(key_prefix .. server) or 0
                ngx.say("server", i, " (", server, "): ", count, " connections")
            end

            -- Create balancer
            local up_nodes = upstream.nodes
            local balancer = least_conn.new(up_nodes, upstream)

            if not balancer then
                ngx.say("ERROR: Failed to create balancer")
                return
            end

            ngx.say("")
            ngx.say("[Multiple selection iterations]")

            local selection_counts = {}
            local total_iterations = 10

            for i = 1, total_iterations do
                -- Select server using balancer (this will increment the conn count internally)
                local ctx = {}
                local selected_server, info = balancer.get(ctx)

                if selected_server then
                    selection_counts[selected_server] = (selection_counts[selected_server] or 0) + 1
                    local conn_after = conn_count_dict:get(key_prefix .. selected_server) or 0
                    ngx.say("iteration ", i, ": selected ", selected_server, " (conn_after=", conn_after, ")")
                else
                    ngx.say("iteration ", i, ": selection FAILED - ", info)
                end
            end

            ngx.say("")
            ngx.say("[Selection summary]")
            for _, server in ipairs(servers) do
                local count = selection_counts[server] or 0
                ngx.say(server, " selected ", count, " times")
            end

            ngx.say("")
            ngx.say("[Final connection counts]")
            local final_counts = {}
            for i, server in ipairs(servers) do
                local count = conn_count_dict:get(key_prefix .. server) or 0
                final_counts[i] = count
                ngx.say("server", i, " (", server, "): ", count, " connections")
            end

            -- Verify load balancing effectiveness
            ngx.say("")

            -- Get selection counts for each server
            local count_1980 = selection_counts["127.0.0.1:1980"] or 0
            local count_1981 = selection_counts["127.0.0.1:1981"] or 0
            local count_1982 = selection_counts["127.0.0.1:1982"] or 0

            -- Verify 1: selection order should be 1980 <= 1982 <= 1981
            -- (server with lower initial connections should be selected more)
            -- Initial: 1980=10, 1981=5, 1982=8, so 1981 should be selected most
            local selection_order_ok = (count_1980 <= count_1982) and (count_1982 <= count_1981)
            ngx.say("selection order (1980 <= 1982 <= 1981): ",
                    count_1980, " <= ", count_1982, " <= ", count_1981,
                    " -> ", selection_order_ok and "YES" or "NO")

            -- Verify 2: final connection counts difference should be <= 2
            local max_final = math.max(final_counts[1], final_counts[2], final_counts[3])
            local min_final = math.min(final_counts[1], final_counts[2], final_counts[3])
            local final_diff = max_final - min_final
            local balance_ok = final_diff <= 2
            ngx.say("final counts balance (diff <= 2): ", final_diff, " -> ", balance_ok and "YES" or "NO")

            if selection_order_ok and balance_ok then
                ngx.say("least_conn multiple iterations test: PASSED")
            else
                ngx.say("least_conn multiple iterations test: FAILED")
            end
        }
    }
--- request
GET /t
--- response_body_like
\[Initial connection counts\]
server1 \(127\.0\.0\.1:1980\): 10 connections
server2 \(127\.0\.0\.1:1981\): 5 connections
server3 \(127\.0\.0\.1:1982\): 8 connections

\[Multiple selection iterations\]
iteration 1: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)
iteration 2: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)
iteration 3: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)
iteration 4: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)
iteration 5: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)
iteration 6: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)
iteration 7: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)
iteration 8: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)
iteration 9: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)
iteration 10: selected 127\.0\.0\.1:\d+ \(conn_after=\d+\)

\[Selection summary\]
.*

\[Final connection counts\]
.*

selection order \(1980 <= 1982 <= 1981\): \d+ <= \d+ <= \d+ -> YES
final counts balance \(diff <= 2\): [012] -> YES
least_conn multiple iterations test: PASSED
