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
log_level('info');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: fetch_latest_conf resolves a bare "/<type>/<id>" path (no etcd prefix)
# remove_etcd_prefix's own doc comment claims to handle both
# "/<etcd-prefix>/<type>/<id>" and bare "/<type>/<id>" formats, but it used to
# unconditionally strip #etcd_prefix characters regardless of whether the
# prefix was actually present, mangling a bare path (e.g. turning
# "/upstreams/foo" into "ams/foo" when the configured prefix is "/apisix").
# Every existing caller happens to always pass the prefixed form
# (up_conf.resource_key), so this went unnoticed until a bare-path caller
# (healthcheck_manager.ensure_checker) was added.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local resource = require("apisix.resource")

            assert(t('/apisix/admin/upstreams/bare-path-test', ngx.HTTP_PUT, [[{
                "nodes": {"127.0.0.1:1980": 1},
                "type": "roundrobin"
            }]]) < 300)
            ngx.sleep(0.2)

            local res_conf = resource.fetch_latest_conf("/upstreams/bare-path-test")
            ngx.say("bare path resolved: ", tostring(res_conf ~= nil))
            if res_conf then
                ngx.say("resolved id: ", tostring(res_conf.value.id))
            end
        }
    }
--- request
GET /t
--- response_body
bare path resolved: true
resolved id: bare-path-test
--- no_error_log
[error]
--- timeout: 5



=== TEST 2: fetch_latest_conf still resolves the etcd-prefixed "/apisix/<type>/<id>" form
# Regression guard for the format every real production caller
# (up_conf.resource_key) actually uses.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local resource = require("apisix.resource")

            assert(t('/apisix/admin/upstreams/prefixed-path-test', ngx.HTTP_PUT, [[{
                "nodes": {"127.0.0.1:1980": 1},
                "type": "roundrobin"
            }]]) < 300)
            ngx.sleep(0.2)

            local res_conf = resource.fetch_latest_conf("/apisix/upstreams/prefixed-path-test")
            ngx.say("prefixed path resolved: ", tostring(res_conf ~= nil))
            if res_conf then
                ngx.say("resolved id: ", tostring(res_conf.value.id))
            end
        }
    }
--- request
GET /t
--- response_body
prefixed path resolved: true
resolved id: prefixed-path-test
--- no_error_log
[error]
--- timeout: 5
