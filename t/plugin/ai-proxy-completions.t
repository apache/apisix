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
    $ENV{AI_PROXY_TEST_SCHEME} = "http";
}

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

            location /v1/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

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
                        local esc = body:gsub('"\\\""', '\"')
                        body, err = json.decode(esc)

                        if body.prompt then
                            ngx.status = 200
                            ngx.say([[$resp]])
                            return
                        end
                    else
                        ngx.status = 401
                    end
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
                route_type = "llm/chat",
                model = {
                    provider = "openai",
                    name = "gpt-4",
                },
                auth = {
                    source = "header",
                    value = "some value",
                    name = "some name",
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



=== TEST 2: set route with wrong auth header
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
                            "route_type": "llm/completions",
                            "auth": {
                                "source": "header",
                                "name": "Authorization",
                                "value": "Bearer wrongtoken"
                            },
                            "model": {
                                "provider": "openai",
                                "name": "gpt-35-turbo-instruct",
                                "options": {
                                    "max_tokens": 512,
                                    "temperature": 1.0,
                                    "upstream_host": "localhost",
                                    "upstream_port": 6724
                                }
                            }
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



=== TEST 3: send request
--- request
POST /anything
{"prompt": "what is 1 + 1"}
--- error_code: 401
--- response_body
Unauthorized



=== TEST 4: set route with correct auth header
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
                            "route_type": "llm/completions",
                            "auth": {
                                "source": "header",
                                "name": "Authorization",
                                "value": "Bearer token"
                            },
                            "model": {
                                "provider": "openai",
                                "name": "gpt-35-turbo-instruct",
                                "options": {
                                    "max_tokens": 512,
                                    "temperature": 1.0,
                                    "upstream_host": "localhost",
                                    "upstream_port": 6724
                                }
                            }
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



=== TEST 5: send request
--- request
POST /anything
{"prompt": "what is 1 + 1"}
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 6: send request with empty body
--- request
POST /anything
--- error_code: 400
--- response_body_chomp
failed to get request body: request body is empty



=== TEST 7: send request with wrong method (GET) should work
--- request
GET /anything
{"prompt": "what is 1 + 1"}
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body eval
qr/\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}/



=== TEST 8: wrong JSON in request body should give error
--- request
GET /anything
{"prompt": "what is 1 + 1"
--- error_code: 400
--- response_body chomp
Expected comma or object end but found T_END at character 27



=== TEST 9: content-type should be JSON
--- request
POST /anything
prompt%3Dwhat%2520is%25201%2520%252B%25201
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400
--- response_body chomp
unsupported content-type: application/x-www-form-urlencoded



=== TEST 10: request schema validity check
--- request
POST /anything
{"prompt-is-missing": "what is 1 + 1"}
--- more_headers
Authorization: Bearer token
--- error_code: 400
--- response_body chomp
request format doesn't match schema: property "prompt" is required
