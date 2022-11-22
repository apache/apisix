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

log_level('info');
repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: add plugin for delay test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 4,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "upstream_node",
                        "uri": "/hello*"
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



=== TEST 2: the second request will timeout because of delay,  error code will be ''
--- abort
--- timeout: 500ms
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- error_code eval
[200, '']



=== TEST 3: add nodelay flag
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1/plugins',
                ngx.HTTP_PATCH,
                [[{
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 4,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "nodelay": true
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



=== TEST 4: the second request will not timeout because of nodelay
--- abort
--- timeout: 500ms
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- error_code eval
[200, 200]



=== TEST 5: key type is var_combination
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 0.1,
                            "rejected_code": 503,
                            "key": "$http_a $http_b",
                            "key_type": "var_combination"
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



=== TEST 6: exceed the burst
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"

            local ress = {}
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {headers = {a = 1}})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, res.status)
            end
            ngx.say(json.encode(ress))
        }
    }
--- request
GET /t
--- response_body
[200,503]



=== TEST 7: don't exceed the burst
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"

            local ress = {}
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {headers = {a = i}})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, res.status)
            end
            ngx.say(json.encode(ress))
        }
    }
--- request
GET /t
--- response_body
[200,200]



=== TEST 8: request when key is missing
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"

            local ress = {}
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, res.status)
            end
            ngx.say(json.encode(ress))
        }
    }
--- request
GET /t
--- response_body
[200,503]
--- error_log
The value of the configured key is empty, use client IP instead



=== TEST 9: update plugin to set invalid key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 0.1,
                            "rejected_code": 503,
                            "key": "abcdefgh",
                            "key_type": "var_combination"
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



=== TEST 10: request when key is invalid
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"

            local ress = {}
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, res.status)
            end
            ngx.say(json.encode(ress))
        }
    }
--- request
GET /t
--- response_body
[200,503]
--- error_log
The value of the configured key is empty, use client IP instead
