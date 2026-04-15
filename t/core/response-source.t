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
no_shuffle();
no_root_location();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: get_response_source returns "apisix" when ctx is nil
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local source = core.response.get_response_source(nil)
            ngx.say(source)
        }
    }
--- response_body
apisix



=== TEST 2: get_response_source returns "apisix" when no flags set
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
apisix



=== TEST 3: get_response_source returns explicit _resp_source
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {_resp_source = "apisix"}
            ngx.say(core.response.get_response_source(ctx))
            ctx._resp_source = "upstream"
            ngx.say(core.response.get_response_source(ctx))
            ctx._resp_source = "nginx"
            ngx.say(core.response.get_response_source(ctx))
        }
    }
--- response_body
apisix
upstream
nginx



=== TEST 4: get_last_upstream_token: nil input
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.response.get_last_upstream_token(nil) or "nil")
        }
    }
--- response_body
nil



=== TEST 5: get_last_upstream_token: single value
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.response.get_last_upstream_token("0.002"))
            ngx.say(core.response.get_last_upstream_token("-"))
            ngx.say(core.response.get_last_upstream_token("0"))
        }
    }
--- response_body
0.002
-
0



=== TEST 6: get_last_upstream_token: comma-separated retries
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            -- first attempt failed, second succeeded
            ngx.say(core.response.get_last_upstream_token("-, 0.002"))
            -- both attempts failed
            ngx.say(core.response.get_last_upstream_token("-, -"))
            -- first succeeded, retry failed
            ngx.say(core.response.get_last_upstream_token("0.002, -"))
        }
    }
--- response_body
0.002
-
-



=== TEST 7: get_last_upstream_token: spaces around separators
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.response.get_last_upstream_token("- , 0.001"))
            ngx.say(core.response.get_last_upstream_token("0.001 , -"))
            ngx.say(core.response.get_last_upstream_token("- , -"))
        }
    }
--- response_body
0.001
-
-



=== TEST 8: get_last_upstream_token: colon-separated (upstream groups)
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            -- colon separates upstream groups per NGINX docs
            ngx.say(core.response.get_last_upstream_token("- : 0.003"))
            ngx.say(core.response.get_last_upstream_token("0.003 : -"))
        }
    }
--- response_body
0.003
-



=== TEST 9: get_last_upstream_token: empty string
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.response.get_last_upstream_token("") or "nil")
        }
    }
--- response_body
nil



=== TEST 10: get_last_upstream_token: three retries
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.response.get_last_upstream_token("-, -, 0.005"))
            ngx.say(core.response.get_last_upstream_token("-, -, -"))
        }
    }
--- response_body
0.005
-



=== TEST 11: _resp_source takes priority over _apisix_proxied
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {
                _resp_source = "apisix",
                _apisix_proxied = true,
            }
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
apisix



=== TEST 12: set_response_source sets ctx._resp_source
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.response.set_response_source(ctx, "upstream")
            ngx.say(ctx._resp_source)
            ngx.say(core.response.get_response_source(ctx))
        }
    }
--- response_body
upstream
upstream



=== TEST 13: resp_exit sets _resp_source = "apisix" for error codes
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.api_ctx = {}
            local core = require("apisix.core")
            core.response.exit(403, "forbidden\n")
        }
        log_by_lua_block {
            local ctx = ngx.ctx.api_ctx
            ngx.log(ngx.INFO, "resp_source: ", ctx._resp_source or "nil")
        }
    }
--- error_code: 403
--- response_body
forbidden
--- error_log
resp_source: apisix



=== TEST 14: resp_exit sets _resp_source for success codes too
--- config
    location = /t {
        access_by_lua_block {
            ngx.ctx.api_ctx = {}
            local core = require("apisix.core")
            core.response.exit(200, "ok\n")
        }
        log_by_lua_block {
            local ctx = ngx.ctx.api_ctx
            ngx.log(ngx.INFO, "resp_source: ", ctx._resp_source or "nil")
        }
    }
--- response_body
ok
--- error_log
resp_source: apisix



=== TEST 15: resp_exit does not override explicit set_response_source
--- config
    location = /t {
        access_by_lua_block {
            local ctx = {}
            ngx.ctx.api_ctx = ctx
            local core = require("apisix.core")
            core.response.set_response_source(ctx, "upstream")
            core.response.exit(200, "ok\n")
        }
        log_by_lua_block {
            local ctx = ngx.ctx.api_ctx
            ngx.log(ngx.INFO, "resp_source: ", ctx._resp_source or "nil")
        }
    }
--- response_body
ok
--- error_log
resp_source: upstream



=== TEST 16: integration - upstream returns 200, response_source = "upstream"
--- apisix_yaml
routes:
    -
        uri: /hello
        plugins:
            serverless-pre-function:
                phase: log
                functions:
                    - "return function(_, ctx) ngx.log(ngx.WARN, 'resp_source: ', require('apisix.core').response.get_response_source(ctx)) end"
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
#END
--- request
GET /hello
--- error_code: 200
--- error_log
resp_source: upstream



=== TEST 17: integration - upstream connection refused, response_source = "nginx"
--- apisix_yaml
routes:
    -
        uri: /hello
        plugins:
            serverless-pre-function:
                phase: log
                functions:
                    - "return function(_, ctx) ngx.log(ngx.WARN, 'resp_source: ', require('apisix.core').response.get_response_source(ctx)) end"
        upstream:
            nodes:
                "127.0.0.1:11111": 1
            type: roundrobin
#END
--- request
GET /hello
--- error_code: 502
--- error_log
resp_source: nginx



=== TEST 18: integration - upstream returns 502, response_source = "upstream"
This verifies that a real 502 from upstream is classified as "upstream", not "nginx".
--- apisix_yaml
routes:
    -
        uri: /specific_status
        plugins:
            serverless-pre-function:
                phase: log
                functions:
                    - "return function(_, ctx) ngx.log(ngx.WARN, 'resp_source: ', require('apisix.core').response.get_response_source(ctx)) end"
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
#END
--- request
GET /specific_status
--- more_headers
X-Test-Upstream-Status: 502
--- error_code: 502
--- error_log
resp_source: upstream



=== TEST 19: integration - APISIX plugin rejects request, response_source = "apisix"
--- apisix_yaml
routes:
    -
        uri: /hello
        plugins:
            serverless-pre-function:
                functions:
                    - "return function() local core = require('apisix.core'); core.response.exit(403, 'rejected by plugin') end"
            serverless-post-function:
                phase: log
                functions:
                    - "return function(_, ctx) ngx.log(ngx.WARN, 'resp_source: ', require('apisix.core').response.get_response_source(ctx)) end"
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
#END
--- request
GET /hello
--- error_code: 403
--- error_log
resp_source: apisix
