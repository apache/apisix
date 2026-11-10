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

=== TEST 1: panic in construct_upstream during checker creation must not crash the timer
# construct_upstream is overridden to raise a Lua error on every call. The
# healthcheck manager creation timer wraps it in pcall, logs the failure and
# skips the bad resource instead of aborting checker creation for the whole
# worker. Proxying is unaffected.
--- extra_init_worker_by_lua
    local plugin = require "apisix.plugins.ai-proxy-multi"
    plugin.construct_upstream = function(instance)
        local panic_check
        panic_check.cnt = 1
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson.safe")

            local checks = {
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
            }

            local route = {
                uri = "/ai",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "ai-instance",
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
                            {
                                name = "ai-instance-2",
                                provider = "openai",
                                weight = 1,
                                auth = {
                                    header = {
                                        Authorization = "Bearer token",
                                    },
                                },
                                options = {
                                    model = "gpt-3",
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

            -- queues the checker creation, which the timer picks up next second
            assert(send_ai() == 200, "first request should succeed")
            ngx.sleep(2)
            assert(send_ai() == 200, "second request should succeed")
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed
--- error_log
[creating checker] unable to construct upstream for plugin: ai-proxy-multi, resource path: /apisix/routes/1#plugins['ai-proxy-multi'].instances[0], json path: $.plugins['ai-proxy-multi'].instances[0]
'panic_check' (a nil value)



=== TEST 2: panic in construct_upstream during working pool check must not crash the timer
# The first call (creation timer) succeeds so a checker lands in the working
# pool; later calls (the working pool check timer) raise a Lua error. The
# check timer wraps construct_upstream in pcall, logs and keeps the entry
# instead of crashing the worker.
--- extra_init_worker_by_lua
    local plugin = require "apisix.plugins.ai-proxy-multi"
    local old_func = plugin.construct_upstream
    local cnt = 0
    plugin.construct_upstream = function(instance)
        cnt = cnt + 1
        if cnt <= 1 then
            return old_func(instance)
        end
        local panic_check
        panic_check.cnt = cnt
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson.safe")

            local checks = {
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
            }

            local route = {
                uri = "/ai",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "ai-instance",
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
                            {
                                name = "ai-instance-2",
                                provider = "openai",
                                weight = 1,
                                auth = {
                                    header = {
                                        Authorization = "Bearer token",
                                    },
                                },
                                options = {
                                    model = "gpt-3",
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

            assert(send_ai() == 200, "first request should succeed")
            ngx.sleep(2)
            assert(send_ai() == 200, "second request should succeed")
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed
--- error_log
[checking checker] unable to construct upstream for plugin: ai-proxy-multi, resource path: /apisix/routes/1#plugins['ai-proxy-multi'].instances[0], json path: $.plugins['ai-proxy-multi'].instances[0]
'panic_check' (a nil value)



=== TEST 3: construct_upstream returning nil, err during checker creation must not crash the timer
# construct_upstream returns its normal failure tuple (nil, err) instead of
# throwing. The creation timer logs the error and skips the bad resource.
--- extra_init_worker_by_lua
    local plugin = require "apisix.plugins.ai-proxy-multi"
    plugin.construct_upstream = function(instance)
        return nil, "boom"
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson.safe")

            local checks = {
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
            }

            local route = {
                uri = "/ai",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "ai-instance",
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
                            {
                                name = "ai-instance-2",
                                provider = "openai",
                                weight = 1,
                                auth = {
                                    header = {
                                        Authorization = "Bearer token",
                                    },
                                },
                                options = {
                                    model = "gpt-3",
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

            assert(send_ai() == 200, "first request should succeed")
            ngx.sleep(2)
            assert(send_ai() == 200, "second request should succeed")
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed
--- error_log
[creating checker] unable to construct upstream for plugin: ai-proxy-multi, resource path: /apisix/routes/1#plugins['ai-proxy-multi'].instances[0], json path: $.plugins['ai-proxy-multi'].instances[0], error: boom



=== TEST 4: construct_upstream returning a bare nil during working pool check must not crash the timer
# The first call (creation timer) succeeds; later calls return a bare nil with
# no error string. The check timer must not crash on the nil error and must
# keep the existing checker instead of destroying it.
--- extra_init_worker_by_lua
    local plugin = require "apisix.plugins.ai-proxy-multi"
    local old_func = plugin.construct_upstream
    local cnt = 0
    plugin.construct_upstream = function(instance)
        cnt = cnt + 1
        if cnt <= 1 then
            return old_func(instance)
        end
        return nil
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson.safe")

            local checks = {
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
            }

            local route = {
                uri = "/ai",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "ai-instance",
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
                            {
                                name = "ai-instance-2",
                                provider = "openai",
                                weight = 1,
                                auth = {
                                    header = {
                                        Authorization = "Bearer token",
                                    },
                                },
                                options = {
                                    model = "gpt-3",
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

            assert(send_ai() == 200, "first request should succeed")
            ngx.sleep(2)
            assert(send_ai() == 200, "second request should succeed")
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed
--- error_log
[checking checker] unable to construct upstream for plugin: ai-proxy-multi, resource path: /apisix/routes/1#plugins['ai-proxy-multi'].instances[0], json path: $.plugins['ai-proxy-multi'].instances[0], error: unknown error



=== TEST 5: removed instance must destroy its checker instead of leaking it
# A checker is created for instances[0], then the ai-proxy-multi plugin is
# removed from the route. The json path no longer resolves, so
# construct_upstream gets a nil config; the working pool check must treat that
# as a real removal and release the stale checker.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("cjson.safe")

            local checks = {
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
            }

            local route = {
                uri = "/ai",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "ai-instance",
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
                            {
                                name = "ai-instance-2",
                                provider = "openai",
                                weight = 1,
                                auth = {
                                    header = {
                                        Authorization = "Bearer token",
                                    },
                                },
                                options = {
                                    model = "gpt-3",
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

            -- create the checker for instances[0]
            assert(send_ai() == 200, "request should succeed")
            ngx.sleep(2)

            -- drop ai-proxy-multi so the instance's json path resolves to nil
            local plain = {
                uri = "/ai",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:16724"] = 1,
                    },
                },
            }
            code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, json.encode(plain))
            assert(code < 300, body)
            ngx.sleep(2)
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed
--- error_log
try to release checker:
for resource: /apisix/routes/1#plugins['ai-proxy-multi'].instances[0] and version
