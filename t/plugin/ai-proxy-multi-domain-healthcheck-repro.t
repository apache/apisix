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

log_level("debug");
repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
workers(4);


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 16724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.say([[{"choices":[{"message":{"content":"ok","role":"assistant"}}]}]])
                }
            }

            location /status/domain {
                content_by_lua_block {
                    ngx.sleep(1.2)
                    ngx.say("ok")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: changing DNS order does not rebuild checker while active probe is in flight
--- extra_init_by_lua
    local resolver = require("apisix.core.resolver")
    local original_parse_domain = resolver.parse_domain
    local original_parse_domain_all = resolver.parse_domain_all

    resolver.parse_domain = function(host)
        if host == "multi-ip.example.com" then
            local current = ngx.shared.test:get(host) or "first"
            if current == "first" then
                return "127.0.0.1"
            end
            return "127.0.0.2"
        end
        return original_parse_domain(host)
    end

    resolver.parse_domain_all = function(host)
        if host == "multi-ip.example.com" then
            local current = ngx.shared.test:get(host) or "first"
            if current == "first" then
                return {"127.0.0.1", "127.0.0.2"}
            end
            return {"127.0.0.2", "127.0.0.1"}
        end
        return original_parse_domain_all(host)
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson.safe")
            local http = require("resty.http")
            ngx.shared.test:set("multi-ip.example.com", "first")

            local route = {
                uri = "/ai",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "openai-domain",
                                provider = "openai",
                                weight = 1,
                                priority = 1,
                                auth = {
                                    header = {
                                        Authorization = "Bearer token",
                                    },
                                },
                                options = {
                                    model = "gpt-4",
                                },
                                override = {
                                    endpoint = "http://multi-ip.example.com:16724",
                                },
                                checks = {
                                    active = {
                                        timeout = 3,
                                        http_path = "/status/domain",
                                        host = "multi-ip.example.com",
                                        healthy = {
                                            interval = 1,
                                            successes = 1,
                                        },
                                        unhealthy = {
                                            interval = 1,
                                            http_failures = 1,
                                            tcp_failures = 1,
                                            timeouts = 1,
                                        },
                                    },
                                },
                            },
                            {
                                name = "openai-fallback",
                                provider = "openai",
                                weight = 1,
                                priority = 10,
                                auth = {
                                    header = {
                                        Authorization = "Bearer token",
                                    },
                                },
                                options = {
                                    model = "gpt-4",
                                },
                                override = {
                                    endpoint = "http://127.0.0.1:16724",
                                },
                            },
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

            local function send_ai_http()
                local httpc = http.new()
                local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/ai", {
                    method = "POST",
                    body = json.encode({messages = {{role = "user", content = "hi"}}}),
                    headers = {
                        ["Content-Type"] = "application/json",
                    },
                    keepalive = false,
                })
                if not res then
                    ngx.log(ngx.WARN, "failed to send ai request: ", err)
                    return
                end
                if res.status ~= 200 then
                    ngx.log(ngx.WARN, "unexpected ai response: ", res.status, " ", res.body)
                end
            end

            for _ = 1, 16 do
                send_ai_http()
            end
            ngx.sleep(1.5)

            local stop_at = ngx.now() + 10
            local traffic = ngx.thread.spawn(function()
                while ngx.now() < stop_at do
                    local threads = {}
                    for _ = 1, 8 do
                        threads[#threads + 1] = ngx.thread.spawn(send_ai_http)
                    end
                    for _, th in ipairs(threads) do
                        ngx.thread.wait(th)
                    end
                    ngx.sleep(0.02)
                end
            end)

            local order = "second"
            while ngx.now() < stop_at do
                ngx.shared.test:set("multi-ip.example.com", order)
                order = order == "second" and "first" or "second"
                ngx.sleep(0.7)
            end
            ngx.thread.wait(traffic)

            local deadline = ngx.now() + 1.5
            while ngx.now() < deadline do
                local threads = {}
                for _ = 1, 8 do
                    threads[#threads + 1] = ngx.thread.spawn(send_ai_http)
                end
                for _, th in ipairs(threads) do
                    ngx.thread.wait(th)
                end
                ngx.sleep(0.05)
            end

            ngx.sleep(1.2)
            ngx.say("passed")
        }
    }
--- timeout: 25
--- response_body
passed
--- no_error_log
releasing existing checker:
trying to increment a target that is not in the list
failed to get health check target status
target not found
