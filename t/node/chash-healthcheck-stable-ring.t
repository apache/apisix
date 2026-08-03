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
log_level('warn');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = <<_EOC_;
        server {
            listen 127.0.0.1:16730;

            location /server_port {
                content_by_lua_block {
                    ngx.print("16730")
                }
            }

            location /status {
                return 500;
            }
        }

        server {
            listen 127.0.0.1:16731;

            location /server_port {
                content_by_lua_block {
                    ngx.print("16731")
                }
            }

            location /status {
                return 200;
            }
        }

        server {
            listen 127.0.0.1:16732;

            location /server_port {
                content_by_lua_block {
                    ngx.print("16732")
                }
            }

            location /status {
                return 200;
            }
        }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: chash keeps healthy node mapping stable when health status changes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson.safe")
            local http = require("resty.http")

            local unhealthy_port = "16730"
            local nodes = {
                ["127.0.0.1:" .. unhealthy_port] = 3,
                ["127.0.0.1:16731"] = 6,
                ["127.0.0.1:16732"] = 10,
            }

            local function put_route(with_checks)
                local upstream = {
                    type = "chash",
                    hash_on = "header",
                    key = "X-Sessionid",
                    nodes = nodes,
                }

                if with_checks then
                    upstream.checks = {
                        active = {
                            http_path = "/status",
                            healthy = {
                                interval = 1,
                                http_statuses = {200},
                                successes = 1,
                            },
                            unhealthy = {
                                interval = 1,
                                http_statuses = {500},
                                http_failures = 1,
                                tcp_failures = 1,
                                timeouts = 1,
                            },
                        },
                    }
                end

                local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    json.encode({
                        uri = "/server_port",
                        upstream = upstream,
                    })
                )
                assert(code < 300, body)

                return upstream
            end

            local function send(session_id)
                local httpc = http.new()
                local res, err = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/server_port",
                    {
                        method = "GET",
                        keepalive = false,
                        headers = {
                            ["X-Sessionid"] = session_id,
                        },
                    }
                )
                assert(res, err)
                assert(res.status == 200, res.status .. ": " .. res.body)
                return res.body
            end

            put_route(false)

            local baseline = {}
            local baseline_unhealthy = 0
            local healthy_total = 0
            local total = 120
            for i = 1, total do
                local key = "session-" .. i
                local port = send(key)
                baseline[key] = port
                if port == unhealthy_port then
                    baseline_unhealthy = baseline_unhealthy + 1
                else
                    healthy_total = healthy_total + 1
                end
            end
            assert(baseline_unhealthy > 0, "baseline did not hit unhealthy node")
            assert(healthy_total > 0, "baseline did not hit healthy nodes")

            put_route(true)
            send("warmup")
            ngx.sleep(3)

            local healthy_moved = 0
            local unhealthy_stayed = 0
            for i = 1, total do
                local key = "session-" .. i
                local before = baseline[key]
                local after = send(key)
                if before == unhealthy_port then
                    if after == unhealthy_port then
                        unhealthy_stayed = unhealthy_stayed + 1
                    end
                elseif after ~= before then
                    healthy_moved = healthy_moved + 1
                end
            end

            assert(healthy_moved == 0,
                   "healthy-node keys moved after health change: " .. healthy_moved)
            assert(unhealthy_stayed == 0,
                   "unhealthy-node keys still routed to unhealthy node: " .. unhealthy_stayed)

            ngx.say("baseline_unhealthy=", baseline_unhealthy,
                    ", healthy_total=", healthy_total,
                    ", healthy_moved=", healthy_moved)
        }
    }
--- request
GET /t
--- timeout: 30
--- response_body eval
qr/baseline_unhealthy=\d+, healthy_total=\d+, healthy_moved=0/
--- no_error_log
[error]
