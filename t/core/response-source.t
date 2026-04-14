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



=== TEST 3: get_response_source returns "apisix" when _resp_source is set
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {_resp_source = "apisix"}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
apisix



=== TEST 4: get_response_source returns "nginx" when proxied but no header time
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {_apisix_proxied = true, var = {upstream_header_time = "-"}}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
nginx



=== TEST 5: get_response_source returns "nginx" when proxied and header time nil
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {_apisix_proxied = true, var = {}}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
nginx



=== TEST 6: get_response_source returns "upstream" when proxied with numeric header time
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {_apisix_proxied = true, var = {upstream_header_time = "0.002"}}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
upstream



=== TEST 7: get_response_source handles retry: last attempt succeeded
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            -- first attempt failed, second succeeded
            local ctx = {_apisix_proxied = true, var = {upstream_header_time = "-, 0.002"}}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
upstream



=== TEST 8: get_response_source handles retry: all attempts failed
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            -- both attempts failed
            local ctx = {_apisix_proxied = true, var = {upstream_header_time = "-, -"}}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
nginx



=== TEST 9: get_response_source handles retry: last attempt failed
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            -- first succeeded but retry failed (edge case)
            local ctx = {_apisix_proxied = true, var = {upstream_header_time = "0.001, -"}}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
nginx



=== TEST 10: get_response_source: _resp_source takes priority over _apisix_proxied
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {
                _resp_source = "apisix",
                _apisix_proxied = true,
                var = {upstream_header_time = "0.002"}
            }
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
apisix



=== TEST 11: resp_exit sets _resp_source = "apisix" for error codes
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



=== TEST 12: resp_exit sets _resp_source for success codes too
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



=== TEST 13: get_response_source handles spaced separators in upstream_header_time
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            -- spaces around comma separators: "- , -"
            local ctx = {_apisix_proxied = true, var = {upstream_header_time = "- , -"}}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
nginx



=== TEST 14: get_response_source handles spaced separators with success
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            -- "- , 0.002" - first failed, second succeeded, with spaces
            local ctx = {_apisix_proxied = true, var = {upstream_header_time = "- , 0.002"}}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
upstream



=== TEST 15: get_response_source with no upstream_header_time available
--- config
    location = /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {_apisix_proxied = true}
            local source = core.response.get_response_source(ctx)
            ngx.say(source)
        }
    }
--- response_body
nginx



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
                    - "return function(_, ctx) local uht = ctx.var and ctx.var.upstream_header_time; ngx.log(ngx.WARN, 'diag: uht=', tostring(uht), ' type=', type(uht), ' ngx_uht=', tostring(ngx.var.upstream_header_time), ' us=', tostring(ngx.var.upstream_status), ' ubr=', tostring(ngx.var.upstream_bytes_received)) end"
        upstream:
            nodes:
                "127.0.0.1:11111": 1
            type: roundrobin
#END
--- request
GET /hello
--- error_code: 502
--- grep_error_log eval
qr/diag: uht=\S+ type=\S+ ngx_uht=\S+ us=\S+ ubr=\S+/
--- grep_error_log_out eval
qr/diag: uht=/
