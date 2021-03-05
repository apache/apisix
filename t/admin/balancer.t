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
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $init_by_lua_block = <<_EOC_;
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    function test(route, ctx, count)
        local balancer = require("apisix.balancer")
        local res = {}
        for i = 1, count or 12 do
            ctx.balancer_try_count = 0
            local server, err = balancer.pick_server(route, ctx)
            if err then
                ngx.say("failed: ", err)
            end

            core.log.warn("host: ", server.host, " port: ", server.port)
            res[server.host] = (res[server.host] or 0) + 1
        end

        local keys = {}
        for k,v in pairs(res) do
            table.insert(keys, k)
        end
        table.sort(keys)

        for _, key in ipairs(keys) do
            ngx.say("host: ", key, " count: ", res[key])
        end

        ctx.server_picker = nil
    end
_EOC_
    $block->set_value("init_by_lua_block", $init_by_lua_block);
});

run_tests;

__DATA__

=== TEST 1: roundrobin with same weight
--- config
    location /t {
        content_by_lua_block {
            local up_conf = {
                type = "roundrobin",
                nodes = {
                    {host = "39.97.63.215", port = 80, weight = 1},
                    {host = "39.97.63.216", port = 81, weight = 1},
                    {host = "39.97.63.217", port = 82, weight = 1},
                }
            }
            local ctx = {conf_version = 1}
            ctx.upstream_conf = up_conf
            ctx.upstream_version = "ver"
            ctx.upstream_key = up_conf.type .. "#route_" .. "id"

            test(route, ctx)
        }
    }
--- request
GET /t
--- response_body
host: 39.97.63.215 count: 4
host: 39.97.63.216 count: 4
host: 39.97.63.217 count: 4
--- no_error_log
[error]



=== TEST 2: roundrobin with different weight
--- config
    location /t {
        content_by_lua_block {
            local up_conf = {
                type = "roundrobin",
                nodes = {
                    {host = "39.97.63.215", port = 80, weight = 1},
                    {host = "39.97.63.216", port = 81, weight = 2},
                    {host = "39.97.63.217", port = 82, weight = 3},
                }
            }
            local ctx = {conf_version = 1}
            ctx.upstream_conf = up_conf
            ctx.upstream_version = "ver"
            ctx.upstream_key = up_conf.type .. "#route_" .. "id"

            test(route, ctx)
        }
    }
--- request
GET /t
--- response_body
host: 39.97.63.215 count: 2
host: 39.97.63.216 count: 4
host: 39.97.63.217 count: 6
--- no_error_log
[error]



=== TEST 3: roundrobin, cached server picker by version
--- config
    location /t {
        content_by_lua_block {
            local up_conf = {
                type = "roundrobin",
                nodes = {
                    {host = "39.97.63.215", port = 80, weight = 1},
                    {host = "39.97.63.216", port = 81, weight = 1},
                    {host = "39.97.63.217", port = 82, weight = 1},
                }
            }
            local ctx = {}
            ctx.upstream_conf = up_conf
            ctx.upstream_version = 1
            ctx.upstream_key = up_conf.type .. "#route_" .. "id"

            test(route, ctx)

            -- cached by version
            up_conf.nodes = {
                {host = "39.97.63.218", port = 80, weight = 1},
                {host = "39.97.63.219", port = 80, weight = 0},
            }
            test(route, ctx)

            -- update, version changed
            ctx.upstream_version = 2
            test(route, ctx)
        }
    }
--- request
GET /t
--- response_body
host: 39.97.63.215 count: 4
host: 39.97.63.216 count: 4
host: 39.97.63.217 count: 4
host: 39.97.63.215 count: 4
host: 39.97.63.216 count: 4
host: 39.97.63.217 count: 4
host: 39.97.63.218 count: 12
--- no_error_log
[error]



=== TEST 4: chash
--- config
    location /t {
        content_by_lua_block {
            local up_conf = {
                type = "chash",
                key  = "remote_addr",
                nodes = {
                    {host = "39.97.63.215", port = 80, weight = 1},
                    {host = "39.97.63.216", port = 81, weight = 1},
                    {host = "39.97.63.217", port = 82, weight = 1},
                }
            }
            local ctx = {
                var = {remote_addr = "127.0.0.1"},
            }
            ctx.upstream_conf = up_conf
            ctx.upstream_version = 1
            ctx.upstream_key = up_conf.type .. "#route_" .. "id"

            test(route, ctx)

            -- cached by version
            up_conf.nodes = {
                {host = "39.97.63.218", port = 80, weight = 1},
                {host = "39.97.63.219", port = 80, weight = 0},
            }
            test(route, ctx)

            -- update, version changed
            ctx.upstream_version = 2
            test(route, ctx)
        }
    }
--- request
GET /t
--- response_body
host: 39.97.63.215 count: 12
host: 39.97.63.215 count: 12
host: 39.97.63.218 count: 12
--- no_error_log
[error]



=== TEST 5: return item directly if only have one item in `nodes`
--- config
    location /t {
        content_by_lua_block {
            local up_conf = {
                type = "roundrobin",
                nodes = {
                    {host = "39.97.63.215", port = 80, weight = 1},
                    {host = "39.97.63.216", port = 81, weight = 1},
                    {host = "39.97.63.217", port = 82, weight = 1},
                }
            }
            local ctx = {}
            ctx.upstream_conf = up_conf
            ctx.upstream_version = 1
            ctx.upstream_key = up_conf.type .. "#route_" .. "id"

            test(route, ctx)

            -- one item in nodes, return it directly
            up_conf.nodes = {
                {host = "39.97.63.218", port = 80, weight = 1},
            }
            test(route, ctx)
        }
    }
--- request
GET /t
--- response_body
host: 39.97.63.215 count: 4
host: 39.97.63.216 count: 4
host: 39.97.63.217 count: 4
host: 39.97.63.218 count: 12
--- no_error_log
[error]
