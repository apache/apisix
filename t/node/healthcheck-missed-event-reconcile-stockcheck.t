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
# NOT part of the real test suite -- a throwaway "red" counterpart to
# healthcheck-missed-event-reconcile.t, written to run against STOCK (unpatched)
# resty.healthcheck deps to prove apache/apisix#13888 is real at the unit level.
# Unlike the real test, this never calls _set_reconcile_interval() (a patched-only
# API that doesn't exist on stock deps and would error the whole test file).
# See /Users/andre.nogueira/projects/apisix/hack/patches/lua-resty-healthcheck-13888.patch
use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

run_tests();

__DATA__

=== TEST 1: on stock code, a missed event leaves the local cache stale forever
# Same shm-poke as healthcheck-missed-event-reconcile.t (simulates a dropped
# worker_events broadcast), but never calls the patched-only reconcile hook.
# On stock resty.healthcheck, get_target_status() reads only the local cache
# and nothing re-derives it from shm on any cadence -- so the stale value must
# still be wrong even several seconds later, not just "immediately after".
--- config
    location /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")

            local checker = healthcheck.new({
                name = "test-13888-stockcheck",
                shm_name = "upstream-healthcheck",
                checks = {
                    active = {
                        healthy = { interval = 0 },
                        unhealthy = { interval = 0 },
                    },
                },
                events_module = "resty.events",
            })
            if not checker then
                ngx.say("failed to create checker")
                return
            end

            local ok, err = checker:add_target("127.0.0.1", 12346)
            if not ok then
                ngx.say("failed to add target: ", err)
                return
            end
            ngx.sleep(0.2) -- let add_target's own event settle locally

            local before = checker:get_target_status("127.0.0.1", 12346)
            ngx.say("before shm write: ", tostring(before))

            -- Simulate a dropped worker_events broadcast: mutate the
            -- authoritative shm state directly, without incr_counter/raise_event.
            local shm = ngx.shared["upstream-healthcheck"]
            local state_key = checker.TARGET_STATE .. ":127.0.0.1:12346:127.0.0.1"
            local ok, err = shm:set(state_key, 2) -- INTERNAL_STATES[2] == "unhealthy"
            if not ok then
                ngx.say("failed to poke shm: ", err)
                return
            end

            local immediately_after = checker:get_target_status("127.0.0.1", 12346)
            ngx.say("immediately after shm write: ", tostring(immediately_after))

            -- generous wait -- several times longer than the patched default
            -- RECONCILE_INTERVAL (1s) -- to prove this is not a timing fluke
            ngx.sleep(3)

            local after_wait = checker:get_target_status("127.0.0.1", 12346)
            ngx.say("after 3s wait, still stale on stock: ", tostring(after_wait))

            checker:stop()
        }
    }
--- request
GET /t
--- response_body
before shm write: true
immediately after shm write: true
after 3s wait, still stale on stock: true
--- no_error_log
[error]
--- timeout: 8
