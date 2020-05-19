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
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cors")
            local ok, err = plugin.check_schema({
                allow_origins = '',
                allow_methods = '',
                allow_headers = '',
                expose_headers = '',
                max_age = 600,
                allow_credential = true
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: wrong value of key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cors")
            local ok, err = plugin.check_schema({
                allow_origins = '',
                allow_methods = '',
                allow_headers = '',
                expose_headers = '',
                max_age = '600',
                allow_credential = true
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")

        }
    }
--- request
GET /t
--- response_body
property "max_age" validation failed: wrong type: expected integer, got string
done
--- no_error_log
[error]



=== TEST 3: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 4: update plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "**",
                            "allow_methods": "**",
                            "allow_headers": "*",
                            "expose_headers": "*",
                            "madx_age": 5,
                            "allow_credential": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 5: disable plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 6: set route(default)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "cors": {
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 7: cors default
--- request
GET /hello HTTP/1.1
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: *
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials: 
--- no_error_log
[error]



=== TEST 8: set route (cors specified)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "http://sub.domain.com,http://sub2.domain.com",
                            "allow_methods": "GET,POST",
                            "allow_headers": "headr1,headr2",
                            "expose_headers": "ex-headr1,ex-headr2",
                            "max_age": 50,
                            "allow_credential": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 9: cors specified
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://sub2.domain.com
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: http://sub2.domain.com
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: headr1,headr2
Access-Control-Expose-Headers: ex-headr1,ex-headr2
Access-Control-Max-Age: 50
Access-Control-Allow-Credentials: true
--- no_error_log
[error]



=== TEST 10: cors specified no match origin
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://sub3.domain.com
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin:
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:
--- no_error_log
[error]



=== TEST 11: set route(force wildcard)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "**",
                            "allow_methods": "**",
                            "allow_headers": "*",
                            "expose_headers": "*"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 12: cors force wildcard
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: https://sub.domain.com
ExternalHeader1: val
ExternalHeader2: val
ExternalHeader3: val
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: https://sub.domain.com
Access-Control-Allow-Methods: GET,POST,PUT,DELETE,PATCH,HEAD,OPTIONS,CONNECT,TRACE
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials:
--- no_error_log
[error]



=== TEST 13: cors force wildcard no origin
--- request
GET /hello HTTP/1.1
--- more_headers
ExternalHeader1: val
ExternalHeader2: val
ExternalHeader3: val
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET,POST,PUT,DELETE,PATCH,HEAD,OPTIONS,CONNECT,TRACE
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials:
--- no_error_log
[error]



=== TEST 14: options return directly
--- request
OPTIONS /hello HTTP/1.1
--- response_body

--- no_error_log
[error]



=== TEST 15: set route(auth plugins faills)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "key-auth": {},
                        "cors": {
                            "allow_origins": "**",
                            "allow_methods": "**",
                            "allow_headers": "*",
                            "expose_headers": "*"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 16: auth failed still work
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: https://sub.domain.com
ExternalHeader1: val
ExternalHeader2: val
ExternalHeader3: val
--- response_body
{"message":"Missing API key found in request"}
--- error_code: 401
--- response_headers
Access-Control-Allow-Origin: https://sub.domain.com
Access-Control-Allow-Methods: GET,POST,PUT,DELETE,PATCH,HEAD,OPTIONS,CONNECT,TRACE
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials:
--- no_error_log
[error]
