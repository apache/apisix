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

=== TEST 1: node-only change reuses the checker (no destroy-and-rebuild)
--- extra_init_worker_by_lua
    local healthcheck = require("resty.healthcheck")
    local new = healthcheck.new
    healthcheck.new = function(...)
        ngx.log(ngx.WARN, "create new checker")
        local obj = new(...)
        local clear = obj.delayed_clear
        obj.delayed_clear = function(...)
            ngx.log(ngx.WARN, "clear checker")
            return clear(...)
        end
        return obj
    end

--- config
location /t {
    content_by_lua_block {
        local checks = [[{
            "active":{
                "http_path":"/hello",
                "timeout":1,
                "type":"http",
                "healthy":{ "interval":1, "successes":1 },
                "unhealthy":{ "interval":1, "http_failures":2 }
            }
        }]]
        local function cfg(nodes)
            return [[{
                "upstream": {
                    "nodes": ]] .. nodes .. [[,
                    "type": "roundrobin",
                    "checks": ]] .. checks .. [[
                },
                "uri": "/hello"
            }]]
        end

        local t = require("lib.test_admin").test
        -- initial config: one node -> creates the checker
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg('{"127.0.0.1:1980": 1}')) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- node-only change (checks unchanged): should reconcile in place,
        -- NOT create a new checker nor delayed_clear the old one
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg('{"127.0.0.1:1980": 1, "127.0.0.1:1981": 1}')) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)
        ngx.say("done")
    }
}

--- request
GET /t
--- response_body
done
--- no_error_log
clear checker
--- error_log
create new checker
--- timeout: 8



=== TEST 2: checks-config change still rebuilds the checker
--- extra_init_worker_by_lua
    local healthcheck = require("resty.healthcheck")
    local new = healthcheck.new
    healthcheck.new = function(...)
        local obj = new(...)
        local clear = obj.delayed_clear
        obj.delayed_clear = function(...)
            ngx.log(ngx.WARN, "clear checker")
            return clear(...)
        end
        return obj
    end

--- config
location /t {
    content_by_lua_block {
        local function cfg(interval)
            return [[{
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin",
                    "checks": {
                        "active":{
                            "http_path":"/hello",
                            "timeout":1,
                            "type":"http",
                            "healthy":{ "interval":]] .. interval .. [[, "successes":1 },
                            "unhealthy":{ "interval":1, "http_failures":2 }
                        }
                    }
                },
                "uri": "/hello"
            }]]
        end

        local t = require("lib.test_admin").test
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg(1)) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)
        -- change the checks config -> must rebuild (delayed_clear old checker)
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg(2)) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)
        ngx.say("done")
    }
}

--- request
GET /t
--- response_body
done
--- error_log
clear checker
--- timeout: 8



=== TEST 3: surviving targets are not purged after a checks-config rebuild
# Changing the checks config rebuilds the checker, which delayed_clear()s the old
# one. Because the new checker shares the same shm target list, the surviving
# nodes must keep being health-checked: they must NOT be purged once the
# delayed-clear window elapses. A wrong rebuild order (clear after re-add) would
# leave the live checker's targets marked and purge them here.
--- config
location /t {
    content_by_lua_block {
        local json = require("apisix.core.json")
        local t = require("lib.test_admin").test
        local function cfg(interval)
            return [[{
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1, "127.0.0.1:1981": 1},
                    "type": "roundrobin",
                    "checks": {
                        "active":{
                            "http_path":"/hello",
                            "type":"http",
                            "healthy":{ "interval":]] .. interval .. [[, "successes":1 },
                            "unhealthy":{ "interval":1, "http_failures":2 }
                        }
                    }
                },
                "uri": "/hello"
            }]]
        end
        local function count_nodes()
            local _, _, res = t('/v1/healthcheck', ngx.HTTP_GET)
            local n = 0
            for _, info in ipairs(json.decode(res)) do
                n = n + #(info.nodes or {})
            end
            return n
        end

        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg(1)) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- change the checks config (interval 1 -> 2) while keeping both nodes:
        -- this rebuilds the checker through the delayed_clear path
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg(2)) < 300)
        t('/hello', ngx.HTTP_GET)

        -- wait past DELAYED_CLEAR_TIMEOUT (10s) plus a cleanup window
        ngx.sleep(15)

        -- both surviving nodes must still be present in the live checker
        ngx.say("nodes_after: ", count_nodes())
    }
}
--- request
GET /t
--- response_body
nodes_after: 2
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 30



=== TEST 4: a node-only update keeps filtering an already-unhealthy node during the transition
# Before the fetch_checker fix, a node-only version change made fetch_checker()
# return nil until the 1s timer reconciled, so api_ctx.up_checker was nil and the
# balancer fell back to all nodes -- a node already known unhealthy could take
# traffic during the transition (apache/apisix#13282 health-filter bypass window).
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local http = require("resty.http")

        local function put(nodes)
            return t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/hello",
                "upstream": {
                    "type": "roundrobin",
                    "retries": 0,
                    "nodes": ]] .. nodes .. [[,
                    "checks": {
                        "active": {
                            "type": "tcp",
                            "healthy":   { "interval": 1, "successes": 1 },
                            "unhealthy": { "interval": 1, "tcp_failures": 1 }
                        }
                    }
                }
            }]])
        end

        -- start with only the healthy node so the checker is created without the
        -- dead node ever being in the picker yet
        assert(put('{"127.0.0.1:1980": 1}') < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(1)

        -- add the dead node (node-only change) and let active checks mark it
        -- unhealthy; a request is needed to enqueue the reconcile
        assert(put('{"127.0.0.1:1980": 1, "127.0.0.1:1970": 1}') < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(3)

        -- another node-only update opens a fresh version-transition window;
        -- immediately burst requests before timer_create_checker reconciles
        assert(put('{"127.0.0.1:1980": 1, "127.0.0.1:1970": 1}') < 300)
        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
        local errors = 0
        for _ = 1, 20 do
            local httpc = http.new()
            local res = httpc:request_uri(uri, { method = "GET", keepalive = false })
            if not res or res.status ~= 200 then
                errors = errors + 1
            end
        end
        -- the already-unhealthy dead node must stay filtered throughout
        ngx.say("errors: ", errors)
    }
}
--- request
GET /t
--- response_body
errors: 0
--- error_log
unhealthy TCP increment
--- timeout: 15



=== TEST 5: create_checker removes targets left stale in the shm by another worker
# Multi-worker: a peer worker created the checker with a node that was later
# removed, leaving it in the shared shm. A worker that never had the checker
# reaches create_checker(), which must reconcile the shm (not just add) so the
# stale node stops being probed and reported by /v1/healthcheck
# (apache/apisix#13282, multi-worker).
--- config
location /t {
    content_by_lua_block {
        local json = require("apisix.core.json")
        local t = require("lib.test_admin").test

        -- simulate a peer worker: seed route 1's checker shm target list with a
        -- node (1970) that the config below will not contain
        local healthcheck = require("resty.healthcheck")
        local seed = healthcheck.new({
            name = "upstream#/apisix/routes/1",
            shm_name = "upstream-healthcheck",
            events_module = "resty.events",
            checks = { active = { type = "tcp",
                healthy = { interval = 100, successes = 1 },
                unhealthy = { interval = 100, tcp_failures = 1 } } },
        })
        seed:add_target("127.0.0.1", 1970, nil, true)

        -- this worker has no checker in its working pool, so the first request
        -- goes through create_checker() for the current config {1980}
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
            "uri": "/hello",
            "upstream": {
                "type": "roundrobin",
                "nodes": {"127.0.0.1:1980": 1},
                "checks": { "active": { "type": "tcp",
                    "healthy": { "interval": 1, "successes": 1 },
                    "unhealthy": { "interval": 1, "tcp_failures": 1 } } }
            }
        }]]) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- create_checker's reconcile must have removed the stale 1970
        local _, _, res = t('/v1/healthcheck', ngx.HTTP_GET)
        local has_1970 = false
        for _, info in ipairs(json.decode(res)) do
            for _, node in ipairs(info.nodes or {}) do
                if node.port == 1970 then has_1970 = true end
            end
        end
        ngx.say("stale_1970: ", tostring(has_1970))
    }
}
--- request
GET /t
--- response_body
stale_1970: false
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 8



=== TEST 6: destroying a stale local checker does not purge a peer worker's live shm targets
# Multi-worker: after a checks-config change, a worker that did NOT serve traffic
# keeps its old-version checker in working_pool. timer_working_pool_check then
# destroys that stale local handle. Because the checker's shm target list is
# shared by name, a peer worker's live checker (built for the new config) owns it.
# The destroy path must NOT delayed_clear() that shm, or the peer's live targets
# are purged on every worker once the delayed-clear window elapses
# (apache/apisix#13282, multi-worker).
--- config
location /t {
    content_by_lua_block {
        local healthcheck = require("resty.healthcheck")
        local t = require("lib.test_admin").test

        local NAME = "upstream#/apisix/routes/1"
        local SHM = "upstream-healthcheck"

        -- peer worker (worker A): a live, running checker for the same resource
        -- that owns the shared shm target list and holds node 1980
        local peer = healthcheck.new({
            name = NAME, shm_name = SHM, events_module = "resty.events",
            checks = { active = { type = "tcp",
                healthy = { interval = 1, successes = 1 },
                unhealthy = { interval = 1, tcp_failures = 1 } } },
        })
        peer:add_target("127.0.0.1", 1980, nil, true)

        local function cfg(interval)
            return [[{
                "uri": "/hello",
                "upstream": {
                    "type": "roundrobin",
                    "nodes": {"127.0.0.1:1980": 1},
                    "checks": { "active": { "type": "tcp",
                        "healthy": { "interval": ]] .. interval .. [[, "successes": 1 },
                        "unhealthy": { "interval": 1, "tcp_failures": 1 } } }
                }
            }]]
        end

        -- this worker builds its own checker at checks-interval 1 (serves once)
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg(1)) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- change the checks config but send NO request to route 1: this worker
        -- never rebuilds, so working_pool keeps the old-version checker.
        -- timer_working_pool_check sees the checks change and destroys it.
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg(2)) < 300)

        -- wait past DELAYED_CLEAR_TIMEOUT (10s) + a cleanup window
        ngx.sleep(15)

        -- the peer's live target must survive in the shared shm
        local list = healthcheck.get_target_list(NAME, SHM) or {}
        local live_1980 = false
        for _, tg in ipairs(list) do
            if tg.port == 1980 then live_1980 = true end
        end
        ngx.say("live_1980: ", tostring(live_1980))
    }
}
--- request
GET /t
--- response_body
live_1980: true
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 30



=== TEST 7: recreating the same upstream id during the delayed-clear window keeps its targets
# Deleting an upstream schedules a delayed_clear() of its shm target list. If the
# same id is recreated within that window and served, create_checker() re-adds the
# targets, which must un-mark the pending purge_time so the recreated node is NOT
# purged when the window elapses (apache/apisix#13282).
--- config
location /t {
    content_by_lua_block {
        local healthcheck = require("resty.healthcheck")
        local t = require("lib.test_admin").test
        local NAME = "upstream#/apisix/routes/1"
        local SHM = "upstream-healthcheck"

        local cfg = [[{
            "uri": "/hello",
            "upstream": {
                "type": "roundrobin",
                "nodes": {"127.0.0.1:1980": 1},
                "checks": { "active": { "type": "tcp",
                    "healthy": { "interval": 1, "successes": 1 },
                    "unhealthy": { "interval": 1, "tcp_failures": 1 } } }
            }
        }]]

        -- create + build checker
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- delete: timer_working_pool_check destroys and delayed_clear()s the shm
        assert(t('/apisix/admin/routes/1', ngx.HTTP_DELETE) < 300)
        ngx.sleep(2)  -- let the destroy fire, still within the 10s clear window

        -- recreate the SAME id within the window and serve it -> create_checker re-adds
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg) < 300)
        t('/hello', ngx.HTTP_GET)

        -- wait past the original delayed_clear window
        ngx.sleep(12)

        local list = healthcheck.get_target_list(NAME, SHM) or {}
        local live_1980 = false
        for _, tg in ipairs(list) do
            if tg.port == 1980 then live_1980 = true end
        end
        ngx.say("live_1980: ", tostring(live_1980))
    }
}
--- request
GET /t
--- response_body
live_1980: true
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 40



=== TEST 8: deleting an upstream cleans its shm target list
# Deleting an upstream (with a live checker) must eventually remove its targets
# from the shared shm so a stale node is no longer probed or reported by
# /v1/healthcheck.
--- config
location /t {
    content_by_lua_block {
        local healthcheck = require("resty.healthcheck")
        local t = require("lib.test_admin").test
        local NAME = "upstream#/apisix/routes/1"
        local SHM = "upstream-healthcheck"

        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
            "uri": "/hello",
            "upstream": {
                "type": "roundrobin",
                "nodes": {"127.0.0.1:1980": 1},
                "checks": { "active": { "type": "tcp",
                    "healthy": { "interval": 1, "successes": 1 },
                    "unhealthy": { "interval": 1, "tcp_failures": 1 } } }
            }
        }]]) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        assert(t('/apisix/admin/routes/1', ngx.HTTP_DELETE) < 300)
        -- wait past the delayed_clear window plus a cleanup margin
        ngx.sleep(15)

        local list = healthcheck.get_target_list(NAME, SHM) or {}
        ngx.say("targets_after_delete: ", #list)
    }
}
--- request
GET /t
--- response_body
targets_after_delete: 0
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 30



=== TEST 9: create_checker applies a Host-header-only change instead of wiping the target
# Multi-worker: a peer worker registered node 1980 with Host header "old.com".
# The config now wants the same ip+port but Host header "new.com". Since
# resty.healthcheck keys a target by ip+port+hostname (not the Host header),
# create_checker must remove the stale key BEFORE adding -- otherwise the add is
# a no-op on the existing identity and the following remove wipes the target
# entirely (apache/apisix#13282).
--- config
location /t {
    content_by_lua_block {
        local healthcheck = require("resty.healthcheck")
        local t = require("lib.test_admin").test
        local NAME = "upstream#/apisix/routes/1"
        local SHM = "upstream-healthcheck"

        -- peer worker: same identity (127.0.0.1:1980) with Host header "old.com"
        local seed = healthcheck.new({
            name = NAME, shm_name = SHM, events_module = "resty.events",
            checks = { active = { type = "tcp",
                healthy = { interval = 100, successes = 1 },
                unhealthy = { interval = 100, tcp_failures = 1 } } },
        })
        seed:add_target("127.0.0.1", 1980, nil, true, "old.com")

        -- this worker has no checker; the first request runs create_checker() for
        -- a config that wants the same node with Host header "new.com"
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
            "uri": "/hello",
            "upstream": {
                "type": "roundrobin",
                "nodes": {"127.0.0.1:1980": 1},
                "pass_host": "rewrite",
                "upstream_host": "new.com",
                "checks": { "active": { "type": "tcp",
                    "healthy": { "interval": 1, "successes": 1 },
                    "unhealthy": { "interval": 1, "tcp_failures": 1 } } }
            }
        }]]) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- the target must survive with the new Host header, not be wiped
        local list = healthcheck.get_target_list(NAME, SHM) or {}
        local hdr = "<absent>"
        for _, tg in ipairs(list) do
            if tg.port == 1980 then hdr = tostring(tg.hostheader) end
        end
        ngx.say("hdr: ", hdr)
    }
}
--- request
GET /t
--- response_body
hdr: new.com
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 8



=== TEST 10: create_checker removes a stale target when checks.active.host (hostname) changes
# resty.healthcheck keys a target by ip+port+hostname, and checks.active.host maps
# to that hostname. A multi-worker cold start where a peer registered the node
# under one active-check host and the config now uses another must remove the
# stale identity, not leave both probed and reported (apache/apisix#13282).
--- config
location /t {
    content_by_lua_block {
        local healthcheck = require("resty.healthcheck")
        local t = require("lib.test_admin").test
        local NAME = "upstream#/apisix/routes/1"
        local SHM = "upstream-healthcheck"

        -- peer worker: node 1980 registered with active-check hostname "old-host"
        local seed = healthcheck.new({
            name = NAME, shm_name = SHM, events_module = "resty.events",
            checks = { active = { type = "http", http_path = "/status",
                healthy = { interval = 100, successes = 1 },
                unhealthy = { interval = 100, http_failures = 1 } } },
        })
        seed:add_target("127.0.0.1", 1980, "old-host", true)

        -- this worker has no checker; create_checker runs for a config whose
        -- checks.active.host is "new-host" (same ip+port, different identity)
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
            "uri": "/hello",
            "upstream": {
                "type": "roundrobin",
                "nodes": {"127.0.0.1:1980": 1},
                "checks": { "active": { "type": "http", "http_path": "/status",
                    "host": "new-host",
                    "healthy": { "interval": 1, "successes": 1 },
                    "unhealthy": { "interval": 1, "http_failures": 1 } } }
            }
        }]]) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- the stale "old-host" identity must be gone; only "new-host" remains
        local list = healthcheck.get_target_list(NAME, SHM) or {}
        local hosts = {}
        for _, tg in ipairs(list) do
            if tg.port == 1980 then hosts[#hosts + 1] = tostring(tg.hostname) end
        end
        table.sort(hosts)
        ngx.say("hostnames: ", table.concat(hosts, ","))
    }
}
--- request
GET /t
--- response_body
hostnames: new-host
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 8



=== TEST 11: a nodes-only update reconciles the checker even without traffic
# timer_working_pool_check keeps the checker alive on a nodes-only change, but the
# reconcile runs in timer_create_checker which drains waiting_pool. waiting_pool
# is normally filled by fetch_checker (request-driven), so without this worker's
# timer enqueuing the new version, a nodes-only update on an upstream that gets no
# further traffic would keep probing/reporting the old node set (apache/apisix#13282).
--- config
location /t {
    content_by_lua_block {
        local healthcheck = require("resty.healthcheck")
        local t = require("lib.test_admin").test
        local NAME = "upstream#/apisix/routes/1"
        local SHM = "upstream-healthcheck"
        local function cfg(nodes)
            return [[{
                "uri": "/hello",
                "upstream": {
                    "type": "roundrobin",
                    "nodes": ]] .. nodes .. [[,
                    "checks": { "active": { "type": "tcp",
                        "healthy": { "interval": 1, "successes": 1 },
                        "unhealthy": { "interval": 1, "tcp_failures": 1 } } }
                }
            }]]
        end
        local function shm_ports()
            local list = healthcheck.get_target_list(NAME, SHM) or {}
            local ports = {}
            for _, tg in ipairs(list) do
                ports[#ports + 1] = tg.port
            end
            table.sort(ports)
            return table.concat(ports, ",")
        end

        -- build the checker with the initial node set (one request)
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg('{"127.0.0.1:1980": 1, "127.0.0.1:1981": 1}')) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- nodes-only change (remove 1981, add 1982) but send NO request to route 1;
        -- the reconcile must still happen, driven by timer_working_pool_check
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg('{"127.0.0.1:1980": 1, "127.0.0.1:1982": 1}')) < 300)
        ngx.sleep(3)

        ngx.say("ports: ", shm_ports())
    }
}
--- request
GET /t
--- response_body
ports: 1980,1982
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 8



=== TEST 12: a checks-config change reconciles without traffic (no orphaned shm targets)
# On a checks-config change, timer_working_pool_check destroys the local handle
# but must not clear the shared shm (a peer worker may own it). If every worker
# goes cold, nothing would rebuild and the old targets would be left neither
# probed nor purged. timer_working_pool_check therefore enqueues a rebuild so
# timer_create_checker reconciles the shm on its per-worker timer, without traffic
# (apache/apisix#13282).
--- config
location /t {
    content_by_lua_block {
        local healthcheck = require("resty.healthcheck")
        local t = require("lib.test_admin").test
        local NAME = "upstream#/apisix/routes/1"
        local SHM = "upstream-healthcheck"
        local function cfg(interval, nodes)
            return [[{
                "uri": "/hello",
                "upstream": {
                    "type": "roundrobin",
                    "nodes": ]] .. nodes .. [[,
                    "checks": { "active": { "type": "tcp",
                        "healthy": { "interval": ]] .. interval .. [[, "successes": 1 },
                        "unhealthy": { "interval": 1, "tcp_failures": 1 } } }
                }
            }]]
        end
        local function shm_ports()
            local list = healthcheck.get_target_list(NAME, SHM) or {}
            local ports = {}
            for _, tg in ipairs(list) do
                ports[#ports + 1] = tg.port
            end
            table.sort(ports)
            return table.concat(ports, ",")
        end

        -- build the checker (one request)
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg(1, '{"127.0.0.1:1980": 1, "127.0.0.1:1981": 1}')) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- change the checks config (and the nodes) but send NO request to route 1;
        -- the shm must still reconcile to the new node set, driven by the timers
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg(2, '{"127.0.0.1:1980": 1, "127.0.0.1:1982": 1}')) < 300)
        ngx.sleep(3)

        ngx.say("ports: ", shm_ports())
    }
}
--- request
GET /t
--- response_body
ports: 1980,1982
--- no_error_log
failed to run timer_working_pool_check
failed to run timer_create_checker
failed to create healthcheck
failed to add healthcheck target
failed to remove healthcheck target
--- timeout: 8
