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

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;
    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: a control-API reload request bumps the shared plugins conf version
--- config
    location /t {
        content_by_lua_block {
            local dict = ngx.shared["internal-status"]
            local before = dict:get("plugins_conf_version") or 0
            local res = ngx.location.capture("/v1/plugins/reload",
                                             { method = ngx.HTTP_PUT })
            local after = dict:get("plugins_conf_version") or 0
            ngx.say(res.status, " bumped=", tostring(after > before))
        }
    }
--- response_body
200 bumped=true
--- no_error_log
failed to increase plugins conf version



=== TEST 2: a worker that missed the control reload broadcast converges via reconciliation
--- config
    location /t {
        content_by_lua_block {
            -- A reload whose broadcast never arrives (the resty.events broker has
            -- no delivery guarantee while a worker is reconnecting) leaves the
            -- shared version ahead of what this worker applied. Reproduce exactly
            -- that state without going through the events layer, and let the admin
            -- reconciliation timer (once a second) catch it up.
            local dict = ngx.shared["internal-status"]
            local newver, incr_err = dict:incr("plugins_conf_version", 1, 0)
            if not newver then
                ngx.say("failed to bump version: ", incr_err)
                return
            end
            ngx.sleep(2.5)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
start to hot reload plugins
