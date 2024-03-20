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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {uri = "http://127.0.0.1:8199"},
                {request_headers = {"test"}},
                {uri = 3233},
                {uri = "http://127.0.0.1:8199", request_headers = "test"},
                {uri = "http://127.0.0.1:8199", request_method = "POST"},
                {uri = "http://127.0.0.1:8199", request_method = "PUT"}
            }
            local plugin = require("apisix.plugins.forward-auth")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done
property "uri" is required
property "uri" validation failed: wrong type: expected string, got number
property "request_headers" validation failed: wrong type: expected array, got string
done
property "request_method" validation failed: matches none of the enum values



=== TEST 2: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/upstreams/u1",
                    data = [[{
                        "nodes": {
                            "127.0.0.1:1984": 1
                        },
                        "type": "roundrobin"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/auth",
                    data = {
                        plugins = {
                            ["serverless-pre-function"] = {
                                phase = "rewrite",
                                functions =  {
                                    [[return function(conf, ctx)
                                        local core = require("apisix.core");
                                        if core.request.header(ctx, "Authorization") == "111" then
                                            core.response.exit(200);
                                        end
                                    end]],
                                    [[return function(conf, ctx)
                                        local core = require("apisix.core");
                                        if core.request.header(ctx, "Authorization") == "222" then
                                            core.response.set_header("X-User-ID", "i-am-an-user");
                                            core.response.exit(200);
                                        end
                                    end]],
                                    [[return function(conf, ctx)
                                        local core = require("apisix.core");
                                        if core.request.header(ctx, "Authorization") == "333" then
                                            core.response.set_header("Location", "http://example.com/auth");
                                            core.response.exit(403);
                                        end
                                    end]],
                                    [[return function(conf, ctx)
                                        local core = require("apisix.core");
                                        if core.request.header(ctx, "Authorization") == "444" then
                                            core.response.exit(403, core.request.headers(ctx));
                                        end
                                    end]],
                                    [[
                                        return function(conf, ctx)
                                        local core = require("apisix.core")
                                        if core.request.get_method() == "POST" then
                                            if core.request.header(ctx, "Authorization") == "large-body" then
                                                core.response.set_header("X-User-ID", "large-body")
                                                core.response.exit(200)
                                            end
                                            if core.request.header(ctx, "Authorization") == "i-am-not-an-user-large-body" then
                                                core.response.exit(403)
                                            end
                                        end
                                    end]],
                                    [[return function(conf, ctx)
                                        local core = require("apisix.core")
                                        if core.request.get_method() == "POST" then
                                           local req_body, err = core.request.get_body()
                                           if err then
                                               core.response.exit(400)
                                           end
                                           if req_body then
                                               local data, err = core.json.decode(req_body)
                                               if err then
                                                   core.response.exit(400)
                                               end
                                               if data["authorization"] == "555" then
                                                   core.response.set_header("X-User-ID", "i-am-an-user")
                                                   core.response.exit(200)
                                               elseif data["authorization"] == "666" then
                                                   core.response.set_header("Location", "http://example.com/auth")
                                                   core.response.exit(403)
                                               end
                                           end
                                        end
                                    end]],
                                    [[return function(conf, ctx)
                                        local core = require("apisix.core");
                                        if core.request.header(ctx, "Authorization") == "token-headers-test" then
                                            if core.request.get_method() == "POST" then
                                                if core.request.header(ctx, "Content-Length") or core.request.header(ctx, "Transfer-Encoding") or core.request.header(ctx, "Content-Encoding") then
                                                    core.response.exit(200)
                                                else
                                                    core.response.exit(403)
                                                end
                                            else
                                                if core.request.header(ctx, "Content-Length") or core.request.header(ctx, "Transfer-Encoding") or core.request.header(ctx, "Content-Encoding") then
                                                    core.response.exit(403)
                                                else
                                                    core.response.exit(200)
                                                end
                                            end
                                        end
                                    end]]
                                }
                            }
                        },
                        uri = "/auth"
                    },
                },
                {
                    url = "/apisix/admin/routes/echo",
                    data = [[{
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions": [
                                    "return function (conf, ctx)
                                        local core = require(\"apisix.core\");
                                        core.response.exit(200, core.request.headers(ctx));
                                    end"
                                ]
                            }
                        },
                        "uri": "/echo"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "upstream_headers": ["X-User-ID"],
                                "client_headers": ["Location"]
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/hello"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/2",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"]
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/empty"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/3",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_method": "POST",
                                "upstream_headers": ["X-User-ID"],
                                "client_headers": ["Location"]
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/ping"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/4",
                    data = [[{
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "rewrite",
                                "functions" : ["return function() require(\"apisix.core\").response.exit(444); end"]
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/crashed-auth"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/5",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/crashed-auth",
                                "request_headers": ["Authorization"],
                                "upstream_headers": ["X-User-ID"],
                                "client_headers": ["Location"]
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/nodegr"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/6",
                    data = [[{
                        "uri": "/hello",
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/crashed-auth",
                                "request_headers": ["Authorization"],
                                "upstream_headers": ["X-User-ID"],
                                "client_headers": ["Location"],
                                "allow_degradation": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "test.com:1980": 1
                            },
                            "type": "roundrobin"
                        }
                    }]],
                },
                {
                    url = "/apisix/admin/routes/7",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "upstream_headers": ["X-User-ID"],
                                "request_headers": ["Authorization"],
                                "request_method": "POST"
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/large-body"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/8",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.39.40.1:9999/auth",
                                "request_headers": ["Authorization"],
                                "upstream_headers": ["X-User-ID"],
                                "client_headers": ["Location"],
                                "status_on_error": 503,
                                "allow_degradation": false
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/onerror"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/9",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "POST"
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/verify-auth-post"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/10",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "GET"
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/verify-auth-get"
                    }]],
                }
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n" x 13



=== TEST 3: hit route (test request_headers)
--- request
GET /hello
--- more_headers
Authorization: 111
--- response_body_like eval
qr/\"authorization\":\"111\"/



=== TEST 4: hit route (test upstream_headers)
--- request
GET /hello
--- more_headers
Authorization: 222
--- response_body_like eval
qr/\"x-user-id\":\"i-am-an-user\"/



=== TEST 5: hit route (test client_headers)
--- request
GET /hello
--- more_headers
Authorization: 333
--- error_code: 403
--- response_headers
Location: http://example.com/auth



=== TEST 6: hit route (check APISIX generated headers and ignore client headers)
--- request
GET /hello
--- more_headers
Authorization: 444
X-Forwarded-Host: apisix.apache.org
--- error_code: 403
--- response_body eval
qr/\"x-forwarded-proto\":\"http\"/     and qr/\"x-forwarded-method\":\"GET\"/    and
qr/\"x-forwarded-host\":\"localhost\"/ and qr/\"x-forwarded-uri\":\"\\\/hello\"/ and
qr/\"x-forwarded-for\":\"127.0.0.1\"/
--- response_body_unlike eval
qr/\"x-forwarded-host\":\"apisix.apache.org\"/



=== TEST 7: hit route (not send upstream headers)
--- request
GET /empty
--- more_headers
Authorization: 222
--- response_body_unlike eval
qr/\"x-user-id\":\"i-am-an-user\"/



=== TEST 8: hit route (not send client headers)
--- request
GET /empty
--- more_headers
Authorization: 333
--- error_code: 403
--- response_headers
!Location



=== TEST 9: hit route (test upstream_headers when use post method)
--- request
POST /ping
{"authorization": "555"}
--- response_body_like eval
qr/\"x-user-id\":\"i-am-an-user\"/



=== TEST 10: hit route (test client_headers when use post method)
--- request
POST /ping
{"authorization": "666"}
--- error_code: 403
--- response_headers
Location: http://example.com/auth



=== TEST 11: hit route (unavailable auth server, expect failure)
--- request
GET /nodegr
--- more_headers
Authorization: 111
--- error_code: 403
--- error_log
failed to process forward auth, err: closed



=== TEST 12: hit route (unavailable auth server, allow degradation)
--- request
GET /hello
--- more_headers
Authorization: 111
--- error_code: 200



=== TEST 13: Verify status_on_error
--- request
GET /onerror
--- more_headers
Authorization: 333
--- error_code: 503



=== TEST 14: test large body
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t    = require("lib.test_admin")
            local http = require("resty.http")

            local tempFileName = os.tmpname()
            local file = io.open(tempFileName, "wb")

            local fileSizeInBytes = 11 * 1024 * 1024 -- 11MB
            for i = 1, fileSizeInBytes do
                file:write(string.char(0))
            end
            file:close()

            local large_body = t.read_file(tempFileName)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/large-body"

            local httpc = http.new()
            local res1, err = httpc:request_uri(uri,
                {
                    method = "POST",
                    body = large_body,
                    headers = {
                        ["Authorization"] = "i-am-not-an-user-large-body",
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                }
            )
            assert(res1.status == 403, "status: " .. res1.status)
            data1 = core.json.decode(res1.body)

            local res2, err = httpc:request_uri(uri,
                {
                    method = "POST",
                    body = large_body,
                    headers = {
                        ["Authorization"] = "large-body",
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                }
            )
            assert(res2.status == 200, "status: " .. res2.status)
            data2 = core.json.decode(res2.body)
            assert(data2["x-user-id"] == "large-body", "x-user-id: " .. data2["x-user-id"])
        }
    }
--- error_code: 200



=== TEST 15: verify auth server forward headers for request_method=GET
--- request
GET /verify-auth-get
--- more_headers
Authorization: token-headers-test
--- error_code: 200



=== TEST 16: verify auth server forward headers for request_method=POST for GET upstream
--- request
GET /verify-auth-post
--- more_headers
Authorization: token-headers-test
--- error_code: 200



=== TEST 17: verify auth server forward headers for request_method=POST
--- request
POST /verify-auth-post
{"authorization": "token-headers-test"}
--- more_headers
Authorization: token-headers-test
--- error_code: 200



=== TEST 18: verify auth server forward headers for request_method=GET for POST upstream
--- request
POST /verify-auth-get
{"authorization": "token-headers-test"}
--- more_headers
Authorization: token-headers-test
--- error_code: 200
