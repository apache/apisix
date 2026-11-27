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
        healthy_add_calls = 0, healthy_remove_calls = 0, stale_remove_calls = 0,
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
            if state.delete_on_failure then
                shm_set(dict, key, nil)
            end
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
                end
                if port == 1960 and operation == "remove" then
                    state.stale_remove_calls = state.stale_remove_calls + 1
                end
                if state.armed == operation and port == (state.armed_port or 1970) then
                    local armed_port = state.armed_port or 1970
                    state.armed = nil
                    local list = healthcheck.get_target_list(self.name,
                                                           "upstream-healthcheck") or {}
                    for _, target in ipairs(list) do
                        if target.port == armed_port then
                            state.failed_purge_time = target.purge_time
                        end
                    end
                    state.fail_write = self.TARGET_LIST
                end
                local ok, method_err = method(self, ip, port, ...)
                assert(not state.fail_write, "the selected target-list write did not run")
                return ok, method_err
            end
        end
        return checker
    end

    function state.wait_for(condition, timeout)
        local deadline = ngx.now() + (timeout or 10)
        while not condition() do
            ngx.update_time()
            if ngx.now() >= deadline then
                return false
            end
            ngx.sleep(0.05)
        end
        return true
    end

    function state.put(interval, keep_dead, extra_port)
        local nodes = { { host = "127.0.0.1", port = 1980, weight = 1 } }
        if keep_dead then
            nodes[#nodes + 1] = { host = "127.0.0.1", port = 1970, weight = 1 }
        end
        if extra_port then
            nodes[#nodes + 1] = { host = "127.0.0.1", port = extra_port, weight = 1 }
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

    function state.prepare_nodes_update(extra_port)
        state.put(1, true, extra_port)
        state.seed()
        assert(state.wait_for(function()
            return state.unhealthy() and (not extra_port or
                   state.current:get_target_status("127.0.0.1", extra_port) == false)
        end), "initial probes did not finish")

        -- Slow down probes of healthy targets before the nodes-only change.
        -- A probe must not repair a wrongly reset target during the retry.
        state.put(60, true, extra_port)
        assert(state.wait_for(function()
            return state.created == 2 and state.unhealthy()
        end), "the slow-probe checker was not ready")
        state.delete_on_failure = true
        return state.current
    end

    function state.shared_status(port)
        local key = state.current.TARGET_STATE .. ":127.0.0.1:" .. port .. ":127.0.0.1"
        return ngx.shared["upstream-healthcheck"]:get(key)
    end

    function state.removed()
        local status, err
        if state.current then
            status, err = state.current:get_target_status("127.0.0.1", 1970)
        end
        return status == nil and err == "target not found"
    end

    function state.traffic(label, second_healthy)
        local test = require("lib.test_admin").test
        local healthy = 0
        for _ = 1, 40 do
            local code, _, body = test(state.uri, ngx.HTTP_GET)
            if code == 200 and (body == "1980" or (second_healthy and body == second_healthy)) then
                healthy = healthy + 1
            end
        end
        ngx.say(label or "healthy responses: ", healthy)
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



=== TEST 4: a deleted target list does not reset an unhealthy target to healthy
--- extra_init_worker_by_lua eval: $::RetryHook
--- config
location /t {
    content_by_lua_block {
        local state = _G.hc_retry_test
        state.uri = "/server_port"
        state.put(1, true)
        state.seed()
        assert(state.wait_for(state.unhealthy), "initial probes did not finish")

        state.armed = "add"
        state.delete_on_failure = true
        state.put(60, true)
        assert(state.wait_for(function()
            return state.created >= 2 and state.add_calls >= 3 and #state.targets() == 2
        end), "target reconstruction did not finish")
        assert(state.wait_for(state.unhealthy),
               "reconstructed target did not remain unhealthy")

        local state_key = state.current.TARGET_STATE .. ":127.0.0.1:1970:127.0.0.1"
        ngx.say("failed writes: ", state.failures)
        ngx.say("checkers created: ", state.created)
        ngx.say("shared dead-node state: ",
                ngx.shared["upstream-healthcheck"]:get(state_key))
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
checkers created: 2
shared dead-node state: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to add healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60



=== TEST 5: a deleted target list does not leave a local ghost
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
        state.delete_on_failure = true
        state.put(60, false)
        assert(state.wait_for(function()
            return state.created >= 2 and state.remove_calls >= 2 and #state.targets() == 1
        end), "stale-target removal did not finish")
        assert(state.wait_for(state.removed), "the worker kept a removed target")

        local ports = {}
        for _, target in ipairs(state.targets()) do
            ports[#ports + 1] = target.port
        end
        table.sort(ports)
        local removed_status, removed_err = state.current:get_target_status("127.0.0.1", 1970)
        ngx.say("failed writes: ", state.failures)
        ngx.say("checkers created: ", state.created)
        ngx.say("dead-node remove attempts: ", state.remove_calls)
        ngx.say("registered ports: ", table.concat(ports, ","))
        ngx.say("removed target status: ", tostring(removed_status), "/", tostring(removed_err))
        state.traffic()

        state.put(60, true)
        assert(state.wait_for(function()
            return state.add_calls >= 2
                   and state.current:get_target_status("127.0.0.1", 1970) == true
        end), "the re-added target did not use the default health state")
        ngx.say("re-added target healthy: ",
                tostring(state.current:get_target_status("127.0.0.1", 1970)))
        state.traffic("healthy responses after re-add: ")

        state.put(1, true)
        assert(state.wait_for(state.unhealthy), "the re-added dead node was not probed")
        state.traffic("healthy responses after final probe: ")
    }
}
--- request
GET /t
--- response_body
failed writes: 1
checkers created: 2
dead-node remove attempts: 2
registered ports: 1980
removed target status: nil/target not found
healthy responses: 40
re-added target healthy: true
healthy responses after re-add: 20
healthy responses after final probe: 40
--- error_log
failed to remove healthcheck target: 127.0.0.1:1970
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 90



=== TEST 6: reconstruction during create_checker preserves an unhealthy survivor
--- extra_init_worker_by_lua eval: $::RetryHook
--- config
location /t {
    content_by_lua_block {
        local state = _G.hc_retry_test
        state.uri = "/server_port"
        state.put(1, true, 1960)
        state.seed()
        assert(state.wait_for(state.unhealthy), "initial probes did not finish")

        state.armed = "remove"
        state.armed_port = 1960
        state.delete_on_failure = true
        state.put(60, true, false)
        assert(state.wait_for(function()
            local stale_status = state.current:get_target_status("127.0.0.1", 1960)
            return state.created >= 2 and state.add_calls >= 2
                   and state.stale_remove_calls >= 2 and #state.targets() == 2
                   and stale_status == nil
        end), "create_checker reconstruction did not finish")
        assert(state.wait_for(state.unhealthy),
               "create_checker reset the surviving target's health")

        local ports = {}
        for _, target in ipairs(state.targets()) do
            ports[#ports + 1] = target.port
        end
        table.sort(ports)
        local state_key = state.current.TARGET_STATE .. ":127.0.0.1:1970:127.0.0.1"
        ngx.say("failed writes: ", state.failures)
        ngx.say("checkers created: ", state.created)
        ngx.say("dead-node add attempts: ", state.add_calls)
        ngx.say("stale-node remove attempts: ", state.stale_remove_calls)
        ngx.say("registered ports: ", table.concat(ports, ","))
        ngx.say("shared dead-node state: ",
                ngx.shared["upstream-healthcheck"]:get(state_key))
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()
    }
}
--- request
GET /t
--- response_body
failed writes: 1
checkers created: 2
dead-node add attempts: 2
stale-node remove attempts: 2
registered ports: 1970,1980
shared dead-node state: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to remove healthcheck target: 127.0.0.1:1960
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60



=== TEST 7: retry a nodes-only addition with the same checker after losing the target list
--- extra_init_worker_by_lua eval: $::RetryHook
--- config
location /t {
    content_by_lua_block {
        local state = _G.hc_retry_test
        state.uri = "/server_port_aa"
        local checker = state.prepare_nodes_update()

        state.armed = "add"
        state.armed_port = 1981
        state.put(60, true, 1981)
        -- No route traffic or further configuration change drives the retry.
        assert(state.wait_for(function()
            return state.failures == 1 and #state.targets() == 3
                   and state.current:get_target_status("127.0.0.1", 1981) == true
        end), "the working-pool timer did not finish the addition")

        ngx.say("same checker: ", checker == state.current)
        ngx.say("shared dead-node state: ", state.shared_status(1970))
        ngx.say("dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic("healthy responses: ", "1981")
    }
}
--- request
GET /t
--- response_body
same checker: true
shared dead-node state: 2
dead node unhealthy: true
healthy responses: 40
--- error_log
failed to add healthcheck target: 127.0.0.1:1981
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60



=== TEST 8: retry a nodes-only removal and allow a later addition to start healthy
--- extra_init_worker_by_lua eval: $::RetryHook
--- config
location /t {
    content_by_lua_block {
        local state = _G.hc_retry_test
        state.uri = "/server_port_route2"
        local checker = state.prepare_nodes_update(1960)

        state.armed = "remove"
        state.armed_port = 1960
        state.put(60, true)
        assert(state.wait_for(function()
            local status, err = state.current:get_target_status("127.0.0.1", 1960)
            return state.failures == 1 and #state.targets() == 2
                   and status == nil and err == "target not found"
                   and state.shared_status(1960) == nil
        end), "the working-pool timer did not finish the removal")

        ngx.say("same checker: ", checker == state.current)
        ngx.say("shared dead-node state: ", state.shared_status(1970))
        ngx.say("surviving dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()

        state.put(60, true, 1960)
        assert(state.wait_for(function()
            return #state.targets() == 3
                   and state.current:get_target_status("127.0.0.1", 1960) == true
        end), "the re-added node did not start healthy")
        ngx.say("same checker after re-add: ", checker == state.current)
        ngx.say("shared re-added node state: ", state.shared_status(1960))
    }
}
--- request
GET /t
--- response_body
same checker: true
shared dead-node state: 2
surviving dead node unhealthy: true
healthy responses: 40
same checker after re-add: true
shared re-added node state: 1
--- error_log
failed to remove healthcheck target: 127.0.0.1:1960
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60



=== TEST 9: replacing the probe Host starts a fresh registration on the same address
--- extra_init_worker_by_lua eval: $::RetryHook
--- upstream_server_config
location = /host-health {
    content_by_lua_block {
        if ngx.var.server_port == "1981" and ngx.var.host == "old.example" then
            return ngx.exit(503)
        end
        return ngx.exit(200)
    }
}
--- config
location /t {
    content_by_lua_block {
        local state = _G.hc_retry_test
        local test = require("lib.test_admin").test
        state.uri = "/server_port_aa"
        local upstream = {
            type = "roundrobin", retries = 0,
            nodes = { ["127.0.0.1:1980"] = 1, ["127.0.0.1:1981"] = 1 },
            pass_host = "rewrite", upstream_host = "old.example",
            checks = { active = {
                type = "http", http_path = "/host-health",
                healthy = { interval = 1, successes = 1 },
                -- A failed registration stays out of rotation until after the test.
                unhealthy = { interval = 60, http_failures = 1 },
            } },
        }
        local route = { uri = state.uri, upstream = upstream }
        assert(test("/apisix/admin/routes/1", ngx.HTTP_PUT, route) < 300)
        state.seed()
        assert(state.wait_for(function()
            return state.current and state.current:get_target_status("127.0.0.1", 1981) == false
        end), "the old Host was not marked unhealthy")
        local checker = state.current

        -- Reconciliation removes both old registrations and adds the new ones
        -- in one pass, before the worker necessarily receives its remove events.
        upstream.upstream_host = "new.example"
        assert(test("/apisix/admin/routes/1", ngx.HTTP_PUT, route) < 300)
        assert(state.wait_for(function()
            local targets = state.targets()
            local healthy = state.current:get_target_status("127.0.0.1", 1981)
            return #targets == 2 and targets[1].hostheader == "new.example"
                   and targets[2].hostheader == "new.example"
                   and healthy == (state.shared_status(1981) == 1)
        end), "the new probe Host was not configured")
        ngx.say("same checker: ", state.current == checker)
        ngx.say("new registration shared state: ", state.shared_status(1981))

        local responses = { ["1980"] = 0, ["1981"] = 0 }
        for _ = 1, 40 do
            local code, _, port = test(state.uri, ngx.HTTP_GET)
            assert(code == 200 and responses[port], "unexpected upstream response")
            responses[port] = responses[port] + 1
        end
        ngx.say("responses per upstream: ", responses["1980"], "/", responses["1981"])
    }
}
--- request
GET /t
--- response_body
same checker: true
new registration shared state: 1
responses per upstream: 20/20
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 40



=== TEST 10: retry an explicit removal after both the shared list and the worker forget it
--- extra_init_worker_by_lua eval: $::RetryHook
--- config
location /t {
    content_by_lua_block {
        local state = _G.hc_retry_test
        state.uri = "/server_port_hello"
        local checker = state.prepare_nodes_update(1960)

        -- Let the real library sweep run after the replacement was registered
        -- but before the manager can start its next reconciliation.
        local add_target = checker.add_target
        checker.add_target = function(self, ip, port, ...)
            local ok, err = add_target(self, ip, port, ...)
            if ok and port == 1981 then
                self.add_target = add_target
                state.swept = state.wait_for(function()
                    local status, status_err = self:get_target_status("127.0.0.1", 1960)
                    return status == nil and status_err == "target not found"
                end, 25)
                state.after_sweep = state.shared_status(1960)
            end
            return ok, err
        end

        state.armed = "remove"
        state.armed_port = 1960
        state.put(60, true, 1981)
        assert(state.wait_for(function() return state.swept ~= nil end, 30)
               and state.swept, "worker did not sweep the removed node")
        ngx.say("shared removed-node state after sweep: ", state.after_sweep)
        local cleaned = state.wait_for(function()
            return #state.targets() == 3 and state.shared_status(1960) == nil
        end)
        ngx.say("manager finished the removal: ", cleaned)
        ngx.say("same checker: ", checker == state.current)
        ngx.say("surviving dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic("healthy responses: ", "1981")

        state.put(60, true, 1960)
        assert(state.wait_for(function()
            return state.current:get_target_status("127.0.0.1", 1960) ~= nil
        end), "removed node was not re-added")
        ngx.say("shared re-added node state: ", state.shared_status(1960))
    }
}
--- request
GET /t
--- response_body
shared removed-node state after sweep: 2
manager finished the removal: true
same checker: true
surviving dead node unhealthy: true
healthy responses: 40
shared re-added node state: 1
--- error_log
failed to remove healthcheck target: 127.0.0.1:1960
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 65
