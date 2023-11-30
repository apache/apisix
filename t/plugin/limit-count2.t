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


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: invalid route: wrong rejected_msg type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 1,
                            "time_window": 600,
                            "rejected_code": 503,
                            "rejected_msg": true,
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-count err: property \"rejected_msg\" validation failed: wrong type: expected string, got boolean"}



=== TEST 2: invalid route: wrong rejected_msg length
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 1,
                            "time_window": 600,
                            "rejected_code": 503,
                            "rejected_msg": "",
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-count err: property \"rejected_msg\" validation failed: string too short, expected at least 1, got 0"}



=== TEST 3: set route, with rejected_msg
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 1,
                            "time_window": 600,
                            "rejected_code": 503,
                            "rejected_msg": "Requests are too frequent, please try again later.",
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
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



=== TEST 4: rejected_msg, request normal
--- request
GET /hello
--- response_body
hello world



=== TEST 5: rejected_msg, request frequent
--- request
GET /hello
--- error_code: 503
--- response_body
{"error_msg":"Requests are too frequent, please try again later."}



=== TEST 6: update route, use new limit configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "http_a",
                            "key_type": "var"
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
--- response_body
passed



=== TEST 7: exceed the burst when key_type is var
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 4 do
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
--- response_body
[200,200,503,503]



=== TEST 8: bypass empty key when key_type is var
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 4 do
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
--- response_body
[200,200,503,503]



=== TEST 9: update plugin to set key_type to var_combination
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
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
--- response_body
passed



=== TEST 10: exceed the burst when key_type is var_combination
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 4 do
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
--- response_body
[200,200,503,503]



=== TEST 11: don`t exceed the burst when key_type is var_combination
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
--- response_body
[503,200]



=== TEST 12: request when key is missing
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 4 do
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
--- response_body
[200,200,503,503]
--- error_log
The value of the configured key is empty, use client IP instead



=== TEST 13: update plugin to set invalid key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
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
--- response_body
passed



=== TEST 14: request when key is invalid
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 4 do
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
--- response_body
[200,200,503,503]
--- error_log
The value of the configured key is empty, use client IP instead



=== TEST 15: limit count in group
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "group": "services_1"
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
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "group": "services_1"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello_chunked"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: hit multiple paths
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri1 = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local uri2 = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello_chunked"
            local ress = {}
            for i = 1, 4 do
                local httpc = http.new()
                local uri
                if i % 2 == 1 then
                    uri = uri1
                else
                    uri = uri2
                end

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
--- response_body
[200,200,503,503]



=== TEST 17: limit count in group, configuration is from services
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "group": "afafafhao"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end


            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "1",
                    "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "1",
                    "uri": "/hello_chunked"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 18: hit multiple paths
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri1 = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local uri2 = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello_chunked"
            local ress = {}
            for i = 1, 4 do
                local httpc = http.new()
                local uri
                if i % 2 == 1 then
                    uri = uri1
                else
                    uri = uri2
                end

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
--- response_body
[200,200,503,503]



=== TEST 19: configuration from the same group should be the same
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 1,
                            "time_window": 60,
                            "rejected_code": 503,
                            "group": "afafafhao"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- error_log
[error]
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-count err: group conf mismatched"}



=== TEST 20: group with constant key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key_type": "constant",
                            "group": "afafafhao2"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
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



=== TEST 21: hit multiple paths
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local uri1 = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local uri2 = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello_chunked"
            local ress = {}
            for i = 1, 4 do
                local httpc = http.new()
                local uri
                if i % 2 == 1 then
                    uri = uri1
                else
                    uri = uri2
                end

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
--- grep_error_log eval
qr/limit key: afafafhao2:remote_addr/
--- grep_error_log_out
limit key: afafafhao2:remote_addr
limit key: afafafhao2:remote_addr
limit key: afafafhao2:remote_addr
limit key: afafafhao2:remote_addr
--- response_body
[200,200,503,503]



=== TEST 22: group with disable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "group": "abcd",
                            "_meta": {
                                "disable": false
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
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
