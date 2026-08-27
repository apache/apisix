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
worker_connections(256);

# enable the resty.healthcheck TESTING seams (apache/apisix#13888 reconcile hook)
# before apisix (and therefore resty.healthcheck) is first required
add_block_preprocessor(sub {
    my ($block) = @_;
    my $extra_init_by_lua_start = $block->extra_init_by_lua_start // '';
    $extra_init_by_lua_start .= "\n_G.__TESTING_HEALTHCHECKER = true\n";
    $block->set_value("extra_init_by_lua_start", $extra_init_by_lua_start);
});

run_tests();

__DATA__

=== TEST 1: a target's local health cache self-heals from shm after a missed event
# Reproduces apache/apisix#13888: incr_counter() only raises a worker_events
# broadcast once per state transition. A worker whose local self.targets cache
# missed that one broadcast (e.g. a resty.events delivery drop) has no other
# way to learn the target went unhealthy -- get_target_status() reads only the
# local cache, never shm, so it stays wrong forever.
#
# This writes directly to the shared dict, bypassing incr_counter/raise_event
# entirely, to simulate exactly that: shm updated, no event delivered. Before
# the reconcile sweep runs, get_target_status() must still report the stale
# ("healthy") value. After one sweep interval, it must have converged to the
# shm value ("unhealthy") on its own, with no event ever posted for it.
--- config
    location /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            healthcheck._set_reconcile_interval(0.3)

            local checker = healthcheck.new({
                name = "test-13888-reconcile",
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

            local ok, err = checker:add_target("127.0.0.1", 12345)
            if not ok then
                ngx.say("failed to add target: ", err)
                return
            end
            ngx.sleep(0.2) -- let add_target's own event settle locally

            local before = checker:get_target_status("127.0.0.1", 12345)
            ngx.say("before shm write: ", tostring(before))

            -- Simulate a dropped worker_events broadcast: mutate the
            -- authoritative shm state directly, without incr_counter/raise_event.
            local shm = ngx.shared["upstream-healthcheck"]
            local state_key = checker.TARGET_STATE .. ":127.0.0.1:12345:127.0.0.1"
            local ok, err = shm:set(state_key, 2) -- INTERNAL_STATES[2] == "unhealthy"
            if not ok then
                ngx.say("failed to poke shm: ", err)
                return
            end

            -- immediately after the shm write: the local cache has NOT been
            -- told anything, so it must still read the pre-existing value
            local immediately_after = checker:get_target_status("127.0.0.1", 12345)
            ngx.say("immediately after shm write: ", tostring(immediately_after))

            ngx.sleep(0.6) -- past the 0.3s test reconcile interval

            local after_reconcile = checker:get_target_status("127.0.0.1", 12345)
            ngx.say("after reconcile: ", tostring(after_reconcile))

            checker:stop()
        }
    }
--- request
GET /t
--- response_body
before shm write: true
immediately after shm write: true
after reconcile: false
--- grep_error_log eval
qr/reconciled target status from shm/
--- grep_error_log_out
reconciled target status from shm
--- no_error_log
[error]
--- timeout: 5
