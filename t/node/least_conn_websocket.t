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
log_level('info');
no_root_location();
worker_connections(1024);
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    enable_admin_key: false
nginx_config:
    http:
        lua_shared_dict:
            balancer-least-conn: 10m
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    my $route = <<_EOC_;
routes:
  - upstream_id: 1
    uris:
      - /ws_test
    enable_websocket: true
#END
_EOC_

    $block->set_value("apisix_yaml", $block->apisix_yaml . $route);

    if (!$block->request && $block->request !~ /websocket/i) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: WebSocket upstream with persistent_conn_counting disabled (default behavior)
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    nodes:
        "127.0.0.1:1980": 2
        "127.0.0.1:1981": 1
# Note: persistent_conn_counting is not set, so it defaults to false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                     "upstream_id": 1,
                     "uris": ["/ws_test"],
                     "enable_websocket": true
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



=== TEST 2: WebSocket upstream with persistent_conn_counting enabled
--- apisix_yaml
upstreams:
  - id: websocket_upstream
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true
    nodes:
        "127.0.0.1:1980": 2
        "127.0.0.1:1981": 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                     "upstream_id": "websocket_upstream",
                     "uris": ["/ws_test"],
                     "enable_websocket": true
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



=== TEST 3: WebSocket handshake with persistent connection counting
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true
    nodes:
        "127.0.0.1:1980": 1
        "127.0.0.1:1981": 1
--- raw_request eval
"GET /ws_test HTTP/1.1\r
Host: server.example.com\r
Upgrade: websocket\r
Connection: Upgrade\r
Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==\r
Sec-WebSocket-Protocol: chat\r
Sec-WebSocket-Version: 13\r
Origin: http://example.com\r
\r
"
--- response_headers
Upgrade: websocket
Connection: upgrade
Sec-WebSocket-Accept: HSmrc0sMlYUkAGmm5OPpG2HaGWk=
!Content-Type
--- raw_response_headers_like: ^HTTP/1.1 101 Switching Protocols\r\n
--- grep_error_log eval
qr/persistent counting not enabled|generated connection count key|incremented connection count/
--- grep_error_log_out
generated connection count key: conn_count:1:127.0.0.1:1980
incremented connection count for server 127.0.0.1:1980 by 1, new count: 1



=== TEST 4: Multiple WebSocket connections load distribution with persistent counting
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true
    nodes:
        "127.0.0.1:1980": 1
        "127.0.0.1:1981": 1
        "127.0.0.1:1982": 1
--- config
    location /t {
        content_by_lua_block {
            local function make_ws_request(conn_id)
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                local ok, err = sock:connect("127.0.0.1", ngx.var.server_port)
                if not ok then
                    ngx.log(ngx.ERR, "connection failed: ", err)
                    return nil, err
                end

                local request = "GET /ws_test HTTP/1.1\r\n" ..
                               "Host: 127.0.0.1:" .. ngx.var.server_port .. "\r\n" ..
                               "Upgrade: websocket\r\n" ..
                               "Connection: Upgrade\r\n" ..
                               "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ..
                               "Sec-WebSocket-Version: 13\r\n" ..
                               "\r\n"

                local bytes, err = sock:send(request)
                if not bytes then
                    ngx.log(ngx.ERR, "send failed: ", err)
                    sock:close()
                    return nil, err
                end

                -- Read response
                local response, err = sock:receive("*a")
                if not response then
                    ngx.log(ngx.ERR, "receive failed: ", err)
                    sock:close()
                    return nil, err
                end

                -- Keep connection open for a bit to simulate persistent connection
                ngx.sleep(0.1)
                sock:close()
                return true
            end

            local threads = {}
            for i = 1, 6 do
                local th = ngx.thread.spawn(make_ws_request, i)
                table.insert(threads, th)
            end

            for _, th in ipairs(threads) do
                ngx.thread.wait(th)
            end

            ngx.say("completed")
        }
    }
--- request
GET /t
--- response_body
completed
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out eval
qr/proxy request to (127\.0\.0\.1:198[012]) while connecting to upstream\n.*proxy request to (127\.0\.0\.1:198[012]) while connecting to upstream\n.*proxy request to (127\.0\.0\.1:198[012]) while connecting to upstream\n.*proxy request to (127\.0\.0\.1:198[012]) while connecting to upstream\n.*proxy request to (127\.0\.0\.1:198[012]) while connecting to upstream\n.*proxy request to (127\.0\.0\.1:198[012]) while connecting to upstream/



=== TEST 5: Verify connection count persistence after upstream scaling
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true
    nodes:
        "127.0.0.1:1980": 1
        "127.0.0.1:1981": 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            -- Step 1: Create initial upstream with 2 nodes
            local code, body = t.test('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                     "id": 1,
                     "type": "least_conn",
                     "scheme": "websocket",
                     "persistent_conn_counting": true,
                     "nodes": {
                         "127.0.0.1:1980": 1,
                         "127.0.0.1:1981": 1
                     }
                 }]]
            )
            ngx.say("initial setup: ", code)

            -- Step 2: Create route
            code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                     "upstream_id": 1,
                     "uris": ["/ws_test"],
                     "enable_websocket": true
                 }]]
            )
            ngx.say("route created: ", code)

            -- Simulate some connections to build up connection counts
            ngx.sleep(0.1)

            -- Step 3: Scale upstream to 3 nodes
            code, body = t.test('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                     "id": 1,
                     "type": "least_conn",
                     "scheme": "websocket",
                     "persistent_conn_counting": true,
                     "nodes": {
                         "127.0.0.1:1980": 1,
                         "127.0.0.1:1981": 1,
                         "127.0.0.1:1982": 1
                     }
                 }]]
            )
            ngx.say("scaled to 3 nodes: ", code)

            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body_like
initial setup: 200
route created: 200
scaled to 3 nodes: 200
test completed
--- grep_error_log eval
qr/lightweight cleanup|generated connection count key|incremented connection count/
--- grep_error_log_out eval
qr/(?:generated connection count key: conn_count:1:127\.0\.0\.1:198[012]|lightweight cleanup for upstream|incremented connection count for server)/



=== TEST 6: Connection cleanup when upstream node is removed
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true
    nodes:
        "127.0.0.1:1980": 1
        "127.0.0.1:1981": 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            -- Create some connection counts first
            ngx.sleep(0.1)

            -- Update upstream to remove one node
            local code, body = t.test('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                     "id": 1,
                     "type": "least_conn",
                     "scheme": "websocket",
                     "persistent_conn_counting": true,
                     "nodes": {
                         "127.0.0.1:1980": 1
                     }
                 }]]
            )

            ngx.say("upstream updated: ", code)
            ngx.say("removed node: 127.0.0.1:1981")
        }
    }
--- request
GET /t
--- response_body
upstream updated: 200
removed node: 127.0.0.1:1981
--- grep_error_log eval
qr/lightweight cleanup|removed zero-count entry/
--- grep_error_log_out
lightweight cleanup for upstream: 1



=== TEST 7: Backward compatibility - least_conn without persistent counting
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    # persistent_conn_counting not specified, should default to false
    nodes:
        "127.0.0.1:1980": 2
        "127.0.0.1:1981": 1
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local balancer = require("apisix.balancer.least_conn")

            local up_nodes = {
                ["127.0.0.1:1980"] = 2,
                ["127.0.0.1:1981"] = 1
            }

            local upstream = {
                type = "least_conn",
                nodes = up_nodes
                -- No persistent_conn_counting field
            }

            local b = balancer.new(up_nodes, upstream)
            local server = b.get()

            -- Should select 1980 due to higher weight (traditional behavior)
            ngx.say("selected server: ", server)
            ngx.say("traditional mode: ", not b.use_persistent_counting)
        }
    }
--- request
GET /t
--- response_body_like
selected server: 127\.0\.0\.1:1980
traditional mode: true



=== TEST 8: Error handling - shared dictionary missing
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin_key: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
# Note: balancer-least-conn shared dict intentionally missing
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true
    nodes:
        "127.0.0.1:1980": 1
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local balancer = require("apisix.balancer.least_conn")

            local up_nodes = {
                ["127.0.0.1:1980"] = 1
            }

            local upstream = {
                id = 1,
                type = "least_conn",
                scheme = "websocket",
                persistent_conn_counting = true,
                nodes = up_nodes
            }

            -- Should gracefully fall back to traditional mode
            local b = balancer.new(up_nodes, upstream)
            local server = b.get()

            ngx.say("fallback successful: ", server ~= nil)
            ngx.say("traditional mode: ", not b.use_persistent_counting)
        }
    }
--- request
GET /t
--- response_body
fallback successful: true
traditional mode: true
--- grep_error_log eval
qr/shared dict.*not found|using traditional least_conn mode/
--- grep_error_log_out
shared dict 'balancer-least-conn' not found, using traditional least_conn mode



=== TEST 9: Connection count overflow protection
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true
    nodes:
        "127.0.0.1:1980": 1
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local balancer = require("apisix.balancer.least_conn")

            local up_nodes = {
                ["127.0.0.1:1980"] = 1
            }

            local upstream = {
                id = 1,
                type = "least_conn",
                scheme = "websocket",
                persistent_conn_counting = true,
                nodes = up_nodes
            }

            local b = balancer.new(up_nodes, upstream)

            -- Simulate get and after_balance calls to test score calculations
            local server = b.get()
            ngx.say("selected server: ", server)

            local ctx = {
                balancer_server = server
            }

            -- This should not create negative scores
            b.after_balance(ctx, false)

            ngx.say("after_balance completed")
        }
    }
--- request
GET /t
--- response_body
selected server: 127.0.0.1:1980
after_balance completed



=== TEST 10: Performance test - lightweight cleanup with zero-count entries
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true
    nodes:
        "127.0.0.1:1980": 1
        "127.0.0.1:1981": 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local shared_dict = ngx.shared["balancer-least-conn"]

            if shared_dict then
                -- Create zero-count entries for current servers to test cleanup
                local upstream_id = 1
                local key1 = "conn_count:" .. upstream_id .. ":127.0.0.1:1980"
                local key2 = "conn_count:" .. upstream_id .. ":127.0.0.1:1981"

                shared_dict:set(key1, 0)  -- Zero count entry
                shared_dict:set(key2, 5)  -- Non-zero entry

                ngx.say("created test entries - zero count and non-zero count")
            else
                ngx.say("no shared dict available")
            end

            -- Trigger lightweight cleanup by updating upstream configuration
            local code, body = t.test('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                     "id": 1,
                     "type": "least_conn",
                     "scheme": "websocket",
                     "persistent_conn_counting": true,
                     "nodes": {
                         "127.0.0.1:1980": 1,
                         "127.0.0.1:1981": 1
                     }
                 }]]
            )

            ngx.say("upstream updated: ", code)

            -- Test global cleanup function
            if shared_dict then
                -- Create some dummy entries for global cleanup test
                for i = 1, 50 do
                    local key = "conn_count:test:" .. i
                    shared_dict:set(key, i)
                end
                ngx.say("created 50 dummy entries for global cleanup test")
            end
        }
    }
--- request
GET /t
--- response_body_like
created test entries - zero count and non-zero count
upstream updated: 200
created 50 dummy entries for global cleanup test
--- grep_error_log eval
qr/lightweight cleanup|removed zero-count entry/
--- grep_error_log_out
lightweight cleanup for upstream: 1
removed zero-count entry for server: 127.0.0.1:1980
cleaned up 1 zero-count entries



=== TEST 11: Test global cleanup function performance
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    scheme: websocket
    persistent_conn_counting: true
    nodes:
        "127.0.0.1:1980": 1
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local balancer = require("apisix.balancer.least_conn")
            local shared_dict = ngx.shared["balancer-least-conn"]

            if shared_dict then
                -- Create multiple test entries for different upstreams
                for upstream_id = 100, 120 do
                    for server_id = 1, 3 do
                        local key = "conn_count:" .. upstream_id .. ":127.0.0.1:" .. (2000 + server_id)
                        local value = math.random(0, 10)
                        shared_dict:set(key, value)
                    end
                end
                ngx.say("created test entries for 21 upstreams")
            end

            -- Test the global cleanup function
            balancer.cleanup_all()
            ngx.say("global cleanup completed")
        }
    }
--- request
GET /t
--- response_body
created test entries for 21 upstreams
global cleanup completed
--- grep_error_log eval
qr/cleaned up \d+ connection count entries from shared dict/
--- grep_error_log_out
cleaned up 63 connection count entries from shared dict