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
log_level('info');

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

=== TEST 1: use variable in rate and burst with default value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rate": "${http_rate ?? 0.1}",
                                "burst": "${http_burst ?? 0.1}",
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "policy": "local"
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



=== TEST 2: request without rate/burst headers - uses default values
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- error_code eval
[200, 503]



=== TEST 3: request with rate and burst header
--- request
GET /hello
--- more_headers
rate: 2
burst: 2
--- timeout: 10s
--- error_code: 200
--- error_log
limit req rate: 2, burst: 2



=== TEST 4: schema check with both rate/burst and rules should fail
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rate": 10,
                                "burst": 2,
                                "key": "remote_addr",
                                "rules": [
                                    {
                                        "rate": 5,
                                        "burst": 1,
                                        "key": "remote_addr"
                                    }
                                ]
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
                ngx.print(body)
                return
            end
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-req err: value should match only one schema, but matches both schemas 1 and 2"}



=== TEST 5: duplicate keys in rules should fail
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rules": [
                                    {
                                        "rate": 5,
                                        "burst": 1,
                                        "key": "${http_user}"
                                    },
                                    {
                                        "rate": 10,
                                        "burst": 2,
                                        "key": "${http_user}"
                                    }
                                ]
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
                ngx.print(body)
                return
            end
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-req err: duplicate key '${http_user}' in rules"}



=== TEST 6: setup route with multi-level rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-req": {
                                "rules": [
                                    {
                                        "rate": 0.01,
                                        "burst": "${http_burst1 ?? 2}",
                                        "key": "${http_user}"
                                    },
                                    {
                                        "rate": 0.01,
                                        "burst": 4,
                                        "key": "${http_project}"
                                    }
                                ],
                                "rejected_code": 503,
                                "rejected_msg": "rate limited",
                                "nodelay": true
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



=== TEST 7: no rule matches - returns 500
--- request
GET /hello
--- error_code: 500
--- error_log
failed to get limit req rules




=== TEST 8: match user rule
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local ress = {}
            for i = 1, 4, 1 do
                local res = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { ["user"] = "jack"}
                })
                table.insert(ress, res.status)
            end

            ngx.say(json.encode(ress))
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
[200,200,200,503]



=== TEST 9: match project rule
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local ress = {}
            for i = 1, 6, 1 do
                local res = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { ["project"] = "apisix"}
                })
                table.insert(ress, res.status)
            end

            ngx.say(json.encode(ress))
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
[200,200,200,200,200,503]



=== TEST 10: match multi rules and specific burst by header
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local ress = {}
            for i = 1, 6, 1 do
                local res = httpc:request_uri(uri, {
                    method = "GET",
                    headers = { ["user"] = "jack2" , ["project"] = "apisix2", ["burst1"] = "3"}
                })
                table.insert(ress, res.status)
            end

            ngx.say(json.encode(ress))
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
[200,200,200,200,503,503]
