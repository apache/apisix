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
log_level("info");
# a single worker so that the Admin API request and the plugin table
# inspected afterwards always belong to the same worker
workers(1);

run_tests;

__DATA__

=== TEST 1: a plugin whose init() throws aborts the reload and rolls it back
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
plugins:
  - response-rewrite
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local core = require("apisix.core")
        local http = require("resty.http")

        local route_conf = [[{
            "uri": "/hello",
            "plugins": {"response-rewrite": {"body": "REWRITTEN\n"}},
            "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}
        }]]

        local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, route_conf)
        ngx.say("admin PUT before reload: ", code)

        ngx.sleep(0.6)
        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
        local res = http.new():request_uri(uri)
        ngx.print("dataplane before reload: ", res.body)

        -- keep response-rewrite and add a plugin whose init() throws
        require("lib.test_admin").set_config_yaml([[
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
  - response-rewrite
  - reload-bad-init
]])
        local code2, body2 = t('/apisix/admin/plugins/reload', ngx.HTTP_PUT)
        ngx.say("reload: ", code2, " ", body2)
        ngx.sleep(2)

        -- the live plugin tables must still hold the previous plugin set:
        -- plugin.plugins is read by the request path, plugin.plugins_hash by
        -- the Admin API schema validation
        local plugin = require("apisix.plugin")
        local names = {}
        for _, p in ipairs(plugin.plugins) do
            core.table.insert(names, p.name)
        end
        ngx.say("after reload: plugins_hash has response-rewrite=",
                plugin.plugins_hash["response-rewrite"] ~= nil,
                ", plugins array=[", core.table.concat(names, ","), "]")

        -- the very same route conf is still accepted
        local code3 = t('/apisix/admin/routes/1', ngx.HTTP_PUT, route_conf)
        ngx.say("admin PUT after reload: ", code3)

        local res2 = http.new():request_uri(uri)
        ngx.print("dataplane after reload: ", res2.body)
    }
}
--- request
GET /t
--- response_body eval
qr/^admin PUT before reload: 20[01]
dataplane before reload: REWRITTEN
reload: 500 \{"error_msg":"failed to reload plugins: failed to init plugin \[reload-bad-init\].*boom.*"\}\s*
after reload: plugins_hash has response-rewrite=true, plugins array=\[response-rewrite\]
admin PUT after reload: 200
dataplane after reload: REWRITTEN
$/s
--- timeout: 15
--- error_log eval
qr/reload-bad-init: init\(\) boom/



=== TEST 2: a failed reload leaves no sticky state, the next one succeeds
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
plugins:
  - response-rewrite
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local core = require("apisix.core")

        require("lib.test_admin").set_config_yaml([[
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
  - response-rewrite
  - reload-bad-init
]])
        local code, _, body = t('/apisix/admin/plugins/reload', ngx.HTTP_PUT)
        ngx.say("failing reload: ", code)
        ngx.sleep(1)

        require("lib.test_admin").set_config_yaml([[
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
  - response-rewrite
  - key-auth
]])
        local code2, _, body2 = t('/apisix/admin/plugins/reload', ngx.HTTP_PUT)
        ngx.say("recovering reload: ", code2, " ", body2)
        ngx.sleep(1)

        local plugin = require("apisix.plugin")
        local names = {}
        for _, p in ipairs(plugin.plugins) do
            core.table.insert(names, p.name)
        end
        table.sort(names)
        ngx.say("plugins array=[", core.table.concat(names, ","), "]")
        ngx.say("key-auth in hash: ", plugin.plugins_hash["key-auth"] ~= nil)
    }
}
--- request
GET /t
--- response_body
failing reload: 500
recovering reload: 200 done
plugins array=[key-auth,response-rewrite]
key-auth in hash: true
--- timeout: 15
--- error_log eval
qr/reload-bad-init: init\(\) boom/
