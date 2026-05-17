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
log_level('info');

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = <<_EOC_;
plugins:
  - error-page
  - serverless-post-function
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: set global rule to enable plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "error-page": {}
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: set route with serverless-post-function plugin to inject error status
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-post-function": {
                            "functions" : ["return function() if ngx.var.http_x_test_status ~= nil then;ngx.exit(tonumber(ngx.var.http_x_test_status));end;end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: without plugin metadata, error response should not be modified
--- request
GET /hello
--- more_headers
X-Test-Status: 502
--- error_code: 502
--- response_headers
content-type: text/html
--- response_body_like
.*openresty.*
--- error_log
failed to read metadata for error-page



=== TEST 4: set plugin metadata with custom error pages
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
                    "enable": true,
                    "error_500": {"body": "<html><body><h1>500 Internal Server Error</h1></body></html>"},
                    "error_404": {"body": "<html><body><h1>404 Not Found</h1></body></html>"},
                    "error_502": {"body": "<html><body><h1>502 Bad Gateway</h1></body></html>"},
                    "error_503": {"body": "<html><body><h1>503 Service Unavailable</h1></body></html>"}
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: custom error page for 500
--- request
GET /hello
--- more_headers
X-Test-Status: 500
--- error_code: 500
--- response_headers
content-type: text/html
--- response_body_like
(?=.*500 Internal Server Error)



=== TEST 6: custom error page for 502
--- request
GET /hello
--- more_headers
X-Test-Status: 502
--- error_code: 502
--- response_headers
content-type: text/html
--- response_body_like
(?=.*502 Bad Gateway)



=== TEST 7: custom error page for 503
--- request
GET /hello
--- more_headers
X-Test-Status: 503
--- error_code: 503
--- response_headers
content-type: text/html
--- response_body_like
(?=.*503 Service Unavailable)



=== TEST 8: custom error page for 404
--- request
GET /hello
--- more_headers
X-Test-Status: 404
--- error_code: 404
--- response_headers
content-type: text/html
--- response_body_like
(?=.*404 Not Found)



=== TEST 9: error page not configured for status 405
--- request
GET /hello
--- more_headers
X-Test-Status: 405
--- error_code: 405
--- error_log
error page for error_405 not defined



=== TEST 10: set metadata with empty body for a status code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
                    "enable": true,
                    "error_405": {"content_type": "text/html"}
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: error page body not set falls back to default
--- request
GET /hello
--- more_headers
X-Test-Status: 405
--- error_code: 405
--- error_log
error page for error_405 not defined



=== TEST 12: set metadata with plugin disabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
                    "enable": false,
                    "error_500": {"body": "<html><body><h1>500 Internal Server Error</h1></body></html>"},
                    "error_404": {"body": "<html><body><h1>404 Not Found</h1></body></html>"}
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: plugin disabled, error response not modified
--- request
GET /hello
--- more_headers
X-Test-Status: 500
--- error_code: 500
--- response_headers
content-type: text/html
--- response_body_like
.*openresty.*



=== TEST 14: set metadata with custom content-type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
                    "enable": true,
                    "error_500": {
                        "body": "{\"code\": 500, \"message\": \"Internal Server Error\"}",
                        "content_type": "application/json"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: custom content-type is returned in response
--- request
GET /hello
--- more_headers
X-Test-Status: 500
--- error_code: 500
--- response_headers
content-type: application/json



=== TEST 16: upstream errors are not intercepted
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
                    "enable": true,
                    "error_500": {"body": "<html><body><h1>500 custom</h1></body></html>"}
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
