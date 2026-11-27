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

=== TEST 1: a failed list update keeps the old node registered until its removal is retried
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port_hello"
        local checker = state.prepare_nodes_update(1960)
        local add = checker.add_target
        checker.add_target = function(self, ip, port, ...)
            local ok, err = add(self, ip, port, ...)
            if ok and port == 1981 then
                self.add_target = add
                state.old_local = self:get_target_status("127.0.0.1", 1960)
                state.old_shared = state.shared_status(1960)
                state.old_listed = false
                for _, t in ipairs(state.targets()) do
                    if t.port == 1960 then
                        state.old_listed = true
                    end
                end
            end
            return ok, err
        end
        state.armed = "remove"
        state.armed_port = 1960
        state.put(60, true, 1981)
        assert(state.wait_for(function()
            return state.failures == 1 and #state.targets() == 3
                   and state.current:get_target_status("127.0.0.1", 1960) == nil
                   and state.shared_status(1960) == nil
        end), "removal did not finish")
        ngx.say("after add: listed=", state.old_listed, " local=", state.old_local,
                " shared=", state.old_shared)
        ngx.say("same checker: ", checker == state.current)
        ngx.say("surviving dead node unhealthy: ", tostring(state.unhealthy()))
        ngx.say("removed node shared state: ", tostring(state.shared_status(1960)))
        state.traffic("healthy responses: ", "1981")
        state.put(60, true, 1960)
        assert(state.wait_for(function()
            return state.current:get_target_status("127.0.0.1", 1960) == true
        end))
        ngx.say("shared re-added node state: ", state.shared_status(1960))
    }
}
--- request
GET /t
--- response_body
after add: listed=true local=false shared=2
same checker: true
surviving dead node unhealthy: true
removed node shared state: nil
healthy responses: 40
shared re-added node state: 1
--- error_log
failed to remove healthcheck target: 127.0.0.1:1960
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60



=== TEST 2: a probe Host change takes effect after another target addition failed
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
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
        local state = require("lib.healthcheck_retry")
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

        -- Let the new route reach the worker before the manager retries the failed add.
        local add = checker.add_target
        checker.add_target = function(self, ip, port, ...)
            local ok, err = add(self, ip, port, ...)
            if not ok and port == 1960 then
                local resource = require("apisix.resource")
                assert(state.wait_for(function()
                    local conf = resource.fetch_latest_conf("/apisix/routes/1")
                    return conf and conf.value.upstream.upstream_host == "new.example"
                end), "the worker did not see the new Host")
                self.add_target = add
            end
            return ok, err
        end
        state.armed = "add"
        state.armed_port = 1960
        state.delete_on_failure = true
        upstream.nodes["127.0.0.1:1960"] = 1
        assert(test("/apisix/admin/routes/1", ngx.HTTP_PUT, route) < 300)
        assert(state.wait_for(function() return state.failures == 1 end), "no failed add")
        upstream.nodes["127.0.0.1:1960"] = nil
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
--- error_log
failed to add healthcheck target: 127.0.0.1:1960
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 40



=== TEST 3: a failed primary write during delayed cleanup still lets a rebuild remove old targets
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port_hello"
        state.put(1, true, 1960)
        state.seed()
        assert(state.wait_for(function()
            return state.unhealthy() and state.current:get_target_status("127.0.0.1", 1960) == false
        end), "the old targets were not probed")
        local old = state.current
        local clear = old.delayed_clear
        old.delayed_clear = function(self, ...)
            self.delayed_clear = clear
            state.delete_on_failure = true
            state.fail_primary = true
            state.arm_list_write(self)
            local ok, err = clear(self, ...)
            state.clear_committed = ok == true
            return ok, err
        end
        state.put(60, true)
        assert(state.wait_for(function()
            return state.created >= 2 and #state.targets() == 2 and state.unhealthy()
        end), "the checker was not rebuilt")
        ngx.say("failed writes: ", state.failures)
        ngx.say("cleanup marking committed: ", state.clear_committed)
        ngx.say("dropped shared state: ", tostring(state.shared_status(1960)))
        ngx.say("surviving unhealthy: ", tostring(state.unhealthy()))
        state.put(60, true, 1960)
        assert(state.wait_for(function()
            return #state.targets() == 3
                   and state.current:get_target_status("127.0.0.1", 1960) ~= nil
        end), "the target was not re-added")
        ngx.say("re-added shared state: ", state.shared_status(1960))
    }
}
--- request
GET /t
--- response_body
failed writes: 1
cleanup marking committed: true
dropped shared state: nil
surviving unhealthy: true
re-added shared state: 1
--- no_error_log
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 45



=== TEST 4: the staged list serves traffic when both primary writes fail
--- extra_init_worker_by_lua
    require("lib.healthcheck_retry")
--- config
location /t {
    content_by_lua_block {
        local state = require("lib.healthcheck_retry")
        state.uri = "/server_port_route2"
        local checker = state.prepare_nodes_update(1960)
        state.armed = "remove"
        state.armed_port = 1960
        state.fail_primary = true
        state.keep_primary_unavailable = true
        state.put(60, true)
        assert(state.wait_for(function() return state.update_committed ~= nil end),
               "the selected removal did not run")

        local shm = ngx.shared["upstream-healthcheck"]
        ngx.say("primary write failures: ", state.failures)
        ngx.say("primary republication failed: ", state.republication_failed)
        ngx.say("removal committed: ", state.update_committed)
        ngx.say("primary absent: ", shm:get(checker.TARGET_LIST) == nil)
        assert(state.wait_for(function()
            return #state.targets() == 2 and state.shared_status(1960) == nil
                   and checker:get_target_status("127.0.0.1", 1960) == nil
        end), "the committed list did not remove the old node")
        ngx.say("same checker: ", state.current == checker)
        ngx.say("surviving dead node unhealthy: ", tostring(state.unhealthy()))
        state.traffic()
        ngx.say("primary absent after traffic: ", shm:get(checker.TARGET_LIST) == nil)

        state.unavailable_primary = nil
        state.put(60, true, 1960)
        assert(state.wait_for(function()
            return checker:get_target_status("127.0.0.1", 1960) == true
                   and shm:get(checker.TARGET_LIST) ~= nil
        end), "re-add from the committed list did not finish")
        assert(#state.targets() == 3, "expected all three registered targets")
        ngx.say("primary republished: ", shm:get(checker.TARGET_LIST) ~= nil)
        ngx.say("shared re-added node state: ", state.shared_status(1960))
    }
}
--- request
GET /t
--- response_body
primary write failures: 1
primary republication failed: true
removal committed: true
primary absent: true
same checker: true
surviving dead node unhealthy: true
healthy responses: 40
primary absent after traffic: true
primary republished: true
shared re-added node state: 1
--- no_error_log
failed to remove healthcheck target
failed to run timer_create_checker
failed to run timer_working_pool_check
lua entry thread aborted
--- timeout: 60
