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

run_tests();

__DATA__

=== TEST 1: retry an explicit removal after the shared list is evicted and the worker forgets it
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
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

        -- Evict the list independently, before the library reads it to prepare
        -- its write. A write-time backup cannot contain this registration.
        local remove_target = checker.remove_target
        local evicted = false
        checker.remove_target = function(self, ip, port, ...)
            if port == 1960 and not evicted then
                local dict = ngx.shared["upstream-healthcheck"]
                assert(dict:get(self.TARGET_LIST), "the shared target list was already absent")
                dict:delete(self.TARGET_LIST)
                assert(#state.targets() == 0, "a protected registration list is still readable")
                evicted = true
            end
            return remove_target(self, ip, port, ...)
        end
        state.armed = "remove"
        state.armed_port = 1960
        state.put(60, true, 1981)
        assert(state.wait_for(function() return state.swept ~= nil end, 30)
               and state.swept, "worker did not sweep the removed node")
        ngx.say("independent list eviction: ", evicted)
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
independent list eviction: true
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
