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

    if (!defined $block->request && !defined $block->stream_request) {
        $block->set_value("request", "GET /t");
    }

    # t::APISIX renders worker_connections 128 into nginx.conf, so the
    # configuration has to say the same for the connection gauges to pass
    # their self check
    if (!defined $block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", <<_EOC_);
stream_plugins:
    - prometheus
nginx_config:
    max_running_timers: 1234
    max_pending_timers: 5678
    event:
        worker_connections: 128
plugin_attr:
    prometheus:
        refresh_interval: 0.1
_EOC_
    }
});

run_tests;

__DATA__

=== TEST 1: pre-create public API route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/metrics',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "public-api": {}
                    },
                    "uri": "/apisix/prometheus/metrics"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: every process reports its timers, connection slots and Lua memory
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local http = require("resty.http")
            local httpc = http.new()
            local res = assert(httpc:request_uri(
                "http://127.0.0.1:1984/apisix/prometheus/metrics"))
            local patterns = {
                [[apisix_nginx_timers\{process="worker-0",subsystem="http",state="running"\} \d+\n]],
                [[apisix_nginx_timers\{process="worker-0",subsystem="http",state="pending"\} \d+]],
                [[apisix_nginx_timers\{process="privileged-agent",subsystem="http",state="running"\} \d+]],
                [[apisix_nginx_timers_max\{state="running"\} 1234\n]],
                [[apisix_nginx_timers_max\{state="pending"\} 5678\n]],
                [[apisix_nginx_process_connections\{process="worker-0"\} [1-9]\d*\n]],
                [[apisix_nginx_process_connections\{process="privileged-agent"\} [1-9]\d*\n]],
                [[apisix_nginx_process_connections_max\{process="worker-0"\} 128\n]],
                [[apisix_nginx_process_connections_max\{process="privileged-agent"\} 512\n]],
                [[apisix_nginx_lua_memory_bytes\{process="worker-0",subsystem="http"\} [1-9]\d*]],
                [[apisix_nginx_lua_memory_bytes\{process="privileged-agent",subsystem="http"\} [1-9]\d*]],
            }
            for _, p in ipairs(patterns) do
                if not ngx.re.find(res.body, p, "jo") then
                    ngx.say("missing ", p)
                end
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 3: connection slots held by cosockets show up in the worker's gauge
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")

            local function worker_connections()
                ngx.sleep(0.5)
                local httpc = http.new()
                local res = assert(httpc:request_uri(
                    "http://127.0.0.1:1984/apisix/prometheus/metrics"))
                local m = ngx.re.match(res.body,
                    [[apisix_nginx_process_connections\{process="worker-0"\} (\d+)]], "jo")
                return tonumber(m[1])
            end

            local before = worker_connections()

            local socks = {}
            for i = 1, 20 do
                local sock = ngx.socket.tcp()
                assert(sock:connect("127.0.0.1", 1980))
                socks[i] = sock
            end

            local held = worker_connections()

            for _, sock in ipairs(socks) do
                sock:close()
            end

            local released = worker_connections()

            ngx.say("held: ", held - before >= 20)
            ngx.say("released: ", held - released >= 20)
        }
    }
--- response_body
held: true
released: true



=== TEST 4: connection gauges stay out when the slots do not match worker_connections
--- extra_yaml_config
plugin_attr:
    prometheus:
        refresh_interval: 0.1
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local http = require("resty.http")
            local httpc = http.new()
            local res = assert(httpc:request_uri(
                "http://127.0.0.1:1984/apisix/prometheus/metrics"))
            ngx.say(ngx.re.find(res.body, "apisix_nginx_process_connections", "jo") == nil)
            ngx.say(ngx.re.find(res.body,
                [[apisix_nginx_timers\{process="worker-0",subsystem="http",state="pending"\}]],
                "jo") ~= nil)
        }
    }
--- response_body
true
true
--- error_log
process connection metrics are disabled: worker connection slots read as 128, but worker_connections is 10620



=== TEST 5: the stream Lua VM of every process reports as well
--- stream_server_config
    content_by_lua_block {
        ngx.req.socket():receive()
        ngx.sleep(0.5)
        local http = require("resty.http")
        local httpc = http.new()
        local res = assert(httpc:request_uri(
            "http://127.0.0.1:1984/apisix/prometheus/metrics"))
        local patterns = {
            [[apisix_nginx_timers\{process="worker-0",subsystem="stream",state="running"\} \d+\n]],
            [[apisix_nginx_timers\{process="worker-0",subsystem="stream",state="pending"\} \d+]],
            [[apisix_nginx_timers\{process="privileged-agent",subsystem="stream",state="pending"\} \d+]],
            [[apisix_nginx_lua_memory_bytes\{process="worker-0",subsystem="stream"\} [1-9]\d*]],
            [[apisix_nginx_lua_memory_bytes\{process="privileged-agent",subsystem="stream"\} [1-9]\d*]],
        }
        for _, p in ipairs(patterns) do
            if not ngx.re.find(res.body, p, "jo") then
                ngx.say("missing ", p)
            end
        end
        ngx.say("done")
    }
--- stream_request
ping
--- stream_response
done
