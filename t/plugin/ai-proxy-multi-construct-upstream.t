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

log_level("info");
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
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);
});

run_tests();

__DATA__

=== TEST 1: construct_upstream must not mutate the instance checks in place
# The healthcheck manager calls construct_upstream once per second per
# instance from its timers, always passing the cached route config. The
# returned checks must carry the auth header/query, but the input table must
# stay untouched: otherwise auth.query is appended to checks.active.http_path
# again on every call, and the cached config no longer matches the config
# delivered by the config center.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy-multi")
            local instance = {
                name = "ins",
                provider = "openai",
                weight = 1,
                auth = {
                    header = {
                        Authorization = "Bearer token",
                    },
                    query = {
                        api_key = "secret",
                    },
                },
                options = {
                    model = "gpt-4",
                },
                override = {
                    endpoint = "http://127.0.0.1:16724",
                },
                checks = {
                    active = {
                        type = "http",
                        http_path = "/status",
                        healthy = {
                            interval = 1,
                            successes = 1,
                        },
                        unhealthy = {
                            interval = 1,
                            http_failures = 2,
                        },
                    },
                },
            }

            for i = 1, 3 do
                local upstream, err = plugin.construct_upstream(instance)
                assert(upstream, err)
                assert(upstream.checks.active.http_path == "/status?api_key=secret",
                       "call " .. i .. ": unexpected http_path: "
                       .. upstream.checks.active.http_path)
                local req_headers = upstream.checks.active.req_headers
                assert(#req_headers == 1 and req_headers[1] == "Authorization: Bearer token",
                       "call " .. i .. ": unexpected req_headers: "
                       .. require("cjson.safe").encode(req_headers))
            end

            assert(instance.checks.active.http_path == "/status",
                   "instance checks.active.http_path mutated in place: "
                   .. instance.checks.active.http_path)
            assert(instance.checks.active.req_headers == nil,
                   "instance checks.active.req_headers mutated in place")
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: auth.query is appended with & when http_path already has a query string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy-multi")
            local instance = {
                name = "ins",
                provider = "openai",
                weight = 1,
                auth = {
                    query = {
                        api_key = "secret",
                    },
                },
                options = {
                    model = "gpt-4",
                },
                override = {
                    endpoint = "http://127.0.0.1:16724",
                },
                checks = {
                    active = {
                        type = "http",
                        http_path = "/status?probe=ready",
                        healthy = {
                            interval = 1,
                            successes = 1,
                        },
                        unhealthy = {
                            interval = 1,
                            http_failures = 2,
                        },
                    },
                },
            }

            for i = 1, 2 do
                local upstream, err = plugin.construct_upstream(instance)
                assert(upstream, err)
                local http_path = upstream.checks.active.http_path
                assert(http_path == "/status?probe=ready&api_key=secret",
                       "call " .. i .. ": unexpected http_path: " .. http_path)
            end

            assert(instance.checks.active.http_path == "/status?probe=ready",
                   "instance checks.active.http_path mutated in place: "
                   .. instance.checks.active.http_path)
            ngx.say("passed")
        }
    }
--- response_body
passed
