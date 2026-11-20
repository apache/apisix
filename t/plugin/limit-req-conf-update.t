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
    function helper.set_route(conf)
        local core = require("apisix.core")
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, core.json.encode({
            uri = "/hello",
            plugins = {["limit-req"] = conf},
            upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}},
        }))
        if code >= 300 then
            error(body)
        end
        ngx.sleep(0.5)
    end

    function helper.hit()
        local http = require("resty.http")
        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
        local res, err = http.new():request_uri(uri)
        if not res then
            error(err)
        end
        if res.status ~= 200 and res.body:sub(1, 1) == "{" then
            return res.status .. " " .. res.body:gsub("\\n\$", "")
        end
        return tostring(res.status)
    end

    -- every step updates the configuration of the same bucket: an unrelated
    -- change keeps it, a threshold change applies to it
    function helper.run(conf)
        local out = {}
        local function hit()
            out[#out + 1] = helper.hit()
        end

        helper.set_route(conf)
        hit()
        hit()
        hit()

        conf.rejected_msg = "rejected"
        conf._meta = {filter = {{"remote_addr", "==", "127.0.0.1"}}}
        helper.set_route(conf)
        hit()

        -- the bucket still holds most of the second request at 0.1 req/s
        conf.burst = 2
        helper.set_route(conf)
        hit()
        hit()

        ngx.say(table.concat(out, "\\n"))
    end

    package.loaded["conf_update_helper"] = helper
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);
});

run_tests;

__DATA__

=== TEST 1: local, a configuration update keeps the bucket
--- config
    location /t {
        content_by_lua_block {
            require("conf_update_helper").run({
                rate = 0.1,
                burst = 1,
                nodelay = true,
                rejected_code = 503,
                key = "remote_addr",
                policy = "local",
            })
        }
    }
--- response_body
200
200
503
503 {"error_msg":"rejected"}
200
503 {"error_msg":"rejected"}
--- timeout: 10



=== TEST 2: redis, a configuration update keeps the bucket
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_all()
            require("conf_update_helper").run({
                rate = 0.1,
                burst = 1,
                nodelay = true,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
            })
        }
    }
--- response_body
200
200
503
503 {"error_msg":"rejected"}
200
503 {"error_msg":"rejected"}
--- timeout: 10



=== TEST 3: redis-cluster, a configuration update keeps the bucket
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_all()
            require("conf_update_helper").run({
                rate = 0.1,
                burst = 1,
                nodelay = true,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis-cluster",
                redis_cluster_nodes = {"127.0.0.1:5000", "127.0.0.1:5001"},
                redis_cluster_name = "redis-cluster-conf-update",
            })
        }
    }
--- response_body
200
200
503
503 {"error_msg":"rejected"}
200
503 {"error_msg":"rejected"}
--- timeout: 10



=== TEST 4: redis, a shorter ttl does not expire a bucket written before it
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_all()
            local helper = require("conf_update_helper")
            -- the bucket of 0.1 req/s with a burst of 10 needs 101s to drain
            local conf = {
                rate = 0.1,
                burst = 10,
                nodelay = true,
                rejected_code = 503,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
                redis_port = 6379,
            }
            helper.set_route(conf)
            helper.hit()
            helper.hit()

            -- a bucket of 10 req/s with a burst of 1 lives 2s
            conf.rate = 10
            conf.burst = 1
            helper.set_route(conf)
            helper.hit()

            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            local ttl = red:ttl("limit_req:/apisix/routes/1:127.0.0.1")
            ngx.say("ttl > 90: ", ttl > 90)
        }
    }
--- response_body
ttl > 90: true
--- timeout: 10
