--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local healthcheck = require("resty.healthcheck")
local new = healthcheck.new
local state = {
    failures = 0, restore_failures = 0, created = 0, add_calls = 0, remove_calls = 0,
    healthy_add_calls = 0, healthy_remove_calls = 0, stale_remove_calls = 0,
}

-- Fail only the armed list replacement and, when requested, its restoration.
-- All other dictionary operations, probes and requests use the real runtime.
local methods = getmetatable(ngx.shared["upstream-healthcheck"]).__index
local shm_set = methods.set
for _, operation in ipairs({ "set", "safe_set", "safe_add" }) do
    local original = methods[operation]
    methods[operation] = function(dict, key, value, ...)
        if state.fail_write == key then
            state.fail_write = nil
            state.failures = state.failures + 1
            if state.delete_on_failure then
                shm_set(dict, key, nil)
            end
            if state.fail_restore then
                state.restore_key = key
            end
            return nil, "no memory"
        end
        if state.restore_key == key then
            state.restore_key = nil
            state.restore_failures = state.restore_failures + 1
            return nil, "no memory"
        end
        return original(dict, key, value, ...)
    end
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
            state.restore_key = nil
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

return state
