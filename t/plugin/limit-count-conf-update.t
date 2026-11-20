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
    local helper = {route = "lc-conf-update-$run"}

    -- deletes the Redis counters of the route, and only those
    function helper.clear(opts)
        for _, prefix in ipairs({"plugin-limit-count:v1:", "plugin-limit-count:"}) do
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
        local plugins = {["limit-count"] = conf}
        if workflow then
            plugins.workflow = workflow
        end
        local code, body = t('/apisix/admin/routes/' .. helper.route, ngx.HTTP_PUT, core.json.encode({
            uri = "/hello",
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
        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
        if args then
            uri = uri .. "?" .. args
        end
        local res, err = http.new():request_uri(uri)
        if not res then
            error(err)
        end
        if res.status ~= 200 then
            -- only a configured rejected_msg, not the default error page
            if res.body:sub(1, 1) == "{" then
                return res.status .. " " .. res.body:gsub("\\n\$", "")
            end
            return tostring(res.status)
        end
        return res.status .. " remaining " .. res.headers["X-RateLimit-Remaining"]
               .. " reset " .. (tonumber(res.headers["X-RateLimit-Reset"]) > 60
                                and "> 60" or "<= 60")
    end

    -- every step updates the configuration of the same counter: a threshold
    -- change applies to what was consumed, an unrelated change keeps it, and
    -- a new time_window starts a new window
    function helper.run(conf)
        local out = {}
        local function hit()
            out[#out + 1] = helper.hit()
        end

        helper.set_route(conf)
        hit()
        hit()

        conf.count = 5
        helper.set_route(conf)
        hit()

        conf.rejected_msg = "rejected"
        conf._meta = {filter = {{"remote_addr", "==", "127.0.0.1"}}}
        helper.set_route(conf)
        hit()

        conf.count = 3
        helper.set_route(conf)
        hit()

        conf.time_window = 120
        helper.set_route(conf)
        hit()

        ngx.say(table.concat(out, "\\n"))
    end

    package.loaded["conf_update_helper"] = helper
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);
});

run_tests;

__DATA__

=== TEST 1: local, a configuration update keeps the counter
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").run({
                count = 3,
                time_window = 60,
                rejected_code = 503,
                key = "remote_addr",
                policy = "local",
            })
        }
    }
--- response_body
200 remaining 2 reset <= 60
200 remaining 1 reset <= 60
200 remaining 2 reset <= 60
200 remaining 1 reset <= 60
503 {"error_msg":"rejected"}
200 remaining 2 reset > 60
--- timeout: 10



=== TEST 2: redis, a configuration update keeps the counter
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            require("conf_update_helper").run({
                count = 3,
                time_window = 60,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
            })
        }
    }
--- response_body
200 remaining 2 reset <= 60
200 remaining 1 reset <= 60
200 remaining 2 reset <= 60
200 remaining 1 reset <= 60
503 {"error_msg":"rejected"}
200 remaining 2 reset > 60
--- timeout: 10



=== TEST 3: redis-cluster, a configuration update keeps the counter
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            require("conf_update_helper").run({
                count = 3,
                time_window = 60,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis-cluster",
                redis_cluster_nodes = {"127.0.0.1:5000", "127.0.0.1:5001"},
                redis_cluster_name = "redis-cluster-conf-update",
            })
        }
    }
--- response_body
200 remaining 2 reset <= 60
200 remaining 1 reset <= 60
200 remaining 2 reset <= 60
200 remaining 1 reset <= 60
503 {"error_msg":"rejected"}
200 remaining 2 reset > 60
--- timeout: 10



=== TEST 4: redis with delayed sync, a configuration update keeps the counter
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            local helper = require("conf_update_helper")
            local conf = {
                count = 2,
                time_window = 60,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
                sync_interval = 0.2,
            }
            local out = {}
            local function hit()
                out[#out + 1] = helper.hit()
            end

            helper.set_route(conf)
            hit()
            hit()
            hit()
            ngx.sleep(0.5)

            -- the quota synced under the previous count applies the new one
            conf.count = 4
            helper.set_route(conf)
            hit()
            hit()
            hit()
            ngx.sleep(0.5)

            conf.count = 3
            helper.set_route(conf)
            hit()

            conf.rejected_msg = "rejected"
            helper.set_route(conf)
            hit()

            conf.time_window = 120
            helper.set_route(conf)
            hit()

            ngx.say(table.concat(out, "\n"))
        }
    }
--- response_body
200 remaining 1 reset <= 60
200 remaining 0 reset <= 60
503
200 remaining 1 reset <= 60
200 remaining 0 reset <= 60
503
503
503 {"error_msg":"rejected"}
200 remaining 2 reset > 60
--- timeout: 15



=== TEST 5: a workflow action does not share the counter of the plugin on the same route
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            local helper = require("conf_update_helper")
            local out = {}
            for _, policy in ipairs({"local", "redis"}) do
                local function conf(key)
                    return {
                        count = 1,
                        time_window = 60,
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
                        actions = {{"limit-count", conf("$arg_tenant")}},
                    }},
                })
                local res = {}
                for _, args in ipairs({"tenant=" .. policy .. "&wf=1", "tenant=" .. policy,
                                       "tenant=" .. policy .. "&wf=1", "tenant=" .. policy}) do
                    res[#res + 1] = helper.hit(args):sub(1, 3)
                end
                out[#out + 1] = policy .. ": " .. table.concat(res, " ")
            end
            ngx.say(table.concat(out, "\n"))
        }
    }
--- response_body
local: 200 200 503 503
redis: 200 200 503 503
--- timeout: 10



=== TEST 6: redis with delayed sync, a sync of the previous configuration does not bring back its count
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").clear()
            local helper = require("conf_update_helper")
            local conf = {
                count = 2,
                time_window = 60,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
                sync_interval = 2,
            }
            local out = {}
            local function hit()
                out[#out + 1] = helper.hit()
            end

            -- starts the syncer of this configuration, due in 2s
            helper.set_route(conf)
            hit()

            conf.count = 4
            helper.set_route(conf)
            ngx.sleep(0.5)
            hit()

            -- the syncer of count 2 has synced the key, the one of count 4 not yet
            ngx.sleep(1.5)
            hit()

            ngx.say(table.concat(out, "\n"))
        }
    }
--- response_body
200 remaining 1 reset <= 60
200 remaining 2 reset <= 60
200 remaining 1 reset <= 60
--- timeout: 10



=== TEST 7: a new sliding window length starts a new window, also with the same window id
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            -- floor(now / time_window) is 1 for both lengths
            local conf = {
                count = 3,
                time_window = 1000000000,
                window_type = "sliding",
                rejected_code = 503,
                key = "remote_addr",
                policy = "local",
            }
            local out = {}
            helper.set_route(conf)
            out[#out + 1] = helper.hit():match("^%d+ remaining %d+")
            out[#out + 1] = helper.hit():match("^%d+ remaining %d+")

            conf.time_window = 1000000001
            helper.set_route(conf)
            out[#out + 1] = helper.hit():match("^%d+ remaining %d+")
            ngx.say(table.concat(out, "\n"))
        }
    }
--- response_body
200 remaining 2
200 remaining 1
200 remaining 2
--- timeout: 10



=== TEST 8: redis with delayed sync, a pending delta is synced to the Redis it was counted for
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            helper.clear({database = 14})
            helper.clear({database = 15})
            local conf = {
                count = 10,
                time_window = 60,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
                redis_database = 14,
                sync_interval = 1,
            }

            -- two requests wait to be synced to database 14
            helper.set_route(conf)
            helper.hit()
            helper.hit()

            conf.redis_database = 15
            helper.set_route(conf)
            helper.hit()

            -- both syncers are done
            ngx.sleep(2)
            local key = helper.key("plugin-limit-count:v1:", "60:")
            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            for _, db in ipairs({14, 15}) do
                assert(red:select(db))
                ngx.say("database ", db, ": ", (red:get(key)))
            end
        }
    }
--- response_body
database 14: 2
database 15: 1
--- timeout: 10



=== TEST 9: redis with delayed sync, a new count applies to what the local fallback rejected
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            -- nothing listens on the port, so the syncer falls back to the
            -- local limiter, which has already counted 3
            local conf = {
                count = 2,
                time_window = 60,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 1,
                sync_interval = 0.2,
            }
            local key = "/apisix/routes/" .. helper.route .. ":60:127.0.0.1"
            assert(ngx.shared["plugin-limit-count"]:incr(key, 3, 0, 60))
            assert(ngx.shared["plugin-limit-count-reset-header"]:set(key, ngx.now() + 60, 60))
            local out = {}
            local function hit()
                out[#out + 1] = helper.hit()
            end

            helper.set_route(conf)
            hit()

            -- one over the new count of 5 is left
            conf.count = 5
            helper.set_route(conf)
            hit()

            ngx.say(table.concat(out, "\n"))
        }
    }
--- response_body
503
200 remaining 1 reset <= 60
--- error_log
sync to redis failed
--- timeout: 10



=== TEST 10: a workflow action keeps its counter when the rules are reordered, not when its case changes
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            local function action(case, count)
                return {
                    case = case,
                    actions = {{"limit-count", {
                        count = count,
                        time_window = 60,
                        rejected_code = 503,
                        key = "remote_addr",
                        policy = "local",
                    }}},
                }
            end
            local route_conf = {count = 100, time_window = 60, key = "remote_addr"}
            local a = action({{"arg_a", "==", "1"}}, 2)
            local b = action({{"arg_b", "==", "1"}}, 3)
            local out = {}
            local function hit(args)
                out[#out + 1] = args .. ": " .. helper.hit(args):match("^%d+ remaining %d+")
            end

            helper.set_route(route_conf, {rules = {a, b}})
            hit("a=1")

            helper.set_route(route_conf, {rules = {b, a}})
            hit("a=1")
            hit("b=1")

            a.case = {{"arg_a", "==", "2"}}
            helper.set_route(route_conf, {rules = {b, a}})
            hit("a=2")

            ngx.say(table.concat(out, "\n"))
        }
    }
--- response_body
a=1: 200 remaining 1
a=1: 200 remaining 0
b=1: 200 remaining 2
a=2: 200 remaining 1
--- timeout: 10



=== TEST 11: redis with delayed sync, a raised count on a sliding window is judged on the counts, not on the old remaining
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            helper.clear()
            -- a window length the current time is 0.4 into, with 8 requests
            -- in the previous window and 1 in the current one
            local window = math.floor(ngx.now() / 1.4)
            local key = helper.key("plugin-limit-count:", window .. ":")
            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            assert(red:set(key .. ".0.counter", 8, "EX", 3600))
            assert(red:set(key .. ".1.counter", 1, "EX", 3600))

            local conf = {
                count = 2,
                time_window = window,
                window_type = "sliding",
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
                sync_interval = 1,
            }
            helper.set_route(conf)
            ngx.say(helper.hit())

            conf.count = 10
            helper.set_route(conf)
            local weight = (window - ngx.now() % window) / window
            local expected = math.floor(10 - 1 - 8 * weight) - 1
            local res = helper.hit()
            ngx.say("judged on the counts: ",
                    res:match("^200 remaining (%d+)") == tostring(expected) or res)
        }
    }
--- response_body
503
judged on the counts: true
--- timeout: 10



=== TEST 12: redis with delayed sync, a pending delta is synced with the window algorithm it was counted with
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            helper.clear()
            local conf = {
                count = 10,
                time_window = 60,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
                sync_interval = 1,
            }
            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            local fixed_key = helper.key("plugin-limit-count:v1:", "60:")
            local function sliding_count()
                local sum = 0
                for _, k in ipairs(red:keys(helper.key("plugin-limit-count:", "60:") .. ".*")) do
                    sum = sum + tonumber(red:get(k))
                end
                return sum
            end

            -- two requests wait to be synced to the fixed window
            helper.set_route(conf)
            helper.hit()
            helper.hit()
            ngx.say("fixed before the sync: ", (red:get(fixed_key)))

            conf.window_type = "sliding"
            helper.set_route(conf)
            helper.hit()

            -- both syncers are done
            ngx.sleep(2)
            ngx.say("fixed: ", (red:get(fixed_key)), ", sliding: ", sliding_count())
        }
    }
--- response_body
fixed before the sync: 0
fixed: 2, sliding: 1
--- timeout: 10



=== TEST 13: redis with delayed sync, other credentials for the same Redis keep the pending delta
--- config
    location /t {
        content_by_lua_block {
            local helper = require("conf_update_helper")
            helper.clear()
            local conf = {
                count = 2,
                time_window = 60,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
                sync_interval = 1,
            }
            local out = {}
            local function hit()
                out[#out + 1] = helper.hit():match("^%d+")
            end

            -- two requests wait to be synced
            helper.set_route(conf)
            hit()
            hit()

            -- the user alice has access to the same keys
            conf.redis_username = "alice"
            conf.redis_password = "somepassword"
            helper.set_route(conf)
            hit()

            ngx.say(table.concat(out, " "))
        }
    }
--- response_body
200 200 503
--- timeout: 10
