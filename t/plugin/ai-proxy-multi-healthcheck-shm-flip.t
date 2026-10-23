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

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 127.0.0.1:16724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.say([[{"choices":[{"message":{"content":"ok","role":"assistant"}}]}]])
                }
            }

            location /status {
                content_by_lua_block {
                    ngx.say("ok")
                }
            }
        }
        server {
            server_name dead;
            listen 127.0.0.1:16725;
            default_type 'application/json';
            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.say([[{"choices":[{"message":{"content":"dead","role":"assistant"}}]}]])
                }
            }
            location /status {
                content_by_lua_block { ngx.say("ok") }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: shm-only AI health flip invalidates a cached picker
# Both instances start healthy and warm the AI picker. The dead instance is
# then marked unhealthy in shm without a resty.events notification. Its local
# checker status_ver does not change, so a picker keyed only on status_ver
# keeps selecting it. The response body identifies which instance was used.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson.safe")

            local checks = {
                active = {
                    type = "http",
                    timeout = 1,
                    http_path = "/status",
                    healthy = {
                        interval = 30,
                        successes = 1,
                    },
                    unhealthy = {
                        interval = 30,
                        http_failures = 2,
                        tcp_failures = 2,
                        timeouts = 2,
                    },
                },
            }

            local route = {
                uri = "/ai",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "dead",
                                provider = "openai",
                                weight = 1,
                                auth = {
                                    header = {
                                        Authorization = "Bearer token",
                                    },
                                },
                                options = {
                                    model = "gpt-4",
                                },
                                override = {
                                    endpoint = "http://127.0.0.1:16725",
                                },
                                checks = checks,
                            },
                            {
                                name = "ok",
                                provider = "openai",
                                weight = 1,
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
                                checks = checks,
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

            -- Register both targets as healthy before this worker creates its
            -- checker objects.
            local healthcheck = require("resty.healthcheck")
            local targets = {
                -- {instance index in json path, port, is_healthy}
                {0, 16725, true},
                {1, 16724, true},
            }
            for _, target in ipairs(targets) do
                local shadow = healthcheck.new({
                    name = "upstream#/apisix/routes/1#plugins['ai-proxy-multi'].instances["
                           .. target[1] .. "]",
                    shm_name = "upstream-healthcheck",
                    events_module = "resty.events",
                    checks = checks,
                })
                assert(shadow:add_target("127.0.0.1", target[2], nil, target[3]))
                shadow:stop()
            end

            local function send_ai()
                local code, body = t("/ai",
                    ngx.HTTP_POST,
                    json.encode({messages = {{role = "user", content = "hi"}}}),
                    nil,
                    {
                        ["Content-Type"] = "application/json",
                    }
                )
                return code, body
            end

            send_ai() -- queue checker creation
            ngx.sleep(2)
            local seen_dead, seen_ok
            for i = 1, 8 do
                local code, body = send_ai()
                assert(code == 200, body)
                seen_dead = seen_dead or body:find('"dead"', 1, true)
                seen_ok = seen_ok or body:find('"ok"', 1, true)
            end
            assert(seen_dead and seen_ok, "both healthy instances should be picked")

            local shm = ngx.shared["upstream-healthcheck"]
            local key = "lua-resty-healthcheck:upstream#/apisix/routes/1#"
                        .. "plugins['ai-proxy-multi'].instances[0]:state:"
                        .. "127.0.0.1:16725:127.0.0.1"
            assert(shm:get(key) == 1, "dead instance should begin healthy")
            assert(shm:set(key, 2)) -- unhealthy, deliberately no event

            for i = 1, 8 do
                local code, body = send_ai()
                assert(code == 200 and body:find('"ok"', 1, true),
                       "request " .. i .. " still selected the unhealthy AI instance: "
                       .. tostring(body))
            end
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed
