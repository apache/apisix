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
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: server picker cached before checker creation must be refreshed after checker exists
# Reproduce the cache key collision: the first request runs before the
# healthcheck manager creates the per-instance checkers (they are created
# asynchronously ~1s after the first fetch_checker call), so it builds and
# caches a server picker WITHOUT health filtering. If the unhealthy state in
# shm was produced by another worker before this worker's checkers were
# created, the local checkers never receive a status-change event and their
# status_ver stays 0. The picker cache key must still change once the
# checkers exist, otherwise the unfiltered picker is reused indefinitely and
# keeps routing requests to the unhealthy instance.
# Here a "shadow" checker plays the other worker: it seeds the shared shm
# with an unhealthy state for the dead instance before any traffic arrives.
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
                                    -- nothing listens on this port
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

            -- seed the shared shm as another worker would have: every target
            -- already exists (so add_target in this worker raises no event)
            -- and the dead instance is already marked unhealthy before this
            -- worker's checker objects exist
            local healthcheck = require("resty.healthcheck")
            local targets = {
                -- {instance index in json path, port, is_healthy}
                {0, 16725, false},
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
                local code = t("/ai",
                    ngx.HTTP_POST,
                    json.encode({messages = {{role = "user", content = "hi"}}}),
                    nil,
                    {
                        ["Content-Type"] = "application/json",
                    }
                )
                return code
            end

            -- builds and caches the server picker while no checker exists
            -- yet, and queues the checker creation
            send_ai()

            -- let the healthcheck manager timer create the checkers; no
            -- status change happens afterwards, so no event ever bumps
            -- status_ver in this worker
            ngx.sleep(2)

            -- the unhealthy instance must not be picked anymore
            for i = 1, 4 do
                local code = send_ai()
                assert(code == 200, "request " .. i .. " got status " .. code
                       .. ": unhealthy instance still picked")
            end
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed
