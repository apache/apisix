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
no_shuffle();

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
    local function etcd_put(key, value)
        local body = '{"key":"' .. ngx.encode_base64(key)
                     .. '","value":"' .. ngx.encode_base64(value) .. '"}'
        local f = assert(io.popen("curl -s -X POST http://127.0.0.1:2379/v3/kv/put -d "
                                  .. "'" .. body .. "'"))
        f:read("*a")
        f:close()
    end
    _G.etcd_put_for_test = etcd_put

    -- start from an empty prefix, so the route written below can only ever
    -- reach the worker through the watch and never through the snapshot
    local body = '{"key":"' .. ngx.encode_base64("/apisix-watch-start-revision/")
                 .. '","range_end":"' .. ngx.encode_base64("/apisix-watch-start-revision0")
                 .. '"}'
    local f = assert(io.popen("curl -s -X POST http://127.0.0.1:2379/v3/kv/deleterange -d "
                              .. "'" .. body .. "'"))
    f:read("*a")
    f:close()

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



=== TEST 2: the watch still starts when no configuration was preloaded
With disable_sync_configuration_during_start there is no snapshot and so no
revision to watch from; the watch has to fall back to reading the current
revision, which is the path TEST 1 must not have removed.
--- yaml_config
apisix:
    node_listen: 1984
    disable_sync_configuration_during_start: true
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    admin:
        admin_key: null
    etcd:
        prefix: "/apisix"
        host:
            - "http://127.0.0.1:2379"
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/routes/watch-fallback',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {"127.0.0.1:1980": 1}
                    }
                }]]
            )
            if code >= 300 then
                ngx.say("failed to create the route: ", code)
                return
            end

            ngx.sleep(1)

            local routes = core.config.fetch_created_obj("/routes")
            local route = routes and routes:get("watch-fallback")
            t('/apisix/admin/routes/watch-fallback', ngx.HTTP_DELETE)

            ngx.say(route and "synced" or "not synced")
        }
    }
--- request
GET /t
--- response_body
synced
