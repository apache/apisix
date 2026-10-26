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
log_level('info');
no_long_string();
no_shuffle();
no_root_location();

run_tests();

__DATA__

=== TEST 1: schema accepts new watch tuning fields (single mode)
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.discovery.kubernetes.schema")
            local jsonschema = require("jsonschema")
            local validator = jsonschema.generate_validator(schema)
            local ok, err = validator({
                service = { schema = "https", host = "127.0.0.1", port = "6443" },
                client  = { token = "fake-token" },
                watch_timeout_seconds        = 60,
                watch_jitter_seconds         = 0,
                watch_retry_interval_seconds = 5,
                watch_retry_max_seconds      = 60,
            })
            ngx.say(ok and "ok" or err)
        }
    }
--- request
GET /t
--- response_body
ok



=== TEST 2: schema rejects out-of-range watch_timeout_seconds
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.discovery.kubernetes.schema")
            local jsonschema = require("jsonschema")
            local validator = jsonschema.generate_validator(schema)
            local ok, err = validator({
                service = { schema = "https", host = "127.0.0.1", port = "6443" },
                client  = { token = "fake-token" },
                watch_timeout_seconds = 0,  -- minimum is 5
            })
            ngx.say(ok and "ok" or "rejected: " .. tostring(err))
        }
    }
--- request
GET /t
--- response_body_like
^rejected: .*



=== TEST 3: informer_factory.new() accepts opts and threads them through
--- config
    location /t {
        content_by_lua_block {
            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local informer = factory.new("", "v1", "Endpoints", "endpoints", "",
                { watch_timeout_seconds = 60, watch_jitter_seconds = 0 })
            ngx.say("watch_timeout_seconds=", tostring(informer.watch_timeout_seconds))
            ngx.say("watch_jitter_seconds=",  tostring(informer.watch_jitter_seconds))
        }
    }
--- request
GET /t
--- response_body
watch_timeout_seconds=60
watch_jitter_seconds=0



=== TEST 4: informer_factory.new() rejects non-table opts
--- config
    location /t {
        content_by_lua_block {
            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local _, err = factory.new("", "v1", "Endpoints", "endpoints", "", "bogus")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
opts should be a table or nil but string



=== TEST 5: informer_factory.new() with nil opts preserves backward compatibility
--- config
    location /t {
        content_by_lua_block {
            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local informer = factory.new("", "v1", "Endpoints", "endpoints", "")
            -- Defaults are applied later in watch(); the table fields are nil
            -- so the watch() function falls back to the historical 1800 / 990.
            ngx.say("default fields nil: ",
                tostring(informer.watch_timeout_seconds == nil and
                         informer.watch_jitter_seconds  == nil))
        }
    }
--- request
GET /t
--- response_body
default fields nil: true



=== TEST 6: schema accepts tuning fields in multi-mode (array form)
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.discovery.kubernetes.schema")
            local jsonschema = require("jsonschema")
            local validator = jsonschema.generate_validator(schema)
            local ok, err = validator({
                {
                    id      = "release",
                    service = { schema = "https", host = "127.0.0.1", port = "6443" },
                    client  = { token = "fake-token" },
                    watch_timeout_seconds        = 120,
                    watch_jitter_seconds         = 30,
                    watch_retry_interval_seconds = 10,
                    watch_retry_max_seconds      = 120,
                },
            })
            ngx.say(ok and "ok" or err)
        }
    }
--- request
GET /t
--- response_body
ok



=== TEST 7: create_handle threads watch tuning conf into informer factory and handle
--- config
    location /t {
        content_by_lua_block {
            local k8s_core = require("apisix.discovery.kubernetes.core")

            local captured_opts
            local mock_factory = {
                new = function(group, version, kind, plural, namespace, opts)
                    captured_opts = opts
                    return { kind = kind }, nil
                end,
            }

            local conf = {
                service = { schema = "https", host = "127.0.0.1", port = "6443" },
                client  = { token = "fake-token" },
                watch_timeout_seconds        = 120,
                watch_jitter_seconds         = 30,
                watch_retry_interval_seconds = 10,
                watch_retry_max_seconds      = 80,
            }

            local handle, err = k8s_core.create_handle(conf, {
                endpoint_dict    = {},
                informer_factory = mock_factory,
            })
            assert(handle, err)

            ngx.say("informer watch_timeout_seconds=",
                tostring(captured_opts.watch_timeout_seconds))
            ngx.say("informer watch_jitter_seconds=",
                tostring(captured_opts.watch_jitter_seconds))
            ngx.say("handle watch_retry_interval_seconds=",
                tostring(handle.watch_retry_interval_seconds))
            ngx.say("handle watch_retry_max_seconds=",
                tostring(handle.watch_retry_max_seconds))
        }
    }
--- request
GET /t
--- response_body
informer watch_timeout_seconds=120
informer watch_jitter_seconds=30
handle watch_retry_interval_seconds=10
handle watch_retry_max_seconds=80



=== TEST 8: create_handle applies default retry intervals when omitted
--- config
    location /t {
        content_by_lua_block {
            local k8s_core = require("apisix.discovery.kubernetes.core")
            local mock_factory = {
                new = function()
                    return { kind = "Endpoints" }, nil
                end,
            }

            local handle, err = k8s_core.create_handle({
                service = { schema = "https", host = "127.0.0.1", port = "6443" },
                client  = { token = "fake-token" },
            }, {
                endpoint_dict    = {},
                informer_factory = mock_factory,
            })
            assert(handle, err)

            ngx.say("retry_interval=", tostring(handle.watch_retry_interval_seconds))
            ngx.say("retry_max=", tostring(handle.watch_retry_max_seconds))
        }
    }
--- request
GET /t
--- response_body
retry_interval=40
retry_max=40



=== TEST 9: schema rejects zero retry interval and accepts one second in both modes
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.discovery.kubernetes.schema")
            local jsonschema = require("jsonschema")
            local validator = jsonschema.generate_validator(schema)

            for _, interval in ipairs({0, 1}) do
                local conf = {
                    id = "release",
                    service = { schema = "https", host = "127.0.0.1", port = "6443" },
                    client = { token = "fake-token" },
                    watch_retry_interval_seconds = interval,
                    watch_retry_max_seconds = 60,
                }
                local ok = validator(conf)
                ngx.say("single ", interval, ": ", ok and "accepted" or "rejected")
                ok = validator({conf})
                ngx.say("multi ", interval, ": ", ok and "accepted" or "rejected")
            end
        }
    }
--- request
GET /t
--- response_body
single 0: rejected
multi 0: rejected
single 1: accepted
multi 1: accepted



=== TEST 10: start_fetch backs off on failures and exceptions, caps delays, and resets on success
--- config
    location /t {
        content_by_lua_block {
            local k8s_core = require("apisix.discovery.kubernetes.core")
            local original_timer_at = ngx.timer.at
            local delays = {}
            local pending
            local outcomes = {
                "failure", "exception", "failure", "exception", "failure",
                "success", "failure", "exception",
            }
            local calls = 0
            local handle = {
                kind = "Endpoints",
                apiserver = {},
                watch_retry_interval_seconds = 5,
                watch_retry_max_seconds = 30,
                list_watch = function()
                    calls = calls + 1
                    local outcome = outcomes[calls]
                    if outcome == "exception" then
                        error("watch retry test exception", 0)
                    end
                    return outcome == "success"
                end,
            }

            -- Capture scheduled callbacks so retries can run without real delays.
            ngx.timer.at = function(delay, callback)
                delays[#delays + 1] = delay
                pending = callback
                return true
            end
            local ok, err = pcall(function()
                k8s_core.start_fetch(handle)
                for _ = 1, #outcomes do
                    local callback = assert(pending, "retry callback was not scheduled")
                    pending = nil
                    callback(false)
                end
            end)
            ngx.timer.at = original_timer_at
            assert(ok, err)

            ngx.say("delays: ", table.concat(delays, ","))
            ngx.say("calls: ", calls)
        }
    }
--- request
GET /t
--- response_body
delays: 0,5,10,20,30,30,0,5,10
calls: 8
--- error_log
list_watch failed, kind: Endpoints, reason: RuntimeException, message : watch retry test exception
--- no_error_log
[alert]



=== TEST 11: start_fetch preserves fixed default retries and clamps a cap below the initial interval
--- config
    location /t {
        content_by_lua_block {
            local k8s_core = require("apisix.discovery.kubernetes.core")
            local original_timer_at = ngx.timer.at
            local cases = {
                { name = "defaults" },
                { name = "lower cap", interval = 5, maximum = 1 },
                { name = "zero cap", interval = 5, maximum = 0 },
            }
            local ok, err = pcall(function()
                for _, case in ipairs(cases) do
                    local delays = {}
                    local pending
                    ngx.timer.at = function(delay, callback)
                        delays[#delays + 1] = delay
                        pending = callback
                        return true
                    end
                    local handle = {
                        kind = "Endpoints",
                        apiserver = {},
                        watch_retry_interval_seconds = case.interval,
                        watch_retry_max_seconds = case.maximum,
                        list_watch = function()
                            return false
                        end,
                    }
                    k8s_core.start_fetch(handle)
                    for _ = 1, 3 do
                        local callback = assert(pending, "retry callback was not scheduled")
                        pending = nil
                        callback(false)
                    end
                    ngx.say(case.name, ": ", table.concat(delays, ","))
                end
            end)
            ngx.timer.at = original_timer_at
            assert(ok, err)
        }
    }
--- request
GET /t
--- response_body
defaults: 0,40,40,40
lower cap: 0,5,5,5
zero cap: 0,5,5,5
--- no_error_log
[error]
[alert]
