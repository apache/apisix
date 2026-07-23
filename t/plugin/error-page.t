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

    if (!defined $block->http_config) {
        $block->set_value("http_config", <<_EOC_);
    server {
        listen 1987;
        location / {
            return 500 "real upstream 500 error";
        }
    }
_EOC_
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
--- response_body_like eval
qr/<body><h1>500 Internal Server Error<\/h1><\/body>/



=== TEST 6: custom error page for 502
--- request
GET /hello
--- more_headers
X-Test-Status: 502
--- error_code: 502
--- response_headers
content-type: text/html
--- response_body_like eval
qr/<body><h1>502 Bad Gateway<\/h1><\/body>/



=== TEST 7: custom error page for 503
--- request
GET /hello
--- more_headers
X-Test-Status: 503
--- error_code: 503
--- response_headers
content-type: text/html
--- response_body_like eval
qr/<body><h1>503 Service Unavailable<\/h1><\/body>/



=== TEST 8: custom error page for 404
--- request
GET /hello
--- more_headers
X-Test-Status: 404
--- error_code: 404
--- response_headers
content-type: text/html
--- response_body_like eval
qr/<body><h1>404 Not Found<\/h1><\/body>/



=== TEST 9: error page not configured for status 405
--- request
GET /hello
--- more_headers
X-Test-Status: 405
--- error_code: 405



=== TEST 10: set metadata with empty body for a status code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
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



=== TEST 12: delete plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: after metadata deleted, error response not modified
--- request
GET /hello
--- more_headers
X-Test-Status: 500
--- error_code: 500
--- response_headers
content-type: text/html
--- response_body_like
.*openresty.*
--- error_log
failed to read metadata for error-page



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



=== TEST 17: create a route pointing to a real upstream returning 500
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/upstream-test",
                    "upstream": {
                        "nodes": {"127.0.0.1:1987": 1},
                        "type": "roundrobin"
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



=== TEST 18: upstream 500 responses are not intercepted by error-page plugin
--- request
GET /upstream-test
--- error_code: 500
--- response_body_like eval
qr/real upstream 500 error/



=== TEST 19: create route pointing to unreachable upstream (for nginx error)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
                    "enable": true,
                    "error_502": {"body": "<html><body><h1>502 custom</h1></body></html>"}
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            local code2, body2 = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/nginx-error-test",
                    "upstream": {
                        "nodes": {"127.0.0.1:1": 1},
                        "type": "roundrobin"
                    }
                }]]
                )
            if code2 >= 300 then
                ngx.status = code2
            end
            ngx.say(body2)
        }
    }
--- response_body
passed



=== TEST 20: nginx proxy errors (connection refused) are intercepted by error-page plugin
--- request
GET /nginx-error-test
--- error_code: 502
--- response_body_like eval
qr/502 custom/
--- error_log
connect() failed (111: Connection refused)


=== TEST 21: set plugin metadata with Nginx variables in error page body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
                    "enable": true,
                    "error_404": {"body": "<html><body>rid=$request_id host=$host addr=${remote_addr}</body></html>"},
                    "error_500": {"body": "<html><body>custom 500</body></html>"},
                    "error_502": {"body": "<html><body>custom 502</body></html>"},
                    "error_503": {"body": "<html><body>custom 503</body></html>"}
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



=== TEST 22: Nginx variables in error page body are resolved
--- request
GET /hello
--- more_headers
X-Test-Status: 404
--- error_code: 404
--- response_headers
content-type: text/html
--- response_body_like eval
qr/rid=[0-9a-f]{32} host=localhost addr=127\.0\.0\.1/



=== TEST 23: variable with default value operator
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
                    "enable": true,
                    "error_404": {"body": "<html><body>missing=$nonexistent_var??fallback</body></html>"}
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



=== TEST 24: undefined variable falls back to default value
--- request
GET /hello
--- more_headers
X-Test-Status: 404
--- error_code: 404
--- response_body_like eval
qr/missing=fallback/



=== TEST 25: escaped dollar sign is not resolved
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-page',
                ngx.HTTP_PUT,
                [[{
                    "enable": true,
                    "error_404": {"body": "<html><body>price=\$100 rid=$request_id</body></html>"}
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



=== TEST 26: escaped dollar sign stays literal, real variable resolved
--- request
GET /hello
--- more_headers
X-Test-Status: 404
--- error_code: 404
--- response_body_like eval
qr/price=\\\$100 rid=[0-9a-f]{32}/
