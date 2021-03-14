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
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
run_tests;

__DATA__

=== TEST 1:  add plugin
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                body = 'Hello world',
                headers = {
                    ["X-Server-id"] = 3
                }
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



=== TEST 2:  add plugin with wrong status_code
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                status_code = 599
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
property "status_code" validation failed: expected 599 to be smaller than 598
--- no_error_log
[error]



=== TEST 3:  add plugin fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                body = 2,
                headers = {
                    ["X-Server-id"] = "3"
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
property "body" validation failed: wrong type: expected string, got number
--- no_error_log
[error]



=== TEST 4: set header(rewrite header and body)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers" : {
                                "X-Server-id": 3,
                                "X-Server-status": "on",
                                "Content-Type": ""
                            },
                            "body": "new body\n"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/with_header"
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



=== TEST 5: check body with deleted header
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/with_header"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end

            if res.headers['Content-Type'] then
                ngx.say('fail content-type should not be exist, now is'..res.headers['Content-Type'])
                return
            end

            if res.headers['X-Server-status'] ~= 'on' then
                ngx.say('fail X-Server-status needs to be on')
                return
            end

            if res.headers['X-Server-id'] ~= '3' then
                ngx.say('fail X-Server-id needs to be 3')
                return
            end

            ngx.print(res.body)
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
new body
--- no_error_log
[error]



=== TEST 6: set body only and keep header the same
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "new body2\n"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/with_header"
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



=== TEST 7: check body and header not changed
--- request
GET /with_header
--- more_headers
resp-X-Server-id: 100
resp-Content-Type: application/xml
resp-Content-Encoding: gzip
resp-Content-Length: 4
resp-Last-Modified: Wed, 21 Oct 2015 07:28:00 GMT
resp-ETag: "33a64df551425fcc55e4d42a148795d9f25f89d4"
--- response_body
new body2
--- response_headers
X-Server-id: 100
Content-Type: application/xml
Content-Length:
Content-Encoding:
Last-Modified:
ETag:
--- no_error_log
[error]



=== TEST 8: set location header with 302 code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers": {
                                "Location":"https://www.iresty.com"
                            },
                            "status_code":302
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



=== TEST 9: check 302 redirect
--- request
GET /hello
--- error_code eval
302
--- response_headers
Location: https://www.iresty.com
--- no_error_log
[error]



=== TEST 10:  empty string in header field
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                status_code = 200,
                headers = {
                    [""] = 2
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
invalid field length in header
--- no_error_log
[error]



=== TEST 11: array in header value
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                status_code = 200,
                headers = {
                    ["X-Name"] = {}
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
invalid type as header value
--- no_error_log
[error]



=== TEST 12: set body in base64
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "SGVsbG8K",
                            "body_base64": true
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



=== TEST 13: check base64 content
--- request
GET /hello
--- response_body
Hello
--- no_error_log
[error]



=== TEST 14: set body with not well formed base64
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                            body = "1",
                            body_base64 =  true
            })
            if not ok then
                ngx.say(err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
invalid base64 content
--- no_error_log
[error]



=== TEST 15: print the plugin `conf` in etcd, no dirty data
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local encode_with_keys_sorted = require("toolkit.json").encode

            local code, _, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers" : {
                                "X-Server-id": 3,
                                "X-Server-status": "on",
                                "Content-Type": ""
                            },
                            "body": "new body\n"
                        }
                    },
                    "uri": "/with_header"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end

            local resp_data = core.json.decode(body)
            ngx.say(encode_with_keys_sorted(resp_data.node.value.plugins))
        }
    }
--- request
GET /t
--- response_body
{"response-rewrite":{"body":"new body\n","body_base64":false,"headers":{"Content-Type":"","X-Server-id":3,"X-Server-status":"on"}}}
--- no_error_log
[error]



=== TEST 16:  additional property
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                body = 'Hello world',
                headers = {
                    ["X-Server-id"] = 3
                },
                invalid_att = "invalid",
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
additional properties forbidden, found invalid_att
--- no_error_log
[error]



=== TEST 17: add validate vars
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                vars = {
                    {"status","==",200}
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 18: add plugin with invalidate vars
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                vars = {
                    {}
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
property "vars" validation failed: failed to validate item 1: expect array to have at least 2 items
--- no_error_log
[error]



=== TEST 19: set route with http status code as expr
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "new body3\n",
                            "status_code": 403,
                            "vars": [
                                ["status","==",500]
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uris": ["/server_error","/hello"]
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



=== TEST 20: check http code that matches http_status
--- request
GET /server_error
--- response_body
new body3
--- error_code eval
403
--- error_log
500 Internal Server Error



=== TEST 21: check http code that not matches http_status
--- request
GET /hello
--- response_body
hello world
--- error_code eval
200
--- no_error_log
[error]
