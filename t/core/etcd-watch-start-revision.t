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
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: a write made after the configuration snapshot is still delivered
The configuration is preloaded once in init_by_lua and handed to each resource
type as it registers, which removes it from the preload table. This test drives
that table empty by giving etcd a prefix holding a single directory, so /routes
is the only type with anything to consume, and then writes a route between the
snapshot and the first watch. The route can only reach the worker through the
watch, so it arrives if and only if the watch starts from the revision the
snapshot was read at.
--- yaml_config
apisix:
    node_listen: 1984
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    admin:
        admin_key: null
    etcd:
        prefix: "/apisix-watch-start-revision"
        host:
            - "http://127.0.0.1:2379"
--- extra_init_by_lua_start
    -- io.popen reports nothing about how curl fared, so the etcd response is
    -- checked instead: a silently failing write here would look exactly like
    -- the lost event this test is about
    local function etcd_call(path, body)
        local f = assert(io.popen("curl -sS --fail-with-body -X POST "
                                  .. "http://127.0.0.1:2379/v3/kv/" .. path
                                  .. " -d '" .. body .. "'"))
        local out = f:read("*a")
        f:close()
        if not out or not out:find('"header"', 1, true) then
            error("etcd " .. path .. " failed: " .. tostring(out))
        end
    end

    local function etcd_put(key, value)
        etcd_call("put", '{"key":"' .. ngx.encode_base64(key)
                         .. '","value":"' .. ngx.encode_base64(value) .. '"}')
    end
    _G.etcd_put_for_test = etcd_put

    local function etcd_clear()
        etcd_call("deleterange",
            '{"key":"' .. ngx.encode_base64("/apisix-watch-start-revision/")
            .. '","range_end":"' .. ngx.encode_base64("/apisix-watch-start-revision0") .. '"}')
    end
    _G.etcd_clear_for_test = etcd_clear

    -- start from an empty prefix, so the route written below can only ever
    -- reach the worker through the watch and never through the snapshot. The
    -- run clears up after itself too; this is here for a run that did not.
    etcd_clear()

    -- only /routes exists under this prefix, so the preload table holds exactly
    -- one entry and registering /routes empties it
    etcd_put("/apisix-watch-start-revision/routes/", "init_dir")
--- extra_init_by_lua
    -- after the snapshot was taken, before any worker starts watching
    _G.etcd_put_for_test("/apisix-watch-start-revision/routes/1",
        '{"uri":"/hello","upstream":{"type":"roundrobin","nodes":{"127.0.0.1:1980":1}}}')
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            ngx.sleep(1)

            local routes = core.config.fetch_created_obj("/routes")
            local route = routes and routes:get("1")

            -- the local etcd is shared, so do not leave this prefix populated
            _G.etcd_clear_for_test()

            if not route then
                ngx.say("route written during startup was lost")
                return
            end

            ngx.say("uri: ", route.value.uri)
        }
    }
--- request
GET /t
--- response_body
uri: /hello
