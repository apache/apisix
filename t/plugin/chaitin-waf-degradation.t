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

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("extra_stream_config", <<_EOC_);
    server {
        listen 8088;
        content_by_lua_block {
            require("lib.chaitin_waf_server").reject()
        }
    }
_EOC_
    $block->set_value("stream_conf_enable", 1);
    $block->set_value("extra_yaml_config", <<_EOC_);
plugins:
    - chaitin-waf
_EOC_

    if (!$block->request) {
        $block->set_value("request", "GET /do");
    }
});

run_tests;

__DATA__

=== TEST 1: configure routes and enable degradation in metadata
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local cases = {
                {name = "inherit", mode = "block"},
                {name = "disabled", mode = "block", allow_degradation = false},
                {name = "enabled", mode = "block", allow_degradation = true},
                {name = "monitor", mode = "monitor", allow_degradation = false},
            }

            for _, case in ipairs(cases) do
                local code, body = t('/apisix/admin/routes/waf-' .. case.name,
                    ngx.HTTP_PUT, {
                        uri = "/hello",
                        vars = {{"arg_case", "==", case.name}},
                        plugins = {
                            ["chaitin-waf"] = {
                                mode = case.mode,
                                allow_degradation = case.allow_degradation,
                                append_waf_debug_header = true,
                            },
                        },
                        upstream = {
                            nodes = {["127.0.0.1:1980"] = 1},
                            type = "roundrobin",
                        },
                    })
                if code >= 300 then
                    ngx.status = code
                    return ngx.say(body)
                end
            end

            -- No detection service listens on this port.
            local code, body = t('/apisix/admin/plugin_metadata/chaitin-waf',
                ngx.HTTP_PUT, {
                    allow_degradation = true,
                    nodes = {{host = "127.0.0.1", port = 1}},
                })
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: an unset route inherits metadata true on connection failure
--- request
GET /hello?case=inherit
--- error_code: 200
--- response_body
hello world
--- response_headers_like
X-APISIX-CHAITIN-WAF: waf-err
X-APISIX-CHAITIN-WAF-ERROR: .*connection refused
--- error_log
degradation enabled, passing request



=== TEST 3: route false overrides metadata true on connection failure
--- request
GET /hello?case=disabled
--- error_code: 500
--- response_headers_like
X-APISIX-CHAITIN-WAF: waf-err
X-APISIX-CHAITIN-WAF-ERROR: .*connection refused
--- no_error_log
degradation enabled, passing request



=== TEST 4: monitor still passes connection failure with degradation disabled
--- request
GET /hello?case=monitor
--- error_code: 200
--- response_body
hello world
--- response_headers_like
X-APISIX-CHAITIN-WAF: waf-err
X-APISIX-CHAITIN-WAF-ERROR: .*connection refused
--- error_log
chaitin-waf monitor mode: detected waf error
--- no_error_log
degradation enabled, passing request



=== TEST 5: disable degradation in metadata
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/chaitin-waf',
                ngx.HTTP_PUT, {
                    allow_degradation = false,
                    nodes = {{host = "127.0.0.1", port = 1}},
                })
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: route true overrides metadata false on connection failure
--- request
GET /hello?case=enabled
--- error_code: 200
--- response_body
hello world
--- response_headers_like
X-APISIX-CHAITIN-WAF: waf-err
X-APISIX-CHAITIN-WAF-ERROR: .*connection refused
--- error_log
degradation enabled, passing request



=== TEST 7: an unset route inherits metadata false on connection failure
--- request
GET /hello?case=inherit
--- error_code: 500
--- response_headers_like
X-APISIX-CHAITIN-WAF: waf-err
X-APISIX-CHAITIN-WAF-ERROR: .*connection refused
--- no_error_log
degradation enabled, passing request



=== TEST 8: omit degradation in metadata
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/chaitin-waf',
                ngx.HTTP_PUT, {
                    nodes = {{host = "127.0.0.1", port = 1}},
                })
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: degradation remains disabled when both route and metadata omit the option
--- request
GET /hello?case=inherit
--- error_code: 500
--- response_headers
X-APISIX-CHAITIN-WAF: waf-err
--- no_error_log
degradation enabled, passing request



=== TEST 10: remove metadata
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/chaitin-waf',
                ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 11: missing metadata honors route true
--- request
GET /hello?case=enabled
--- error_code: 200
--- response_body
hello world
--- response_headers
X-APISIX-CHAITIN-WAF: err
X-APISIX-CHAITIN-WAF-ERROR: missing metadata
--- error_log
degradation enabled, passing request
--- no_error_log
[error]



=== TEST 12: missing metadata honors route false
--- request
GET /hello?case=disabled
--- error_code: 500
--- response_headers
X-APISIX-CHAITIN-WAF: err
X-APISIX-CHAITIN-WAF-ERROR: missing metadata
--- no_error_log
[error]
degradation enabled, passing request



=== TEST 13: missing metadata remains blocked when the route omits degradation
--- request
GET /hello?case=inherit
--- error_code: 500
--- response_headers
X-APISIX-CHAITIN-WAF: err
X-APISIX-CHAITIN-WAF-ERROR: missing metadata
--- no_error_log
[error]
degradation enabled, passing request



=== TEST 14: configure a detection service that rejects requests
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/chaitin-waf',
                ngx.HTTP_PUT, {
                    nodes = {{host = "127.0.0.1", port = 8088}},
                })
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- no_error_log
[error]



=== TEST 15: degradation does not bypass a WAF rejection in block mode
--- request
GET /hello?case=enabled
--- error_code: 403
--- response_body_like: blocked by Chaitin SafeLine Web Application Firewall
--- response_headers
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-ACTION: reject
X-APISIX-CHAITIN-WAF-STATUS: 403
--- error_log
request rejected by chaitin-waf
--- no_error_log
degradation enabled, passing request



=== TEST 16: monitor still passes a WAF rejection with degradation disabled
--- request
GET /hello?case=monitor
--- error_code: 200
--- response_body
hello world
--- response_headers
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-ACTION: reject
X-APISIX-CHAITIN-WAF-STATUS: 403
--- error_log
chaitin-waf monitor mode: request would have been rejected
--- no_error_log
degradation enabled, passing request
