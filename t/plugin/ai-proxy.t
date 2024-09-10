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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();


my $resp_file = 't/assets/ai-proxy-response.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $resp = do { local $/; <$fh> };
close($fh);

print "Hello, World!\n";
print $resp;


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 6724;

            default_type 'application/json';

            location /anything {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end
                    ngx.req.read_body()
                    local body = ngx.req.get_body_data()

                    if body ~= "SELECT * FROM STUDENTS" then
                        ngx.status = 503
                        ngx.say("passthrough doesn't work")
                        return
                    end
                    ngx.say('{"foo", "bar"}')
                }
            }

            location /v1/chat/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    local test_type = ngx.req.get_headers()["test-type"]
                    if test_type == "options" then
                        if body.foo == "bar" then
                            ngx.status = 200
                            ngx.say("options works")
                        else
                            ngx.status = 500
                            ngx.say("model options feature doesn't work")
                        end
                        return
                    end

                    local header_auth = ngx.req.get_headers()["authorization"]
                    local query_auth = ngx.req.get_uri_args()["apikey"]

                    if header_auth ~= "Bearer token" and query_auth ~= "apikey" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    if header_auth == "Bearer token" or query_auth == "apikey" then
                        ngx.req.read_body()
                        local body, err = ngx.req.get_body_data()
                        body, err = json.decode(body)

                        if not body.messages or #body.messages < 1 then
                            ngx.status = 400
                            ngx.say([[{ "error": "bad request"}]])
                            return
                        end

                        if body.messages[1].content == "write an SQL query to get all rows from student table" then
                            ngx.print("SELECT * FROM STUDENTS")
                            return
                        end

                        ngx.status = 200
                        ngx.say([[$resp]])
                        return
                    end


                    ngx.status = 503
                    ngx.say("reached the end of the test suite")
                }
            }

            location /random {
                content_by_lua_block {
                    ngx.say("path override works")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: minimal viable configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local ok, err = plugin.check_schema({
                model = {
                    provider = "openai",
                    name = "gpt-4",
                },
                auth = {
                    header = {
                        some_header = "some_value"
                    }
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 2: unsupported provider
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local ok, err = plugin.check_schema({
                model = {
                    provider = "some-unique",
                    name = "gpt-4",
                },
                auth = {
                    header = {
                        some_header = "some_value"
                    }
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body eval
qr/.*provider: some-unique is not supported.*/



=== TEST 3: set route with wrong auth header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer wrongtoken"
                                }
                            },
                            "model": {
                                "provider": "openai",
                                "name": "gpt-35-turbo-instruct",
                                "options": {
                                    "max_tokens": 512,
                                    "temperature": 1.0
                                }
                            },
                            "override": {
                                "endpoint": "http://localhost:6724"
                            },
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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
--- response_body
passed



=== TEST 4: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 401
--- response_body
Unauthorized



=== TEST 5: set route with right auth header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "model": {
                                "provider": "openai",
                                "name": "gpt-35-turbo-instruct",
                                "options": {
                                    "max_tokens": 512,
                                    "temperature": 1.0
                                }
                            },
                            "override": {
                                "endpoint": "http://localhost:6724"
                            },
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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
--- response_body
passed



=== TEST 6: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 7: send request with empty body
--- request
POST /anything
--- more_headers
Authorization: Bearer token
--- error_code: 400
--- response_body_chomp
failed to get request body: request body is empty



=== TEST 8: send request with wrong method (GET) should work
--- request
GET /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 9: wrong JSON in request body should give error
--- request
GET /anything
{}"messages": [ { "role": "system", "cont
--- error_code: 400
--- response_body
{"message":"could not get parse JSON request body: Expected the end but found T_STRING at character 3"}



=== TEST 10: content-type should be JSON
--- request
POST /anything
prompt%3Dwhat%2520is%25201%2520%252B%25201
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400
--- response_body chomp
unsupported content-type: application/x-www-form-urlencoded



=== TEST 11: request schema validity check
--- request
POST /anything
{ "messages-missing": [ { "role": "system", "content": "xyz" } ] }
--- more_headers
Authorization: Bearer token
--- error_code: 400
--- response_body chomp
request format doesn't match schema: property "messages" is required



=== TEST 12: model options being merged to request body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "model": {
                                "provider": "openai",
                                "name": "some-model",
                                "options": {
                                    "foo": "bar",
                                    "temperature": 1.0
                                }
                            },
                            "override": {
                                "endpoint": "http://localhost:6724"
                            },
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "system", "content": "You are a mathematician" },
                        { "role": "user", "content": "What is 1+1?" }
                    ]
                }]],
                nil,
                {
                    ["test-type"] = "options",
                    ["Content-Type"] = "application/json",
                }
            )

            ngx.status = code
            ngx.say(actual_body)

        }
    }
--- error_code: 200
--- response_body_chomp
options_works



=== TEST 13: override path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "model": {
                                "provider": "openai",
                                "name": "some-model",
                                "options": {
                                    "foo": "bar",
                                    "temperature": 1.0
                                }
                            },
                            "override": {
                                "endpoint": "http://localhost:6724/random"
                            },
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                [[{
                    "messages": [
                        { "role": "system", "content": "You are a mathematician" },
                        { "role": "user", "content": "What is 1+1?" }
                    ]
                }]],
                nil,
                {
                    ["test-type"] = "path",
                    ["Content-Type"] = "application/json",
                }
            )

            ngx.status = code
            ngx.say(actual_body)

        }
    }
--- response_body_chomp
path override works



=== TEST 14: set route with right auth header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "model": {
                                "provider": "openai",
                                "name": "gpt-35-turbo-instruct",
                                "options": {
                                    "max_tokens": 512,
                                    "temperature": 1.0
                                }
                            },
                            "override": {
                                "endpoint": "http://localhost:6724"
                            },
                            "ssl_verify": false,
                            "passthrough": true
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:6724": 1
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
--- response_body
passed



=== TEST 15: send request with wrong method should work
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "write an SQL query to get all rows from student table" } ] }
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body
{"foo", "bar"}



=== TEST 16: set route with stream = true (SSE)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy": {
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "model": {
                                "provider": "openai",
                                "name": "gpt-35-turbo-instruct",
                                "options": {
                                    "max_tokens": 512,
                                    "temperature": 1.0,
                                    "stream": true
                                }
                            },
                            "override": {
                                "endpoint": "http://localhost:7737"
                            },
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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
--- response_body
passed



=== TEST 17: test is SSE works as expected
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })

            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local params = {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                },
                path = "/anything",
                body = [[{
                    "messages": [
                        { "role": "system", "content": "some content" }
                    ]
                }]],
            }

            local res, err = httpc:request(params)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local final_res = {}
            while true do
                local chunk, err = res.body_reader() -- will read chunk by chunk
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end

            ngx.print(#final_res .. final_res[6])
        }
    }
--- response_body_like eval
qr/6data: \[DONE\]\n\n/
