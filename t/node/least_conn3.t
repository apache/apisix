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
no_shuffle();

run_tests();

__DATA__

=== TEST 1: keep in-flight conn count across balancer recreation on scaling
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            -- resource_key is stable across scaling, so both pickers share the
            -- same connection count table
            local up = {resource_key = "/upstreams/lc-scale"}

            -- 2 nodes serving long-lived connections
            local nodes = {["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1}
            local p1 = least_conn.new(nodes, up, 0)

            -- establish 4 in-flight connections (get without after_balance)
            local ctx = {}
            local held = {}
            for _ = 1, 4 do
                held[#held + 1] = p1.get(ctx)
            end

            -- scale out: add a third node, the picker is recreated
            local scaled = {["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1,
                            ["127.0.0.1:1982"] = 1}
            local p2 = least_conn.new(scaled, up, 0)

            -- the freshly added node has no connection, so it must be picked first
            for _ = 1, 2 do
                local s = p2.get(ctx)
                held[#held + 1] = s
                ngx.say(s)
            end

            -- release everything so repeated runs start from a clean state
            for _, s in ipairs(held) do
                ctx.balancer_server = s
                p2.after_balance(ctx, false)
            end
        }
    }
--- request
GET /t
--- response_body
127.0.0.1:1982
127.0.0.1:1982



=== TEST 2: a drained node returns to the pool across balancer recreation
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            local up = {resource_key = "/upstreams/lc-drain"}

            local nodes = {["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1}
            local p1 = least_conn.new(nodes, up, 0)

            -- hold 4 in-flight connections, 2 land on each node
            local ctx = {}
            local held = {}
            for _ = 1, 4 do
                held[#held + 1] = p1.get(ctx)
            end

            -- drain every connection on 1980
            for _, s in ipairs(held) do
                if s == "127.0.0.1:1980" then
                    ctx.balancer_server = s
                    p1.after_balance(ctx, false)
                end
            end

            -- picker recreated: 1980 is back to baseline and must be preferred
            -- over 1981 which is still holding connections
            local p2 = least_conn.new(nodes, up, 0)
            local s = p2.get(ctx)
            ngx.say(s)

            -- release the rest so repeated runs start from a clean state
            ctx.balancer_server = s
            p2.after_balance(ctx, false)
            for _, h in ipairs(held) do
                if h == "127.0.0.1:1981" then
                    ctx.balancer_server = h
                    p2.after_balance(ctx, false)
                end
            end
        }
    }
--- request
GET /t
--- response_body
127.0.0.1:1980



=== TEST 3: scale down drops the removed node, remaining nodes balance
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            local up = {resource_key = "/upstreams/lc-scale-down"}

            local nodes = {["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1}
            local p1 = least_conn.new(nodes, up, 0)

            local ctx = {}
            -- fully complete two requests, one per node
            for _ = 1, 2 do
                local s = p1.get(ctx)
                ctx.balancer_server = s
                p1.after_balance(ctx, false)
            end

            -- scale down to a single remaining node, picker recreated
            local scaled = {["127.0.0.1:1981"] = 1}
            local p2 = least_conn.new(scaled, up, 0)

            local s = p2.get(ctx)
            ctx.balancer_server = s
            p2.after_balance(ctx, false)
            ngx.say(s)
        }
    }
--- request
GET /t
--- response_body
127.0.0.1:1981



=== TEST 4: connections released on the old picker are seen by the new one
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            local up = {resource_key = "/upstreams/lc-drain-old-picker"}

            local nodes = {["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1}
            local p1 = least_conn.new(nodes, up, 0)

            -- 4 long-lived connections, 2 on each node
            local ctx = {}
            local held = {}
            for _ = 1, 4 do
                held[#held + 1] = p1.get(ctx)
            end

            -- scale out: new requests are routed with a freshly built picker
            local scaled = {["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1,
                            ["127.0.0.1:1982"] = 1}
            local p2 = least_conn.new(scaled, up, 0)

            -- the long-lived connections close. They are still bound to the picker
            -- they were routed with (ctx.server_picker), so they are released on p1
            for _, s in ipairs(held) do
                ctx.balancer_server = s
                p1.after_balance(ctx, false)
            end

            -- every node is empty again, so the next requests must spread over all
            -- of them instead of piling up on the node that was added last
            local picked = {}
            for _ = 1, 3 do
                picked[#picked + 1] = p2.get(ctx)
            end
            table.sort(picked)
            ngx.say(table.concat(picked, " "))

            for _, s in ipairs(picked) do
                ctx.balancer_server = s
                p2.after_balance(ctx, false)
            end
        }
    }
--- request
GET /t
--- response_body
127.0.0.1:1980 127.0.0.1:1981 127.0.0.1:1982



=== TEST 5: node sets of different priorities keep their own state
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            local up = {resource_key = "/upstreams/lc-priority"}

            local high = least_conn.new({["127.0.0.1:1980"] = 1}, up, 1)
            local low = least_conn.new({["127.0.0.1:1981"] = 1}, up, 0)

            local ctx = {}
            for _, picker in ipairs({high, low}) do
                local s = picker.get(ctx)
                ngx.say(s)
                ctx.balancer_server = s
                picker.after_balance(ctx, false)
            end
        }
    }
--- request
GET /t
--- response_body
127.0.0.1:1980
127.0.0.1:1981



=== TEST 6: a request that runs out of servers does not release twice
--- config
    location /t {
        content_by_lua_block {
            local balancer = require("apisix.balancer")
            local least_conn = require("apisix.balancer.least_conn")

            local up_conf = {
                type = "least_conn",
                resource_key = "/upstreams/lc-double-release",
                nodes = {
                    {host = "127.0.0.1", port = 1980, weight = 10, priority = 0},
                    {host = "127.0.0.1", port = 1981, weight = 1, priority = 0},
                },
            }
            local nodes = {["127.0.0.1:1980"] = 10, ["127.0.0.1:1981"] = 1}

            -- three long-lived connections land on 1981 while it is the only node
            local seeded = {}
            local seed = least_conn.new({["127.0.0.1:1981"] = 1}, up_conf, 0)
            for i = 1, 3 do
                seeded[i] = {}
                seeded[i].balancer_server = seed.get(seeded[i])
            end

            -- a request that fails on every node, driven through the real balancer
            -- a fresh version, as a real scale out would produce, so the balancer
            -- builds a picker for the two nodes over the state seeded above
            local ctx = {upstream_conf = up_conf, upstream_version = tostring(ngx.now()),
                         upstream_key = "lc-double-release", var = {}}
            assert(balancer.pick_server(nil, ctx), "first try")
            assert(balancer.pick_server(nil, ctx), "retry")
            local server, err = balancer.pick_server(nil, ctx)
            ngx.say(server == nil and err or "expected to run out of servers")

            -- the request holds nothing now, so the log phase must release nothing
            ngx.say("holds a server: ", ctx.balancer_server ~= nil)
            ctx.server_picker.after_balance(ctx, false)

            -- 1981 still holds the three connections, so 1980 (ten times the weight)
            -- must win every pick below. It only ties once 1981 is thought to be
            -- lighter than it is
            local picked = {}
            local stolen = false
            local p = least_conn.new(nodes, up_conf, 0)
            for i = 1, 35 do
                picked[i] = {}
                picked[i].balancer_server = p.get(picked[i])
                if picked[i].balancer_server == "127.0.0.1:1981" then
                    stolen = true
                end
            end
            ngx.say(stolen and "stolen" or "kept")

            for _, c in ipairs(picked) do
                p.after_balance(c, false)
            end
            for _, c in ipairs(seeded) do
                p.after_balance(c, false)
            end
        }
    }
--- request
GET /t
--- response_body
failed to find valid upstream server, all upstream servers tried
holds a server: false
kept



=== TEST 7: scaling out an upstream with in-flight requests prefers the new node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"

            -- the requests have to outlast the whole test, and the default upstream
            -- read timeout (6s) would cut them short well before that
            local function set_upstream(nodes)
                local code, body = t('/apisix/admin/upstreams/1', ngx.HTTP_PUT,
                     [[{"type": "least_conn",
                        "timeout": {"connect": 60, "send": 60, "read": 60},
                        "nodes": ]] .. nodes .. [[}]])
                assert(code < 300, body)
            end

            set_upstream([[{"127.0.0.1:1980": 1, "0.0.0.0:1980": 1}]])
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 [[{"uri": "/mysleep", "upstream_id": "1"}]])
            assert(code < 300, body)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/mysleep?seconds="
            -- let the route and the upstream reach the router before hitting them
            ngx.sleep(1)

            -- four in-flight requests, two on each of the original nodes
            local threads = {}
            for i = 1, 4 do
                threads[i] = assert(ngx.thread.spawn(function ()
                    http.new():request_uri(uri .. "60")
                end))
            end
            ngx.sleep(1)

            -- scale out while they are still in flight
            set_upstream([[{"127.0.0.1:1980": 1, "0.0.0.0:1980": 1, "127.0.0.2:1980": 1}]])
            ngx.sleep(1)

            -- the new node holds no connection, so it must take the next ones
            for _ = 1, 2 do
                assert(http.new():request_uri(uri .. "0.1"))
            end

            -- drop the clients. This only kills the client coroutines: the requests
            -- they made stay parked on the upstream, so their counts are released
            -- whenever those finish, not here. That is fine - a repeated run rebuilds
            -- the upstream from one node, which drops the second one from the heap
            -- and brings it back empty
            for _, th in ipairs(threads) do
                ngx.thread.kill(th)
            end
        }
    }
--- request
GET /t
--- timeout: 10
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out eval
qr/\A(?:proxy request to (?:127\.0\.0\.1|0\.0\.0\.0):1980\n){4}(?:proxy request to 127\.0\.0\.2:1980\n){2}\z/



=== TEST 8: an upstream with no stable key keeps its state private to the picker
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            -- conf_server and ai-proxy-multi build pickers from an upstream table
            -- that carries no resource key, so there is nothing to share state on
            local nodes = {["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1}

            local p1 = least_conn.new(nodes, {})
            local ctx1 = {}
            ctx1.balancer_server = p1.get(ctx1)

            -- a second picker starts empty: it must not see the connection held on
            -- the first one, so it picks the very same node
            local p2 = least_conn.new(nodes, {})
            local ctx2 = {}
            ctx2.balancer_server = p2.get(ctx2)
            ngx.say(ctx2.balancer_server == ctx1.balancer_server and "private" or "shared")

            p1.after_balance(ctx1, false)
            p2.after_balance(ctx2, false)
        }
    }
--- request
GET /t
--- response_body
private



=== TEST 9: scaling out with live WebSocket sessions prefers the new node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local ws_client = require("resty.websocket.client")

            -- an upstream of its own: the balancing state is shared by every picker
            -- built for one upstream, so a test that asserts on it cannot reuse the
            -- upstream another test has been routing connections to
            local function set_upstream(nodes)
                local code, body = t('/apisix/admin/upstreams/2', ngx.HTTP_PUT,
                     [[{"type": "least_conn",
                        "timeout": {"connect": 60, "send": 60, "read": 60},
                        "nodes": ]] .. nodes .. [[}]])
                assert(code < 300, body)
            end

            set_upstream([[{"127.0.0.1:1980": 1, "0.0.0.0:1980": 1}]])
            local code, body = t('/apisix/admin/routes/2', ngx.HTTP_PUT,
                 [[{"uri": "/websocket_hold", "enable_websocket": true, "upstream_id": "2"}]])
            assert(code < 300, body)

            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/websocket_hold"
            ngx.sleep(1)

            -- a session stays in flight until it is closed, which is what makes the
            -- load stick to the nodes that were there before the scale out
            local function hold()
                local wb = ws_client:new({timeout = 60000})
                assert(wb:connect(uri))
                ngx.sleep(60)
            end

            local threads = {}
            for i = 1, 4 do
                threads[i] = assert(ngx.thread.spawn(hold))
            end
            ngx.sleep(1)

            -- scale out while the four sessions are still connected
            set_upstream([[{"127.0.0.1:1980": 1, "0.0.0.0:1980": 1, "127.0.0.2:1980": 1}]])
            ngx.sleep(1)

            -- the new node carries no session, so it must take the next ones
            for i = 5, 6 do
                threads[i] = assert(ngx.thread.spawn(hold))
            end
            ngx.sleep(1)

            -- drop the clients. This only kills the client coroutines: the requests
            -- they made stay parked on the upstream, so their counts are released
            -- whenever those finish, not here. That is fine - a repeated run rebuilds
            -- the upstream from one node, which drops the second one from the heap
            -- and brings it back empty
            for _, th in ipairs(threads) do
                ngx.thread.kill(th)
            end
        }
    }
--- request
GET /t
--- timeout: 10
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out eval
qr/\A(?:proxy request to (?:127\.0\.0\.1|0\.0\.0\.0):1980\n){4}(?:proxy request to 127\.0\.0\.2:1980\n){2}\z/



=== TEST 10: scaling a single-node upstream out counts the sessions it already has
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"

            -- the sessions have to outlast the whole test, and the default upstream
            -- read timeout (6s) would cut them short well before that
            local function set_upstream(nodes)
                local code, body = t('/apisix/admin/upstreams/3', ngx.HTTP_PUT,
                     [[{"type": "least_conn",
                        "timeout": {"connect": 60, "send": 60, "read": 60},
                        "nodes": ]] .. nodes .. [[}]])
                assert(code < 300, body)
            end

            -- a single node is the state a k8s deployment or a discovery service
            -- starts from, and the requests routed while it was alone still have to
            -- be counted, or the scale out cannot see that it is loaded
            set_upstream([[{"127.0.0.1:1980": 1}]])
            -- reuse route 1: two routes cannot both own /mysleep
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 [[{"uri": "/mysleep", "upstream_id": "3"}]])
            assert(code < 300, body)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/mysleep?seconds="
            ngx.sleep(1)

            local threads = {}
            for i = 1, 4 do
                threads[i] = assert(ngx.thread.spawn(function ()
                    http.new():request_uri(uri .. "60")
                end))
            end
            ngx.sleep(1)

            set_upstream([[{"127.0.0.1:1980": 1, "127.0.0.2:1980": 1}]])
            ngx.sleep(1)

            -- the lone node holds four requests, the new one holds none
            for _ = 1, 4 do
                assert(http.new():request_uri(uri .. "0.1"))
            end

            -- abort the sessions rather than outwait them: the log phase still runs,
            -- so the counts are released before the next run of this block
            for _, th in ipairs(threads) do
                ngx.thread.kill(th)
            end
        }
    }
--- request
GET /t
--- timeout: 10
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out eval
qr/\A(?:proxy request to 127\.0\.0\.1:1980\n){4}(?:proxy request to 127\.0\.0\.2:1980\n){4}\z/



=== TEST 11: a weight change is applied without losing the connection count
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            local up = {resource_key = "/upstreams/lc-reweight"}

            local p1 = least_conn.new({["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1}, up, 0)

            -- one connection on each node: equal weight, equal score
            local held = {}
            for i = 1, 2 do
                held[i] = {}
                held[i].balancer_server = p1.get(held[i])
            end

            -- 1980 is given ten times the weight. It carries the same load as 1981,
            -- so it is now the lighter of the two and must win the next picks
            local p2 = least_conn.new({["127.0.0.1:1980"] = 10, ["127.0.0.1:1981"] = 1}, up, 0)

            local picked = {}
            for i = 1, 3 do
                picked[i] = {}
                picked[i].balancer_server = p2.get(picked[i])
                ngx.say(picked[i].balancer_server)
            end

            for _, c in ipairs(picked) do
                p2.after_balance(c, false)
            end
            for _, c in ipairs(held) do
                p2.after_balance(c, false)
            end
        }
    }
--- request
GET /t
--- response_body
127.0.0.1:1980
127.0.0.1:1980
127.0.0.1:1980
