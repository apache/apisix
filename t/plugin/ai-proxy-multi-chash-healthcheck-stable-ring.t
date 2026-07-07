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
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $http_config = <<_EOC_;
        server {
            server_name gpu-a;
            listen 127.0.0.1:16724;
            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.say([[{"choices":[{"message":{"content":"gpu-a","role":"assistant"}}]}]])
                }
            }

            location /status {
                content_by_lua_block {
                    ngx.status = 500
                    ngx.say("fail")
                }
            }
        }

        server {
            server_name gpu-b;
            listen 127.0.0.1:16725;
            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.say([[{"choices":[{"message":{"content":"gpu-b","role":"assistant"}}]}]])
                }
            }

            location /status {
                content_by_lua_block {
                    ngx.say("ok")
                }
            }
        }

        server {
            server_name gpu-c;
            listen 127.0.0.1:16726;
            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.say([[{"choices":[{"message":{"content":"gpu-c","role":"assistant"}}]}]])
                }
            }

            location /status {
                content_by_lua_block {
                    ngx.say("ok")
                }
            }
        }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: ai-proxy-multi chash keeps healthy instance mapping stable when health status changes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson.safe")
            local http = require("resty.http")

            local checks = {
                active = {
                    type = "http",
                    timeout = 1,
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

            local function instance(name, port, weight, with_checks)
                local ins = {
                    name = name,
                    provider = "openai-compatible",
                    weight = weight,
                    auth = {
                        header = {
                            Authorization = "Bearer token",
                        },
                    },
                    options = {
                        model = name,
                    },
                    override = {
                        endpoint = "http://127.0.0.1:" .. port .. "/v1/chat/completions",
                    },
                }
                if with_checks then
                    ins.checks = checks
                end
                return ins
            end

            local function put_route(with_checks)
                local route = {
                    uri = "/ai",
                    plugins = {
                        ["ai-proxy-multi"] = {
                            balancer = {
                                algorithm = "chash",
                                hash_on = "header",
                                key = "X-Sessionid",
                            },
                            instances = {
                                instance("gpu-a", 16724, 3, with_checks),
                                instance("gpu-b", 16725, 6, with_checks),
                                instance("gpu-c", 16726, 10, with_checks),
                            },
                            ssl_verify = false,
                        },
                    },
                }

                local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    json.encode(route)
                )
                assert(code < 300, body)
            end

            local function send(session_id)
                local httpc = http.new()
                local res, err = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/ai",
                    {
                        method = "POST",
                        body = json.encode({messages = {{role = "user", content = "hi"}}}),
                        keepalive = false,
                        headers = {
                            ["Content-Type"] = "application/json",
                            ["X-Sessionid"] = session_id,
                        },
                    }
                )
                assert(res, err)
                assert(res.status == 200, res.status .. ": " .. res.body)
                local body = assert(json.decode(res.body))
                return body.choices[1].message.content
            end

            put_route(false)

            local baseline = {}
            local baseline_a = 0
            local healthy_total = 0
            local total = 120
            for i = 1, total do
                local key = "session-" .. i
                local name = send(key)
                baseline[key] = name
                if name == "gpu-a" then
                    baseline_a = baseline_a + 1
                else
                    healthy_total = healthy_total + 1
                end
            end
            assert(baseline_a > 0, "baseline did not hit gpu-a")
            assert(healthy_total > 0, "baseline did not hit healthy instances")

            put_route(true)
            send("warmup")
            ngx.sleep(3)

            local healthy_moved = 0
            local unhealthy_stayed = 0
            for i = 1, total do
                local key = "session-" .. i
                local before = baseline[key]
                local after = send(key)
                if before == "gpu-a" then
                    if after == "gpu-a" then
                        unhealthy_stayed = unhealthy_stayed + 1
                    end
                elseif after ~= before then
                    healthy_moved = healthy_moved + 1
                end
            end

            assert(healthy_moved == 0,
                   "healthy-instance keys moved after health change: " .. healthy_moved)
            assert(unhealthy_stayed == 0,
                   "unhealthy-instance keys still routed to gpu-a: " .. unhealthy_stayed)

            ngx.say("baseline_a=", baseline_a,
                    ", healthy_total=", healthy_total,
                    ", healthy_moved=", healthy_moved)
        }
    }
--- timeout: 30
--- response_body eval
qr/baseline_a=\d+, healthy_total=\d+, healthy_moved=0/
--- no_error_log
[error]
