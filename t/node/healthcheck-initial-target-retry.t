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
log_level('warn');
no_root_location();
no_shuffle();

our $RetryHook = <<'EOC';
    local healthcheck = require("resty.healthcheck")
    local new = healthcheck.new
    local state = {
        failures = 0, created = 0, add_calls = 0, remove_calls = 0,
        healthy_add_calls = 0, healthy_remove_calls = 0,
    }
    _G.hc_retry_test = state

    -- Fail one real target-list write. All other dictionary operations,
    -- events, probes and upstream requests use the normal implementations.
    local methods = getmetatable(ngx.shared["upstream-healthcheck"]).__index
    local shm_set = methods.set
    methods.set = function(dict, key, value, ...)
        if key == state.fail_write then
            state.fail_write = nil
            state.failures = state.failures + 1
            return nil, "no memory"
        end
        return shm_set(dict, key, value, ...)
    end

    healthcheck.new = function(...)
        local checker, err = new(...)
        if not checker then
            return nil, err
        end
        state.created = state.created + 1
        state.current = checker
        for _, operation in ipairs({ "add", "remove" }) do
            local method = checker[operation .. "_target"]
            checker[operation .. "_target"] = function(self, ip, port, ...)
                if port == 1980 then
                    local key = "healthy_" .. operation .. "_calls"
                    state[key] = state[key] + 1
                end
                if port == 1970 then
                    state[operation .. "_calls"] = state[operation .. "_calls"] + 1
                    if state.armed == operation then
                        state.armed = nil
                        local list = healthcheck.get_target_list(self.name,
                                                               "upstream-healthcheck") or {}
                        for _, target in ipairs(list) do
                            if target.port == 1970 then
                                state.failed_purge_time = target.purge_time
                            end
                        end
                        state.fail_write = self.TARGET_LIST
                    end
                end
                local ok, method_err = method(self, ip, port, ...)
                assert(not state.fail_write, "the selected target-list write did not run")
                return ok, method_err
            end
        end
        return checker
    end

    function state.wait_for(condition)
        local deadline = ngx.now() + 10
        while not condition() do
            ngx.update_time()
            if ngx.now() >= deadline then
                return false
            end
            ngx.sleep(0.05)
        end
        return true
    end

    function state.put(interval, keep_dead)
        local nodes = { { host = "127.0.0.1", port = 1980, weight = 1 } }
        if keep_dead then
            nodes[#nodes + 1] = { host = "127.0.0.1", port = 1970, weight = 1 }
        end
        local code = require("lib.test_admin").test("/apisix/admin/routes/1", ngx.HTTP_PUT, {
            uri = state.uri,
            upstream = {
                type = "roundrobin", retries = 0, nodes = nodes,
                checks = { active = {
                    type = "tcp", timeout = 1,
                    healthy = { interval = interval, successes = 1 },
                    unhealthy = { interval = 1, tcp_failures = 1 },
                } },
            },
        })
        assert(code < 300, code)
    end

    function state.seed()
        -- The Admin API can return before this worker observes the route.
        -- Stop sending requests once either upstream response proves a match.
        local test = require("lib.test_admin").test
        local code
        assert(state.wait_for(function()
            code = test(state.uri, ngx.HTTP_GET)
            return code == 200 or code == 502
        end), "route did not match, last status: " .. tostring(code))
    end

    function state.targets()
        return healthcheck.get_target_list("upstream#/apisix/routes/1",
                                           "upstream-healthcheck") or {}
    end

    function state.unhealthy()
        return state.current
               and state.current:get_target_status("127.0.0.1", 1970) == false
    end

    function state.traffic()
        local test = require("lib.test_admin").test
        local healthy = 0
        for _ = 1, 40 do
            local code, _, body = test(state.uri, ngx.HTTP_GET)
            if code == 200 and body == "1980" then
                healthy = healthy + 1
            end
        end
        ngx.say("healthy responses: ", healthy)
    end
EOC

run_tests();

__DATA__

=== TEST 1: an initial add failure is retried without changing the upstream configuration
--- extra_init_worker_by_lua eval: $::RetryHook
--- config
location /t {
    content_by_lua_block {
        local state = _G.hc_retry_test
        state.uri = "/server_port"
        state.armed = "add"
        state.put(1, true)
        state.seed()

        -- No further route traffic or config update drives the retry. The
        -- working-pool timer must notice that registration was incomplete.
        state.wait_for(function()
            return state.add_calls >= 2 and state.unhealthy()
        end)
        ngx.say("failed writes: ", state.failures)
        ngx.say("dead-node add attempts: ", state.add_calls)
        ngx.say("checkers created: ", state.created)
        ngx.say("healthy-node add attempts: ", state.healthy_add_calls)
        ngx.say("healthy-node remove attempts: ", state.healthy_remove_calls)
        ngx.say("registered targets: ", #state.targets())
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
dead-node add attempts: 2
checkers created: 1
healthy-node add attempts: 1
healthy-node remove attempts: 0
registered targets: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to add healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 30



=== TEST 2: retrying a rebuild unmarks a target whose re-add failed
--- extra_init_worker_by_lua eval: $::RetryHook
--- config
location /t {
    content_by_lua_block {
        local state = _G.hc_retry_test
        state.uri = "/server_port_route2"
        state.put(1, true)
        state.seed()
        assert(state.wait_for(state.unhealthy), "initial probes did not finish")

        state.armed = "add"
        state.put(2, true)
        assert(state.wait_for(function() return state.failures == 1 end), "no failure injected")
        assert(state.failed_purge_time, "rebuild did not mark the old target for cleanup")
        state.wait_for(function()
            local targets = state.targets()
            for _, target in ipairs(targets) do
                if target.port == 1970 then
                    return state.add_calls >= 3 and target.purge_time == nil
                end
            end
            return false
        end)
        ngx.say("failed writes: ", state.failures)
        ngx.say("dead-node add attempts: ", state.add_calls)
        ngx.say("checkers created: ", state.created)
        ngx.say("healthy-node add attempts: ", state.healthy_add_calls)
        ngx.say("healthy-node remove attempts: ", state.healthy_remove_calls)

        -- The real cleanup timer must not remove this desired target after
        -- the old delayed-clear deadline (10 seconds) and a cleanup interval.
        local remaining = state.failed_purge_time + 3 - ngx.now()
        if remaining > 0 then
            ngx.sleep(remaining)
        end
        ngx.say("registered targets after cleanup: ", #state.targets())
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
dead-node add attempts: 3
checkers created: 2
healthy-node add attempts: 2
healthy-node remove attempts: 0
registered targets after cleanup: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to add healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 55



=== TEST 3: a failed stale-target removal during rebuild is retried
--- extra_init_worker_by_lua eval: $::RetryHook
--- config
location /t {
    content_by_lua_block {
        local state = _G.hc_retry_test
        state.uri = "/server_port_hello"
        state.put(1, true)
        state.seed()
        assert(state.wait_for(state.unhealthy), "initial probes did not finish")

        state.armed = "remove"
        state.put(2, false)
        state.wait_for(function()
            return state.remove_calls >= 2 and #state.targets() == 1
        end)
        ngx.say("failed writes: ", state.failures)
        ngx.say("dead-node remove attempts: ", state.remove_calls)
        ngx.say("checkers created: ", state.created)
        ngx.say("healthy-node add attempts: ", state.healthy_add_calls)
        ngx.say("healthy-node remove attempts: ", state.healthy_remove_calls)
        local ports = {}
        for _, target in ipairs(state.targets()) do
            ports[#ports + 1] = target.port
        end
        table.sort(ports)
        ngx.say("registered ports: ", table.concat(ports, ","))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
dead-node remove attempts: 2
checkers created: 2
healthy-node add attempts: 2
healthy-node remove attempts: 0
registered ports: 1980
healthy responses: 40
--- error_log
failed to remove healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 40
