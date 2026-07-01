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
--- ignore_error_log
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
--- ignore_error_log
--- timeout: 8
