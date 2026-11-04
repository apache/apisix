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
log_level('debug');
worker_connections(512);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[alert]");
    }

    my $http_config = <<_EOC_;
    lua_shared_dict introspection 10m;
    lua_shared_dict oidc_introspection_test 1m;

    server {
        listen 1970;

        location = /introspect {
            content_by_lua_block {
                local dict = ngx.shared.oidc_introspection_test
                dict:incr("calls", 1, 0)

                local mode = ngx.var.arg_mode
                if mode == "slow" then
                    ngx.sleep(7)
                elseif mode == "timeout" then
                    ngx.sleep(2)
                elseif mode == "active" or mode == "active-no-exp" or
                       mode == "failure" then
                    ngx.sleep(1)
                end

                ngx.header.content_type = "application/json"
                if mode == "failure" then
                    ngx.status = 503
                    ngx.say('{"error":"temporarily unavailable"}')
                elseif mode == "inactive" then
                    ngx.say('{"active":false}')
                elseif mode == "missing-active" then
                    ngx.say('{"sub":"customer"}')
                elseif mode == "nonboolean-active" then
                    ngx.say('{"active":"true","sub":"customer"}')
                elseif mode == "active-no-exp" then
                    ngx.say('{"active":true,"sub":"customer"}')
                else
                    ngx.say('{"active":true,"sub":"customer","exp":' ..
                            (ngx.time() + 60) .. '}')
                end
            }
        }

        location = /reset {
            content_by_lua_block {
                ngx.shared.oidc_introspection_test:flush_all()
                ngx.say("ok")
            }
        }

        location = /calls {
            content_by_lua_block {
                ngx.say(ngx.shared.oidc_introspection_test:get("calls") or 0)
            }
        }

        location / {
            content_by_lua_block {
                ngx.say("upstream reached")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: concurrent cache misses for one active token are coalesced
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.oidc_introspection")
            test.configure("active")
            local statuses, invalid = test.concurrent("active-token", 35)
            ngx.say("status 200: ", statuses[200] or 0)
            ngx.say("invalid_token challenges: ", invalid)
            ngx.say("upstream calls: ", test.upstream_calls())
        }
    }
--- timeout: 10
--- response_body
status 200: 35
invalid_token challenges: 0
upstream calls: 1



=== TEST 2: concurrent endpoint overload is shared as service unavailable
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.oidc_introspection")
            test.configure("failure")
            local statuses, invalid = test.concurrent("failure-token", 35)
            ngx.say("status 503: ", statuses[503] or 0)
            ngx.say("invalid_token challenges: ", invalid)
            ngx.say("upstream calls: ", test.upstream_calls())
        }
    }
--- timeout: 10
--- response_body
status 503: 35
invalid_token challenges: 0
upstream calls: 1
--- error_log
OIDC introspection failed: response indicates failure, status=503



=== TEST 3: an inactive token remains unauthorized and invalid
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.oidc_introspection")
            test.configure("inactive")
            local status, invalid = test.request("inactive-token")
            ngx.say("status: ", status)
            ngx.say("invalid_token challenge: ", invalid)
            ngx.say("upstream calls: ", test.upstream_calls())
        }
    }
--- response_body
status: 401
invalid_token challenge: true
upstream calls: 1
--- error_log
OIDC introspection failed: invalid token



=== TEST 4: a transport error is service unavailable
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.oidc_introspection")
            test.configure("unreachable")
            local status, invalid = test.request("transport-error-token")
            ngx.say("status: ", status)
            ngx.say("invalid_token challenge: ", invalid)
            ngx.say("upstream calls: ", test.upstream_calls())
        }
    }
--- response_body
status: 503
invalid_token challenge: false
upstream calls: 0
--- error_log
OIDC introspection failed: accessing introspection endpoint



=== TEST 5: an introspection read timeout is service unavailable
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.oidc_introspection")
            test.configure("timeout", 1)
            local status, invalid = test.request("read-timeout-token")
            ngx.say("status: ", status)
            ngx.say("invalid_token challenge: ", invalid)
            ngx.say("upstream calls: ", test.upstream_calls())
        }
    }
--- timeout: 5
--- response_body
status: 503
invalid_token challenge: false
upstream calls: 1
--- error_log
OIDC introspection failed: accessing introspection endpoint



=== TEST 6: a coordination timeout falls back to direct introspection
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.oidc_introspection")
            test.configure("slow", 10)
            local statuses, invalid = test.concurrent("lock-timeout-token", 2, 0.1)
            ngx.say("status 200: ", statuses[200] or 0)
            ngx.say("status 503: ", statuses[503] or 0)
            ngx.say("invalid_token challenges: ", invalid)
            ngx.say("upstream calls: ", test.upstream_calls())
        }
    }
--- timeout: 15
--- response_body
status 200: 2
status 503: 0
invalid_token challenges: 0
upstream calls: 2
--- error_log
failed to acquire introspection lock: timeout; falling back to direct introspection



=== TEST 7: a non-cacheable active response is shared only in flight
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.oidc_introspection")
            test.configure("active-no-exp")
            local statuses, invalid = test.concurrent("no-exp-token", 20)
            local later_status = test.request("no-exp-token")
            ngx.say("batch status 200: ", statuses[200] or 0)
            ngx.say("later status: ", later_status)
            ngx.say("invalid_token challenges: ", invalid)
            ngx.say("upstream calls: ", test.upstream_calls())
        }
    }
--- timeout: 10
--- response_body
batch status 200: 20
later status: 200
invalid_token challenges: 0
upstream calls: 2



=== TEST 8: a response without active is service unavailable
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.oidc_introspection")
            test.configure("missing-active")
            local status, invalid = test.request("missing-active-token")
            ngx.say("status: ", status)
            ngx.say("invalid_token challenge: ", invalid)
            ngx.say("upstream calls: ", test.upstream_calls())
        }
    }
--- response_body
status: 503
invalid_token challenge: false
upstream calls: 1
--- error_log
OIDC introspection failed: introspection response active claim is not a boolean



=== TEST 9: a non-boolean active response is service unavailable
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.oidc_introspection")
            test.configure("nonboolean-active")
            local status, invalid = test.request("nonboolean-active-token")
            ngx.say("status: ", status)
            ngx.say("invalid_token challenge: ", invalid)
            ngx.say("upstream calls: ", test.upstream_calls())
        }
    }
--- response_body
status: 503
invalid_token challenge: false
upstream calls: 1
--- error_log
OIDC introspection failed: introspection response active claim is not a boolean
