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
no_shuffle();
no_root_location();

my $run = time() . "-" . $$;

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $extra_init_by_lua = <<_EOC_;
    -- a route of its own for every run, so that a run never meets the
    -- counters of an earlier one
    local helper = {route = "lconn-conf-update-$run"}

    -- deletes the Redis counters of the route, and only those
    function helper.clear(opts)
        for _, prefix in ipairs({"limit_conn:"}) do
            require("lib.test_redis").delete_keys(
                prefix .. "/apisix/routes/" .. helper.route .. "[:#]*", opts)
        end
    end

    -- the storage key of the counter for this client
    function helper.key(prefix, middle)
        return prefix .. "/apisix/routes/" .. helper.route .. ":" .. (middle or "") .. "127.0.0.1"
    end

    -- updates route 1 and waits for the change to reach the worker
    function helper.set_route(conf, workflow)
        local core = require("apisix.core")
        local t = require("lib.test_admin").test
        local plugins = {["limit-conn"] = conf}
        if workflow then
            plugins.workflow = workflow
        end
        local code, body = t('/apisix/admin/routes/' .. helper.route, ngx.HTTP_PUT, core.json.encode({
            uri = "/mysleep",
            plugins = plugins,
            upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}},
        }))
        if code >= 300 then
            error(body)
        end
        ngx.sleep(0.5)
    end

    function helper.hit(args)
        local http = require("resty.http")
        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/mysleep?" .. args
        local res, err = http.new():request_uri(uri)
        if not res then
            error(err)
        end
        if res.status ~= 200 and res.body:sub(1, 1) == "{" then
            return res.status .. " " .. res.body:gsub("\\n\$", "")
        end
        return tostring(res.status)
    end

    -- keeps n connections open for the given seconds
    function helper.hold(n, args)
        local threads = {}
        for i = 1, n do
            threads[i] = ngx.thread.spawn(helper.hit, args)
        end
        ngx.sleep(0.3)
        return function()
            local res = {}
            for i, th in ipairs(threads) do
                local _, status = ngx.thread.wait(th)
                res[i] = status
            end
            return table.concat(res, " ")
        end
    end

    -- every step updates the configuration of the same counter while two
    -- connections are open: a threshold change applies to them, an unrelated
    -- change keeps them
    function helper.run(conf)
        local out = {}
        helper.set_route(conf)
        local wait = helper.hold(2, "seconds=3")

        conf.conn = 1
        helper.set_route(conf)
        out[#out + 1] = helper.hit("seconds=0")

        conf.conn = 3
        helper.set_route(conf)
        out[#out + 1] = helper.hit("seconds=0")

        conf.conn = 2
        conf.rejected_msg = "rejected"
        conf._meta = {filter = {{"remote_addr", "==", "127.0.0.1"}}}
        helper.set_route(conf)
        out[#out + 1] = helper.hit("seconds=0")

        out[#out + 1] = wait()
        out[#out + 1] = helper.hit("seconds=0")
        ngx.say(table.concat(out, "\\n"))
    end

    package.loaded["conf_update_helper"] = helper
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);
});

run_tests;

__DATA__

=== TEST 1: local, a configuration update keeps the open connections
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").run({
                conn = 2,
                burst = 0,
                default_conn_delay = 0.1,
                rejected_code = 503,
                key = "remote_addr",
                policy = "local",
            })
        }
    }
--- response_body
503
200
503 {"error_msg":"rejected"}
200 200
200
--- timeout: 10



=== TEST 2: redis, a configuration update keeps the open connections
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            require("conf_update_helper").run({
                conn = 2,
                burst = 0,
                default_conn_delay = 0.1,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
            })
        }
    }
--- response_body
503
200
503 {"error_msg":"rejected"}
200 200
200
--- timeout: 10



=== TEST 3: redis-cluster, a configuration update keeps the open connections
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            require("conf_update_helper").run({
                conn = 2,
                burst = 0,
                default_conn_delay = 0.1,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis-cluster",
                redis_cluster_nodes = {"127.0.0.1:5000", "127.0.0.1:5001"},
                redis_cluster_name = "redis-cluster-conf-update",
            })
        }
    }
--- response_body
503
200
503 {"error_msg":"rejected"}
200 200
200
--- timeout: 10



=== TEST 4: redis, a smaller key_ttl does not expire the leases admitted before it
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            local helper = require("conf_update_helper")
            local conf = {
                conn = 5,
                burst = 0,
                default_conn_delay = 0.1,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
                key_ttl = 100,
            }
            helper.set_route(conf)
            local wait = helper.hold(1, "seconds=2")

            conf.key_ttl = 1
            helper.set_route(conf)
            local wait2 = helper.hold(1, "seconds=0.1")

            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            local ttl = red:ttl(helper.key("limit_conn:"))
            ngx.say("ttl > 90: ", ttl > 90)
            ngx.say(wait(), " ", wait2())
        }
    }
--- response_body
ttl > 90: true
200 200
--- timeout: 10



=== TEST 5: redis, two rules counting the same key each release their own lease
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            local helper = require("conf_update_helper")
            helper.set_route({
                default_conn_delay = 0.1,
                rejected_code = 503,
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
                rules = {
                    {conn = 5, burst = 0, key = "$remote_addr"},
                    {conn = 5, burst = 0, key = "${remote_addr}"},
                },
            })

            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            local key = helper.key("limit_conn:")
            local wait = helper.hold(1, "seconds=0.5")
            ngx.say("leases while open: ", (red:zcard(key)))
            ngx.say(wait())
            ngx.sleep(0.2)
            ngx.say("leases after close: ", (red:zcard(key)))
        }
    }
--- response_body
leases while open: 2
200
leases after close: 0
--- timeout: 10



=== TEST 6: a workflow action does not share the counter of the plugin on the same route
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            local helper = require("conf_update_helper")
            local out = {}
            for _, policy in ipairs({"local", "redis"}) do
                local function conf(key)
                    return {
                        conn = 1,
                        burst = 0,
                        default_conn_delay = 0.1,
                        rejected_code = 503,
                        key_type = "var_combination",
                        key = key,
                        policy = policy,
                        redis_host = "127.0.0.1",
                        redis_port = 6379,
                    }
                end
                -- the plugin counts "tenant:1", the action with _vid 1 "tenant"
                helper.set_route(conf("$arg_tenant:1"), {
                    rules = {{
                        case = {{"arg_wf", "==", "1"}},
                        actions = {{"limit-conn", conf("$arg_tenant")}},
                    }},
                })
                local tenant = "tenant=" .. policy
                local wait = helper.hold(1, tenant .. "&wf=1&seconds=1")
                local res = {
                    helper.hit(tenant .. "&seconds=0"),
                    helper.hit(tenant .. "&wf=1&seconds=0"),
                    wait(),
                }
                out[#out + 1] = policy .. ": " .. table.concat(res, " ")
            end
            ngx.say(table.concat(out, "\n"))
        }
    }
--- response_body
local: 200 503 200
redis: 200 503 200
--- timeout: 10



=== TEST 7: redis, a lease is not admitted into a key that expires before it
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            helper.clear()
            helper.set_route({
                conn = 5,
                burst = 0,
                default_conn_delay = 0.1,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
                key_ttl = 3,
            })
            local wait = helper.hold(1, "seconds=1")

            -- 2800ms left reads as a TTL of 3 seconds
            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            local key = helper.key("limit_conn:")
            assert(red:pexpire(key, 2800) == 1)
            local status = helper.hit("seconds=0")
            ngx.say("pttl > 2900: ", red:pttl(key) > 2900)
            ngx.say(wait(), " ", status)
        }
    }
--- response_body
pttl > 2900: true
200 200
--- timeout: 10



=== TEST 8: the cleanup of a test only deletes the keys of its own route
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            local peers = {
                "limit_conn:/apisix/routes/peer:client/apisix/routes/" .. helper.route .. ":blue",
                "limit_conn:/apisix/routes/" .. helper.route .. "-peer:127.0.0.1",
            }
            for _, key in ipairs(peers) do
                assert(red:zadd(key, ngx.time() + 60, "peer-lease"))
            end
            assert(red:zadd(helper.key("limit_conn:"), ngx.time() + 60, "own-lease"))

            helper.clear()
            for _, key in ipairs(peers) do
                ngx.say("peer kept: ", red:zscore(key, "peer-lease") ~= ngx.null)
                red:del(key)
            end
            ngx.say("own deleted: ", red:exists(helper.key("limit_conn:")) == 0)
        }
    }
--- response_body
peer kept: true
peer kept: true
own deleted: true



=== TEST 9: redis, the late release of a lease admitted before an update removes only that lease
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            helper.clear()
            local conf = {
                conn = 5,
                burst = 0,
                default_conn_delay = 0.1,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
            }
            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            local key = helper.key("limit_conn:")

            helper.set_route(conf)
            local wait_old = helper.hold(1, "seconds=1.5")
            local old = red:zrange(key, 0, -1)

            conf.conn = 4
            helper.set_route(conf)
            local wait_new = helper.hold(1, "seconds=3")
            local new
            for _, member in ipairs(red:zrange(key, 0, -1)) do
                if member ~= old[1] then
                    new = member
                end
            end

            -- the lease of the request admitted first is released after the update
            ngx.say(wait_old())
            ngx.sleep(0.3)
            local left = red:zrange(key, 0, -1)
            ngx.say("leases: ", #old, " then ", #left, ", the new one left: ", left[1] == new)
            ngx.say(wait_new())
        }
    }
--- response_body
200
leases: 1 then 1, the new one left: true
200
--- timeout: 10
