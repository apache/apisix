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

# A reload whose broadcast never goes out must still converge every worker.
#
# The version is bumped before the serving worker commits anything, so the
# reconciliation timer has something to replay: the workers that never saw the
# event pick the change up on their next tick. Two workers here, and the probe
# plugin counts its init() in a shared dict so the assertion can see all of
# them, not only the one running the test.

use t::APISIX 'no_plan';

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
workers(2);

run_tests();

__DATA__

=== TEST 1: a failed broadcast still converges through reconciliation
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
  - reload-probe-shared
--- config
location /t {
    content_by_lua_block {
        local dict = ngx.shared["internal-status"]
        local events = require("apisix.events")

        -- let the boot-time loads settle before counting
        ngx.sleep(1)
        local before = dict:get("reload_probe_shared_init") or 0
        local ver_before = dict:get("plugins_conf_version") or 0

        -- the broadcast fails, so no worker is told about the reload
        local orig_post = events.post
        events.post = function()
            return nil, "forced broadcast failure"
        end

        local t = require("lib.test_admin").test
        local code = t('/apisix/admin/plugins/reload', ngx.HTTP_PUT)
        ngx.say("reload: ", code)

        events.post = orig_post

        -- the version must have moved even though the broadcast did not, which
        -- is what lets the other worker converge
        local ver_after = dict:get("plugins_conf_version") or 0
        ngx.say("version bumped: ", tostring(ver_after > ver_before))

        -- the reconciliation timer runs once a second
        ngx.sleep(3)

        -- the serving worker loaded synchronously and the other one through
        -- reconciliation, so the probe was initialized at least twice
        local after = dict:get("reload_probe_shared_init") or 0
        ngx.say("workers converged: ", tostring(after - before >= 2))
    }
}
--- request
GET /t
--- response_body
reload: 503
version bumped: true
workers converged: true
--- timeout: 15
--- error_log
failed to broadcast the plugins reload
