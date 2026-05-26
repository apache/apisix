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
            listen 127.0.0.1:16724;
            listen 127.0.0.2:16724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.say(string.format(
                        [[{"host":"%s","server_addr":"%s","choices":[{"message":{"content":"ok","role":"assistant"}}]}]],
                        ngx.req.get_headers()["host"],
                        ngx.var.server_addr
                    ))
                }
            }

            location /status/domain {
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

=== TEST 1: domain healthcheck uses stable resolved IP set and request uses selected IP
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local resolver = require("apisix.core.resolver")
            local json = require("cjson.safe")
            local original_parse_domain_all = resolver.parse_domain_all
            local dns_query_count = 0

            resolver.parse_domain_all = function(host)
                if host == "multi-ip.example.com" then
                    dns_query_count = dns_query_count + 1
                    if dns_query_count % 2 == 1 then
                        return {"127.0.0.2", "127.0.0.1"}
                    end
                    return {"127.0.0.1", "127.0.0.2"}
                end
                return original_parse_domain_all(host)
            end

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
                                        timeout = 1,
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
                                priority = 0,
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

            local function send_ai()
                local code, _, body = t("/ai",
                    ngx.HTTP_POST,
                    json.encode({messages = {{role = "user", content = "hi"}}}),
                    nil,
                    {
                        ["Content-Type"] = "application/json",
                    }
                )
                assert(code == 200, "unexpected status: " .. tostring(code) .. ", body: " .. body)
                return json.decode(body)
            end

            local ok, err = xpcall(function()
                local res = send_ai()
                assert(res.host == "multi-ip.example.com:16724",
                       "unexpected host: " .. tostring(res.host))
                assert(res.server_addr == "127.0.0.1" or res.server_addr == "127.0.0.2",
                       "unexpected server addr: " .. tostring(res.server_addr))

                ngx.sleep(1.2)
                res = send_ai()
                assert(res.host == "multi-ip.example.com:16724",
                       "unexpected host: " .. tostring(res.host))
                assert(res.server_addr == "127.0.0.1" or res.server_addr == "127.0.0.2",
                       "unexpected server addr: " .. tostring(res.server_addr))
            end, debug.traceback)
            resolver.parse_domain_all = original_parse_domain_all
            assert(ok, err)
            ngx.say("passed")
        }
    }
--- response_body
passed
--- no_error_log
releasing existing checker:
trying to increment a target that is not in the list



=== TEST 2: parse_domain_all asks DNS client for all answers
--- config
    location /t {
        content_by_lua_block {
            local resolver = require("apisix.core.resolver")
            local utils = require("apisix.core.utils")
            local dns_client = require("apisix.core.dns.client")
            local original_dns_parse = utils.dns_parse
            local got_selector

            utils.dns_parse = function(host, selector)
                got_selector = selector
                assert(host == "multi-ip.example.com", "unexpected host: " .. tostring(host))
                return {
                    {address = "127.0.0.2"},
                    {address = "127.0.0.1"},
                }
            end

            local ok, ips, err = xpcall(function()
                local ips, err = resolver.parse_domain_all("multi-ip.example.com")
                return ips, err
            end, debug.traceback)
            utils.dns_parse = original_dns_parse

            assert(ok, ips)
            assert(not err, err)
            assert(got_selector == dns_client.RETURN_ALL,
                   "unexpected selector: " .. tostring(got_selector))
            assert(ips[1] == "127.0.0.1", "unexpected first ip: " .. tostring(ips[1]))
            assert(ips[2] == "127.0.0.2", "unexpected second ip: " .. tostring(ips[2]))
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 3: parse_domain_all uses hosts before DNS client
--- config
    location /t {
        content_by_lua_block {
            local resolver = require("apisix.core.resolver")
            local utils = require("apisix.core.utils")
            local original_dns_parse = utils.dns_parse

            utils.dns_parse = function()
                error("dns_parse should not be called")
            end

            local ok, ips, err = xpcall(function()
                local ips, err = resolver.parse_domain_all("localhost")
                return ips, err
            end, debug.traceback)
            utils.dns_parse = original_dns_parse

            assert(ok, ips)
            assert(not err, err)
            assert(#ips > 0, "expected hosts result")
            ngx.say("passed")
        }
    }
--- response_body
passed
