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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;
});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "client-control": {
                            "max_body_size": 5
                        }
                    }
            }]]
            )

        if code >= 300 then
            ngx.status = code
        end
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed



=== TEST 2: hit, failed
--- request
POST /hello
123456
--- error_code: 413



=== TEST 3: hit, failed with chunked
--- more_headers
Transfer-Encoding: chunked
--- request eval
qq{POST /hello
6\r
Hello \r
0\r
\r
}
--- error_code: 413
--- error_log
client intended to send too large chunked body



=== TEST 4: hit
--- request
POST /hello
12345



=== TEST 5: bad body size
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "client-control": {
                            "max_body_size": -1
                        }
                    }
            }]]
            )

        if code >= 300 then
            ngx.status = code
        end
        ngx.print(body)
    }
}
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin client-control err: property \"max_body_size\" validation failed: expected -1 to be at least 0"}



=== TEST 6: 0 means no limit
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "client-control": {
                            "max_body_size": 0
                        }
                    }
            }]]
            )

        if code >= 300 then
            ngx.status = code
        end
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed



=== TEST 7: hit
--- request
POST /hello
1



=== TEST 8: setup global rule and route with phase-logging functions
The functions construct the log marker dynamically to avoid false matches
from config sync logs that contain the function source code.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- global rule: log in rewrite and access to verify phase ordering
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": ["return function() ngx.log(ngx.WARN, 'PO ' .. 'global-rewrite') end"]
                        },
                        "serverless-post-function": {
                            "phase": "access",
                            "functions": ["return function() ngx.log(ngx.WARN, 'PO ' .. 'global-access') end"]
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- route with client-control + phase-logging
            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "client-control": {
                            "max_body_size": 1048576
                        },
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": ["return function() ngx.log(ngx.WARN, 'PO ' .. 'route-rewrite') end"]
                        },
                        "serverless-post-function": {
                            "phase": "access",
                            "functions": ["return function() ngx.log(ngx.WARN, 'PO ' .. 'route-access') end"]
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 9: verify phase ordering — global rewrite before route rewrite before global access
Route plugins rewrite (including client-control) must run after global rule rewrite
but before global rule access. This ensures client-control can set the body size
override via FFI before any global rule access-phase plugin reads the request body.
--- request
GET /hello
--- grep_error_log eval
qr/PO [a-z]+-[a-z]+/
--- grep_error_log_out
PO global-rewrite
PO route-rewrite
PO global-access
PO route-access



=== TEST 10: cleanup global rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1', ngx.HTTP_DELETE)
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
