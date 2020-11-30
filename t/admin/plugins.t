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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: get plugins' name
--- request
GET /apisix/admin/plugins/list
--- response_body_like eval
qr/\["zipkin","request-id","fault-injection","serverless-pre-function","batch-requests","cors","ip-restriction","referer-restriction","uri-blocker","request-validation","openid-connect","wolf-rbac","hmac-auth","basic-auth","jwt-auth","key-auth","consumer-restriction","authz-keycloak","proxy-mirror","proxy-cache","proxy-rewrite","api-breaker","limit-conn","limit-count","limit-req","node-status","redirect","response-rewrite","grpc-transcode","prometheus","echo","http-logger","sls-logger","tcp-logger","kafka-logger","syslog","udp-logger","example-plugin","serverless-post-function"\]/
--- no_error_log
[error]



=== TEST 2: wrong path
--- request
GET /apisix/admin/plugins
--- error_code: 400
--- response_body
{"error_msg":"not found plugin name"}
--- no_error_log
[error]



=== TEST 3: get plugin schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/limit-req',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{"rate":{"minimum":0,"type":"number"},"burst":{"minimum":0,"type":"number"},"key":{"enum":["remote_addr","server_addr","http_x_real_ip","http_x_forwarded_for","consumer_name"],"type":"string"},"rejected_code":{"type":"integer","default":503,"minimum":200}},"required":["rate","burst","key"],"type":"object"}
                ]]
                )

            ngx.status = code
        }
    }
--- no_error_log
[error]



=== TEST 4: get plugin node-status schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/node-status',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{"disable":{"type":"boolean"}},"additionalProperties":false,"type":"object"}
                ]]
                )

            ngx.status = code
        }
    }
--- no_error_log
[error]



=== TEST 5: get plugin prometheus schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/prometheus',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{"disable":{"type":"boolean"}},"additionalProperties":false,"type":"object"}
                ]]
                )

            ngx.status = code
        }
    }
--- no_error_log
[error]



=== TEST 6: get plugin basic-auth schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/basic-auth',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{"disable":{"type":"boolean"}},"title":"work with route or service object","additionalProperties":false,"type":"object"}
                ]]
                )

            ngx.status = code
        }
    }
--- no_error_log
[error]



=== TEST 7: get plugin basic-auth schema by schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/basic-auth?schema_type=consumer',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with consumer object","additionalProperties":false,"required":["username","password"],"properties":{"username":{"type":"string"},"password":{"type":"string"}},"type":"object"}
                ]]
                )

            ngx.status = code
        }
    }
--- no_error_log
[error]
