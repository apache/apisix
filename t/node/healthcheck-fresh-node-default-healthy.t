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

=== TEST 1: a brand-new upstream's checker is not created until the async timer runs
# Reproduces PS-12691 / the IMP-3253 incident mechanism: apisix.healthcheck_manager
# .fetch_checker() (apisix/healthcheck_manager.lua) enqueues a never-before-seen
# resource into waiting_pool and returns nil for the request that triggered it --
# the actual checker is only built later by the timer_every(1, ...) background
# timer (timer_create_checker). Neither #13627 nor #13629 (both in 3.18.0) touch
# this path: this test must still pass (i.e. still reproduce) on current HEAD.
#
# Wrap fetch_checker() itself (same monkey-patch style as
# healthcheck-incremental-update.t) so each call logs whether it got a live
# checker back, independent of internal resource_path/version bookkeeping.
--- extra_init_worker_by_lua
    local healthcheck_manager = require("apisix.healthcheck_manager")
    local orig_fetch_checker = healthcheck_manager.fetch_checker
    local call_count = 0
    healthcheck_manager.fetch_checker = function(...)
        call_count = call_count + 1
        local checker = orig_fetch_checker(...)
        ngx.log(ngx.WARN, "fetch_checker call #", call_count,
                " returned a live checker: ", tostring(checker ~= nil))
        return checker
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local checks = [[{
                "active":{
                    "http_path":"/hello",
                    "timeout":1,
                    "type":"http",
                    "healthy":{ "interval":1, "successes":1 },
                    "unhealthy":{ "interval":1, "http_failures":1 }
                }
            }]]
            assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin",
                    "checks": ]] .. checks .. [[
                },
                "uri": "/hello"
            }]]) < 300)

            -- first request: fetch_checker() has never seen this resource_path,
            -- so it enqueues it into waiting_pool and returns nil this call --
            -- health filtering is bypassed for this request regardless of node health
            t('/hello', ngx.HTTP_GET)

            ngx.sleep(1.5) -- let timer_create_checker build the checker

            -- second request: the checker now exists in the working pool
            t('/hello', ngx.HTTP_GET)

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- grep_error_log eval
qr/fetch_checker call #\d returned a live checker: (?:true|false)/
--- grep_error_log_out
fetch_checker call #1 returned a live checker: false
fetch_checker call #2 returned a live checker: true
--- timeout: 5



=== TEST 2: a freshly added target defaults to healthy with zero probes
# create_checker()/sync_checker_targets() in apisix/healthcheck_manager.lua call
# checker:add_target(host, port, check_host, true, host_hdr) -- is_healthy is a
# hardcoded literal `true`. The vendored resty.healthcheck add_target() defaults
# a target to "healthy" the instant it is registered, before any probe has run.
# With healthy/unhealthy probe intervals set to 0 (disabled), no probe can ever
# fire, so any "healthy" reading here is provably the zero-probe default, not the
# result of a successful check.
--- config
    location /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")

            local checker = healthcheck.new({
                name = "test-ps12691-default-healthy",
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

            -- mirror healthcheck_manager.create_checker()'s call exactly:
            -- add_target(host, port, check_host, true, host_hdr)
            local ok, err = checker:add_target("127.0.0.1", 19791, nil, true, nil)
            if not ok then
                ngx.say("failed to add target: ", err)
                return
            end
            ngx.sleep(0.2) -- let add_target's own event settle locally; no probe possible (interval=0)

            local status = checker:get_target_status("127.0.0.1", 19791)
            ngx.say("fresh, never-probed target status: ", tostring(status))

            checker:stop()
        }
    }
--- request
GET /t
--- response_body
fresh, never-probed target status: true
--- no_error_log
[error]
--- timeout: 5



=== TEST 3: all_targets_probed() is false until the first real active check fires
# Closes the gap TEST 2 exposes: a cold-start readiness gate needs a way to
# tell "healthy by default, never checked" apart from "healthy, actually
# checked" from outside the checker. resty.healthcheck.all_targets_probed()
# (hack/patches/lua-resty-healthcheck-probed-gate.patch) reads a per-target
# shm flag written the first time run_single_check actually dispatches a
# probe -- attempted, not "passed". Uses a real active interval (1s) against
# 127.0.0.1:1980, the standard t::APISIX mock backend, which answers /hello.
--- config
    location /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")

            local checker = healthcheck.new({
                name = "test-ps12691-all-targets-probed",
                shm_name = "upstream-healthcheck",
                checks = {
                    active = {
                        type = "http",
                        http_path = "/hello",
                        timeout = 1,
                        healthy = { interval = 1, successes = 1 },
                        unhealthy = { interval = 1, http_failures = 1 },
                    },
                },
                events_module = "resty.events",
            })
            if not checker then
                ngx.say("failed to create checker")
                return
            end

            local ok, err = checker:add_target("127.0.0.1", 1980, nil, true, nil)
            if not ok then
                ngx.say("failed to add target: ", err)
                return
            end
            ngx.sleep(0.2) -- let add_target's own event settle locally

            local before = healthcheck.all_targets_probed(
                "test-ps12691-all-targets-probed", "upstream-healthcheck")
            ngx.say("before any active check has run: ", tostring(before))

            ngx.sleep(1.5) -- past the 1s active.healthy.interval: one probe must have fired

            local after = healthcheck.all_targets_probed(
                "test-ps12691-all-targets-probed", "upstream-healthcheck")
            ngx.say("after the first active check: ", tostring(after))

            checker:stop()
        }
    }
--- request
GET /t
--- response_body
before any active check has run: false
after the first active check: true
--- no_error_log
[error]
--- timeout: 5



=== TEST 4: ensure_checker() builds a checker with zero prior traffic
# Closes TEST 1's gap directly: healthcheck_manager.ensure_checker()
# (apisix/healthcheck_manager.lua) seeds waiting_pool proactively, without
# needing any request to fetch_checker() first -- unlike TEST 1, no t('/hello',
# ...) request is made at all before the checker is expected to exist.
--- extra_init_worker_by_lua
    local healthcheck_manager = require("apisix.healthcheck_manager")
    local orig_fetch_checker = healthcheck_manager.fetch_checker
    local call_count = 0
    healthcheck_manager.fetch_checker = function(...)
        call_count = call_count + 1
        return orig_fetch_checker(...)
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local healthcheck_manager = require("apisix.healthcheck_manager")
            local checks = [[{
                "active":{
                    "http_path":"/hello",
                    "timeout":1,
                    "type":"http",
                    "healthy":{ "interval":1, "successes":1 },
                    "unhealthy":{ "interval":1, "http_failures":1 }
                }
            }]]
            -- a standalone /upstreams/<id> object, matching how a real
            -- "critical upstream" is configured (apisixUpstreams entries),
            -- not an inline route upstream -- an inline upstream's
            -- resource_key is the owning route's key ("/routes/<id>"), not
            -- "/upstreams/<id>", which is the identifier space
            -- ensure_checker/is_resource_probed are scoped to.
            assert(t('/apisix/admin/upstreams/ensure-checker-test', ngx.HTTP_PUT, [[{
                "nodes": {"127.0.0.1:1980": 1},
                "type": "roundrobin",
                "checks": ]] .. checks .. [[
            }]]) < 300)
            assert(t('/apisix/admin/routes/ensure-checker-test', ngx.HTTP_PUT, [[{
                "upstream_id": "ensure-checker-test",
                "uri": "/ensure-checker-test"
            }]]) < 300)

            -- no request to /ensure-checker-test at all -- fetch_checker() has
            -- never been called for this resource by real traffic
            local ok, err = healthcheck_manager.ensure_checker("/upstreams/ensure-checker-test")
            ngx.say("ensure_checker: ", tostring(ok), " ", tostring(err))

            ngx.sleep(1.5) -- let timer_create_checker build the checker on its next tick

            ngx.say("resource probed after ensure_checker with zero traffic: ",
                    tostring(healthcheck_manager.is_resource_probed("/upstreams/ensure-checker-test")))
        }
    }
--- request
GET /t
--- response_body_like
ensure_checker: true nil
resource probed after ensure_checker with zero traffic: true
--- timeout: 5



=== TEST 5: all_targets_probed() with min_attempts > 1 waits for real convergence
# Closes a gap found via live kind testing: a single active-check attempt is
# not enough to know a target's real state when unhealthy.http_failures (or
# .tcp_failures/.timeouts, or healthy.successes) is configured above 1 --
# internal_health only actually converges after that many CONSECUTIVE
# attempts. A readiness gate that opens after just 1 attempt can still route
# real traffic to a target whose true state has not yet been reached. This
# is why the shm value is now a per-target probe *count*
# (hack/patches/lua-resty-healthcheck-probed-gate.patch), not a boolean, and
# why all_targets_probed() takes an explicit min_attempts argument that
# apisix.healthcheck_manager.is_resource_probed() computes from the
# checker's own thresholds (required_probe_attempts()).
--- config
    location /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")

            local checker = healthcheck.new({
                name = "test-ps12691-min-attempts",
                shm_name = "upstream-healthcheck",
                checks = {
                    active = {
                        type = "http",
                        -- a path the mock backend does not serve: 404 is in
                        -- the default active.unhealthy.http_statuses list,
                        -- so every attempt fails deterministically without
                        -- needing a dedicated always-500 mock endpoint
                        http_path = "/definitely-not-a-real-endpoint-ps12691",
                        timeout = 1,
                        healthy = { interval = 1, successes = 1 },
                        unhealthy = { interval = 1, http_failures = 2 },
                    },
                },
                events_module = "resty.events",
            })
            if not checker then
                ngx.say("failed to create checker")
                return
            end

            local ok, err = checker:add_target("127.0.0.1", 1980, nil, true, nil)
            if not ok then
                ngx.say("failed to add target: ", err)
                return
            end
            ngx.sleep(0.2) -- let add_target's own event settle locally

            ngx.sleep(1.5) -- past one interval: exactly one attempt has fired

            local after_one = healthcheck.all_targets_probed(
                "test-ps12691-min-attempts", "upstream-healthcheck", 2)
            ngx.say("after 1 attempt, min_attempts=2: ", tostring(after_one))

            -- min_attempts=1 must already be satisfied after just 1 attempt,
            -- proving the gap is specifically about the threshold, not a
            -- broken counter.
            local after_one_threshold_one = healthcheck.all_targets_probed(
                "test-ps12691-min-attempts", "upstream-healthcheck", 1)
            ngx.say("after 1 attempt, min_attempts=1: ", tostring(after_one_threshold_one))

            ngx.sleep(1.2) -- past a second interval: a second attempt has fired

            local after_two = healthcheck.all_targets_probed(
                "test-ps12691-min-attempts", "upstream-healthcheck", 2)
            ngx.say("after 2 attempts, min_attempts=2: ", tostring(after_two))

            checker:stop()
        }
    }
--- request
GET /t
--- response_body
after 1 attempt, min_attempts=2: false
after 1 attempt, min_attempts=1: true
after 2 attempts, min_attempts=2: true
--- no_error_log
[error]
--- timeout: 8
