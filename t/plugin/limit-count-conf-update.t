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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $extra_init_by_lua = <<_EOC_;
    local helper = {}

    -- updates route 1 and waits for the change to reach the worker
    function helper.set_route(conf, workflow)
        local core = require("apisix.core")
        local t = require("lib.test_admin").test
        local plugins = {["limit-count"] = conf}
        if workflow then
            plugins.workflow = workflow
        end
        local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, core.json.encode({
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
            require("lib.test_redis").flush_all()
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
            require("lib.test_redis").flush_all()
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
            require("lib.test_redis").flush_all()
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

            -- a node judges on the quota it synced last, so the new count
            -- applies once the next sync is done, on the same consumption
            conf.count = 4
            helper.set_route(conf)
            hit()
            ngx.sleep(0.5)
            hit()
            hit()
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
503
200 remaining 1 reset <= 60
200 remaining 0 reset <= 60
503
503 {"error_msg":"rejected"}
200 remaining 3 reset > 60
--- timeout: 15



=== TEST 5: a workflow action does not share the counter of the plugin on the same route
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_all()
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
