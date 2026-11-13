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
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: admin schema check does NOT synthesize a missing passive.healthy object
# Mirrors a real admin submission that only sets checks.passive.unhealthy
# (Yuriy's Slack repro config). Confirms what actually lands in etcd.
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local checks_in = {
                type = "https",
                unhealthy = {
                    http_statuses = {500, 502, 503, 504},
                    http_failures = 2,
                    tcp_failures = 2,
                    timeouts = 2,
                },
            }
            local ok, err = core.schema.check(core.schema.health_checker_passive, checks_in)
            ngx.say("schema check ok: ", tostring(ok), " err: ", tostring(err))
            ngx.say("healthy key present after check: ", tostring(checks_in.healthy ~= nil))
        }
    }
--- request
GET /t
--- response_body
schema check ok: true err: nil
healthy key present after check: false
--- no_error_log
[error]



=== TEST 2: that same (schema-checked) checks table fed to healthcheck.new()
# resty.healthcheck's own fill_in_settings fills the missing `healthy` object
# using ITS default (successes = 5), not "disabled". Confirm by driving 5
# consecutive passive successes on a target that starts unhealthy.
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local healthcheck = require("resty.healthcheck")

            local checks_in = {
                type = "https",
                unhealthy = {
                    http_statuses = {500, 502, 503, 504},
                    http_failures = 2,
                    tcp_failures = 2,
                    timeouts = 2,
                },
            }
            assert(core.schema.check(core.schema.health_checker_passive, checks_in))
            ngx.say("passive.healthy after admin schema check: ", tostring(checks_in.healthy))

            local checker = assert(healthcheck.new({
                name = "test-passive-healthy-omitted",
                shm_name = "upstream-healthcheck",
                checks = {
                    active = {
                        healthy = { interval = 0, successes = 2 },
                        unhealthy = { interval = 0, http_failures = 2 },
                    },
                    passive = checks_in,
                },
                events_module = "resty.events",
            }))

            ngx.say("effective passive.healthy.successes: ",
                    tostring(checker.checks.passive.healthy and checker.checks.passive.healthy.successes))

            assert(checker:add_target("127.0.0.1", 19794, nil, false))
            ngx.sleep(0.05)
            ngx.say("initial status: ", tostring(checker:get_target_status("127.0.0.1", 19794)))

            for i = 1, 4 do
                assert(checker:report_http_status("127.0.0.1", 19794, nil, 200, "passive"))
                ngx.sleep(0.05)
            end
            ngx.say("status after 4 passive successes: ",
                    tostring(checker:get_target_status("127.0.0.1", 19794)))

            assert(checker:report_http_status("127.0.0.1", 19794, nil, 200, "passive"))
            ngx.sleep(0.05)
            ngx.say("status after 5th passive success: ",
                    tostring(checker:get_target_status("127.0.0.1", 19794)))

            checker:stop()
        }
    }
--- request
GET /t
--- response_body
passive.healthy after admin schema check: nil
effective passive.healthy.successes: 5
initial status: false
status after 4 passive successes: false
status after 5th passive success: true
--- grep_error_log eval
qr/healthy SUCCESS increment \(\d\/5\)/
--- grep_error_log_out
healthy SUCCESS increment (1/5)
healthy SUCCESS increment (2/5)
healthy SUCCESS increment (3/5)
healthy SUCCESS increment (4/5)
healthy SUCCESS increment (5/5)
--- no_error_log
[error]



=== TEST 3: control -- explicit successes = 0 never flips healthy via passive
--- config
    location /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")

            local checker = assert(healthcheck.new({
                name = "test-passive-healthy-explicit-zero",
                shm_name = "upstream-healthcheck",
                checks = {
                    active = {
                        healthy = { interval = 0, successes = 2 },
                        unhealthy = { interval = 0, http_failures = 2 },
                    },
                    passive = {
                        type = "https",
                        healthy = { http_statuses = {200, 201}, successes = 0 },
                        unhealthy = {
                            http_statuses = {500, 502, 503, 504},
                            http_failures = 2,
                            tcp_failures = 2,
                            timeouts = 2,
                        },
                    },
                },
                events_module = "resty.events",
            }))

            assert(checker:add_target("127.0.0.1", 19795, nil, false))
            ngx.sleep(0.05)

            for i = 1, 10 do
                assert(checker:report_http_status("127.0.0.1", 19795, nil, 200, "passive"))
                ngx.sleep(0.05)
            end
            ngx.say("status after 10 passive successes with successes=0: ",
                    tostring(checker:get_target_status("127.0.0.1", 19795)))

            checker:stop()
        }
    }
--- request
GET /t
--- response_body
status after 10 passive successes with successes=0: false
--- no_error_log
healthy SUCCESS increment
[error]



=== TEST 4: omitting checks.active.healthy entirely -- does it disable active healthy-checking?
# Docs (and schema_def.lua) say checks.active.healthy.interval defaults to 1
# (minimum 1 -- 0 is not even a legal value through the schema). Confirm what
# actually reaches the running checker when the whole `healthy` object is
# omitted from the admin submission, mirroring Yuriy's original repro
# (upstream.checks.active.healthy block removed completely).
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local healthcheck = require("resty.healthcheck")

            local active_in = {
                unhealthy = {
                    http_statuses = {500, 502, 503, 504},
                    http_failures = 2,
                    tcp_failures = 2,
                    timeouts = 1,
                },
            }
            assert(core.schema.check(core.schema.health_checker_active, active_in))
            ngx.say("active.healthy after admin schema check: ", tostring(active_in.healthy))
            ngx.say("active.unhealthy.interval after admin schema check: ",
                    tostring(active_in.unhealthy.interval))

            local checker = assert(healthcheck.new({
                name = "test-active-healthy-omitted",
                shm_name = "upstream-healthcheck",
                checks = {
                    active = active_in,
                },
                events_module = "resty.events",
            }))

            ngx.say("effective active.healthy.interval: ",
                    tostring(checker.checks.active.healthy and checker.checks.active.healthy.interval))
            ngx.say("effective active.healthy.successes: ",
                    tostring(checker.checks.active.healthy and checker.checks.active.healthy.successes))
            ngx.say("effective active.unhealthy.interval: ",
                    tostring(checker.checks.active.unhealthy and checker.checks.active.unhealthy.interval))
            ngx.say("active.healthy.active (timer actually running): ",
                    tostring(checker.checks.active.healthy and checker.checks.active.healthy.active))

            checker:stop()
        }
    }
--- request
GET /t
--- response_body
active.healthy after admin schema check: nil
active.unhealthy.interval after admin schema check: 1
effective active.healthy.interval: 0
effective active.healthy.successes: 2
effective active.unhealthy.interval: 1
active.healthy.active (timer actually running): nil
--- no_error_log
[error]



=== TEST 5: local fix -- healthcheck_manager backfills APISIX's own active defaults
# Same admin-schema-checked input as TEST 4, but routed through
# healthcheck_manager.backfill_active_health_check_defaults() before reaching
# healthcheck.new(), the way create_checker() now does. Confirms the fix
# restores the documented default (interval = 1, timer running) without
# mutating the original up_conf.checks table.
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local healthcheck = require("resty.healthcheck")
            local healthcheck_manager = require("apisix.healthcheck_manager")

            local checks_in = {
                active = {
                    unhealthy = {
                        http_statuses = {500, 502, 503, 504},
                        http_failures = 2,
                        tcp_failures = 2,
                        timeouts = 1,
                    },
                },
            }
            assert(core.schema.check(core.schema.health_checker_active, checks_in.active))
            ngx.say("active.healthy after admin schema check: ", tostring(checks_in.active.healthy))

            local patched = healthcheck_manager.backfill_active_health_check_defaults(checks_in)
            ngx.say("original up_conf.checks.active.healthy untouched: ",
                    tostring(checks_in.active.healthy))

            local checker = assert(healthcheck.new({
                name = "test-active-healthy-backfilled",
                shm_name = "upstream-healthcheck",
                checks = patched,
                events_module = "resty.events",
            }))

            ngx.say("effective active.healthy.interval: ", tostring(checker.checks.active.healthy.interval))
            ngx.say("effective active.healthy.successes: ", tostring(checker.checks.active.healthy.successes))
            ngx.say("effective active.unhealthy.interval: ", tostring(checker.checks.active.unhealthy.interval))
            ngx.say("active.healthy.active (timer actually running): ",
                    tostring(checker.checks.active.healthy.active))

            checker:stop()
        }
    }
--- request
GET /t
--- response_body
active.healthy after admin schema check: nil
original up_conf.checks.active.healthy untouched: nil
effective active.healthy.interval: 1
effective active.healthy.successes: 2
effective active.unhealthy.interval: 1
active.healthy.active (timer actually running): true
--- no_error_log
[error]
