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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: reject an unknown run_policy in _meta
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "_meta": {
                                "run_policy": "prefer_global"
                            },
                            "phase": "rewrite",
                            "functions": ["return function() end"]
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body_like eval
qr/property \\"run_policy\\" validation failed: matches none of the enum values/



=== TEST 2: same plugin in a global rule and on a route, no run_policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": ["return function() ngx.log(ngx.WARN, 'global-', 'instance ran') end"]
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": ["return function() ngx.log(ngx.WARN, 'route-', 'instance ran') end"]
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
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



=== TEST 3: both instances run by default
--- request
GET /hello
--- response_body
hello world
--- error_log
global-instance ran
route-instance ran



=== TEST 4: set run_policy on the route's plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "serverless-pre-function": {
                            "_meta": {
                                "run_policy": "prefer_route"
                            },
                            "phase": "rewrite",
                            "functions": ["return function() ngx.log(ngx.WARN, 'route-', 'instance ran') end"]
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
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



=== TEST 5: only the route instance runs
--- request
GET /hello
--- response_body
hello world
--- error_log
route-instance ran
--- no_error_log
global-instance ran



=== TEST 6: set run_policy on the global rule's plugin instead
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "_meta": {
                                "run_policy": "prefer_route"
                            },
                            "phase": "rewrite",
                            "functions": ["return function() ngx.log(ngx.WARN, 'global-', 'instance ran') end"]
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": ["return function() ngx.log(ngx.WARN, 'route-', 'instance ran') end"]
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
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



=== TEST 7: only the route instance runs
--- request
GET /hello
--- response_body
hello world
--- error_log
route-instance ran
--- no_error_log
global-instance ran



=== TEST 8: the global instance still runs for a route without the plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello1",
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
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



=== TEST 9: hit the route without the plugin
--- request
GET /hello1
--- response_body
hello1 world
--- error_log
global-instance ran
--- no_error_log
route-instance ran



=== TEST 10: the global instance still runs when no route matches
--- request
GET /not_found
--- error_code: 404
--- error_log
global-instance ran



=== TEST 11: disable the route's plugin, run_policy set on the route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "serverless-pre-function": {
                            "_meta": {
                                "disable": true,
                                "run_policy": "prefer_route"
                            },
                            "phase": "rewrite",
                            "functions": ["return function() ngx.log(ngx.WARN, 'route-', 'instance ran') end"]
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
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



=== TEST 12: a disabled route plugin does not suppress the global instance
--- request
GET /hello
--- response_body
hello world
--- error_log
global-instance ran
--- no_error_log
route-instance ran



=== TEST 13: route plugin whose _meta.filter does not match, run_policy set on the route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/hello",
                    "plugins": {
                        "serverless-pre-function": {
                            "_meta": {
                                "filter": [["arg_version", "==", "v2"]],
                                "run_policy": "prefer_route"
                            },
                            "phase": "rewrite",
                            "functions": ["return function() ngx.log(ngx.WARN, 'route-', 'instance ran') end"]
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    }
                }]=]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: the route owns the plugin, so neither instance runs when its filter is false
--- request
GET /hello?version=v1
--- response_body
hello world
--- no_error_log
global-instance ran
route-instance ran



=== TEST 15: the route instance runs when its filter matches
--- request
GET /hello?version=v2
--- response_body
hello world
--- error_log
route-instance ran
--- no_error_log
global-instance ran



=== TEST 16: permissive cors in a global rule, restricted cors on a route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "*"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "cors": {
                            "allow_origins": "http://example.com"
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
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



=== TEST 17: without run_policy the global rule's "*" leaks to a disallowed origin
--- request
GET /hello
--- more_headers
Origin: http://evil.com
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: *



=== TEST 18: set run_policy on the route's cors
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "cors": {
                            "_meta": {
                                "run_policy": "prefer_route"
                            },
                            "allow_origins": "http://example.com"
                        }
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
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



=== TEST 19: a disallowed origin gets no Access-Control-Allow-Origin
--- request
GET /hello
--- more_headers
Origin: http://evil.com
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin:



=== TEST 20: a preflight from the allowed origin is answered by the route's cors
--- request
OPTIONS /hello
--- more_headers
Origin: http://example.com
Access-Control-Request-Method: GET
--- error_code: 200
--- response_headers
Access-Control-Allow-Origin: http://example.com



=== TEST 21: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            t('/apisix/admin/routes/2', ngx.HTTP_DELETE)
            local code, body = t('/apisix/admin/global_rules/1', ngx.HTTP_DELETE)
            ngx.say(body)
        }
    }
--- response_body
passed
