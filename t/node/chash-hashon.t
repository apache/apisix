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
log_level('info');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: add two consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack",
                            "plugins": {
                                "key-auth": {
                                    "key": "auth-jack"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            if code ~= 200 then
                ngx.say("create consumer jack failed")
                return
            end
            ngx.say(code .. " " ..body)

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "tom",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-tom"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "tom",
                            "plugins": {
                                "key-auth": {
                                    "key": "auth-tom"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )
            ngx.say(code .. " " ..body)
        }
    }
--- request
GET /t
--- response_body
200 passed
200 passed
--- no_error_log
[error]



=== TEST 2: add key auth plugin, chash hash_on consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "type": "chash",
                        "hash_on": "consumer"
                    },
                    "uri": "/server_port"
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



=== TEST 3: hit routes, hash_on one consumer
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local request_headers = {}
            request_headers["apikey"] = "auth-jack"

            local ports_count = {}
            for i = 1, 4 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", headers = request_headers})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":4,"port":"1981"}]
--- grep_error_log eval
qr/hash_on: consumer|chash_key: "jack"|chash_key: "tom"/
--- grep_error_log_out
hash_on: consumer
chash_key: "jack"
hash_on: consumer
chash_key: "jack"
hash_on: consumer
chash_key: "jack"
hash_on: consumer
chash_key: "jack"



=== TEST 4: hit routes, hash_on two consumer
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local request_headers = {}
            local ports_count = {}
            for i = 1, 4 do
                if i%2 == 0 then
                    request_headers["apikey"] = "auth-tom"
                else
                    request_headers["apikey"] = "auth-jack"
                end

                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", headers = request_headers})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":2,"port":"1981"},{"count":2,"port":"1980"}]
--- grep_error_log eval
qr/hash_on: consumer|chash_key: "jack"|chash_key: "tom"/
--- grep_error_log_out
hash_on: consumer
chash_key: "jack"
hash_on: consumer
chash_key: "tom"
hash_on: consumer
chash_key: "jack"
hash_on: consumer
chash_key: "tom"



=== TEST 5: set route(two upstream node, type chash), hash_on header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "key": "custom_header",
                        "type": "chash",
                        "hash_on": "header",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
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
--- no_error_log
[error]



=== TEST 6: hit routes, hash_on custom header
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local request_headers = {}
            request_headers["custom_header"] = "custom-one"

            local ports_count = {}
            for i = 1, 4 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", headers = request_headers})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":4,"port":"1980"}]
--- grep_error_log eval
qr/hash_on: header|chash_key: "custom-one"/
--- grep_error_log_out
hash_on: header
chash_key: "custom-one"
hash_on: header
chash_key: "custom-one"
hash_on: header
chash_key: "custom-one"
hash_on: header
chash_key: "custom-one"



=== TEST 7: hit routes, hash_on custom header miss, use default
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local request_headers = {}
            request_headers["miss-custom-header"] = "custom-one"

            local ports_count = {}
            for i = 1, 4 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", headers = request_headers})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":4,"port":"1980"}]
--- grep_error_log eval
qr/chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1/
--- grep_error_log_out
chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1
chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1
chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1
chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1



=== TEST 8: set route(two upstream node, type chash), hash_on cookie
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "key": "custom-cookie",
                        "type": "chash",
                        "hash_on": "cookie",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
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
--- no_error_log
[error]



=== TEST 9: hit routes, hash_on custom cookie
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local request_headers = {}
            request_headers["Cookie"] = "custom-cookie=cuscookie"

            local ports_count = {}
            for i = 1, 4 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", headers = request_headers})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":4,"port":"1981"}]
--- grep_error_log eval
qr/hash_on: cookie|chash_key: "cuscookie"/
--- grep_error_log_out
hash_on: cookie
chash_key: "cuscookie"
hash_on: cookie
chash_key: "cuscookie"
hash_on: cookie
chash_key: "cuscookie"
hash_on: cookie
chash_key: "cuscookie"



=== TEST 10: hit routes, hash_on custom cookie miss, use default
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local request_headers = {}
            request_headers["Cookie"] = "miss-custom-cookie=cuscookie"

            local ports_count = {}
            for i = 1, 4 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", headers = request_headers})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":4,"port":"1980"}]
--- grep_error_log eval
qr/chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1/
--- grep_error_log_out
chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1
chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1
chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1
chash_key fetch is nil, use default chash_key remote_addr: 127.0.0.1



=== TEST 11: set route(key contains uppercase letters and hyphen)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "key": "X-Sessionid",
                        "type": "chash",
                        "hash_on": "header",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
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
--- no_error_log
[error]



=== TEST 12: hit routes with header
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 6 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["X-Sessionid"] = "chash_val_" .. i
                    }
                })
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":3,"port":"1981"},{"count":3,"port":"1980"}]
--- no_error_log
[error]
--- error_log
chash_key: "chash_val_1"
chash_key: "chash_val_2"
chash_key: "chash_val_3"
chash_key: "chash_val_4"
chash_key: "chash_val_5"
chash_key: "chash_val_6"



=== TEST 13: set route(two upstream nodes, type chash), hash_on vars_combinations
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "key": "$http_custom_header-$http_custom_header_second",
                        "type": "chash",
                        "hash_on": "vars_combinations",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
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
--- no_error_log
[error]



=== TEST 14: hit routes, hash_on custom header combinations
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local request_headers = {}
            request_headers["custom_header"] = "custom-one"
            request_headers["custom_header_second"] = "custom-two"

            local ports_count = {}
            for i = 1, 4 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", headers = request_headers})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":4,"port":"1980"}]
--- grep_error_log eval
qr/hash_on: vars_combinations|chash_key: "custom-one-custom-two"/
--- grep_error_log_out
hash_on: vars_combinations
chash_key: "custom-one-custom-two"
hash_on: vars_combinations
chash_key: "custom-one-custom-two"
hash_on: vars_combinations
chash_key: "custom-one-custom-two"
hash_on: vars_combinations
chash_key: "custom-one-custom-two"
