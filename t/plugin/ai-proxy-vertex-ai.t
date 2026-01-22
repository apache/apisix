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

log_level("debug");
repeat_each(1);
no_long_string();
no_root_location();


my $resp_file = 't/assets/ai-proxy-response.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $resp = do { local $/; <$fh> };
close($fh);


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $extra_init_worker_by_lua = <<_EOC_;
    local gcp_accesstoken = require "apisix.utils.google-cloud-oauth"
    local ttl = 0
    gcp_accesstoken.refresh_access_token = function(self)
        ngx.log(ngx.NOTICE, "[test] mocked gcp_accesstoken called")  
        ttl = ttl + 5
        self.access_token_ttl = ttl
        self.access_token = "ya29.c.Kp8B..."
    end
_EOC_

    $block->set_value("extra_init_worker_by_lua", $extra_init_worker_by_lua);


    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 6724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    local json = require("toolkit.json")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    if body and body.instances then
                        local vertex_response = {
                            ["predictions"] = {
                                {
                                    ["embeddings"] = {
                                        ["statistics"] = {
                                            ["token_count"] = 7
                                        },
                                        ["values"] = {
                                            0.0123,
                                            -0.0456,
                                            0.0789,
                                            0.0012
                                        }
                                    }
                                },
                            }
                        }
                        local body = json.encode(vertex_response)
                        ngx.status = 200
                        ngx.say(body)
                        return
                    end

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

                    if header_auth ~= "Bearer token" and query_auth ~= "apikey" and header_auth ~= "Bearer ya29.c.Kp8B..." then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    if header_auth == "Bearer token" or query_auth == "apikey" or header_auth == "Bearer ya29.c.Kp8B..." then
                        if header_auth == "Bearer ya29.c.Kp8B..." then
                            ngx.log(ngx.NOTICE, "[test] GCP service account auth works")
                        end
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

            location ~ ^/status.* {
                content_by_lua_block {
                    local test_dict = ngx.shared["test"]
                    local uri = ngx.var.uri
                    local total_key = uri .. "#total"
                    local count_key = uri .. "#count"
                    local total = test_dict:get(total_key)
                    if not total then
                        return
                    end

                    local count = test_dict:incr(count_key, 1, 0)
                    ngx.log(ngx.INFO, "uri: ", uri, " total: ", total, " count: ", count)
                    if count < total then
                        return
                    end
                    ngx.status = 500
                    ngx.say("error")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set route with right auth header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "vertex-ai",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false
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



=== TEST 2: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body eval
qr/"content":"1 \+ 1 = 2\."/



=== TEST 3: request embeddings, check values field in response
--- request
POST /anything
{"input": "Your text string goes here"}
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body eval
qr/"embedding":\[0.0123,-0.0456,0.0789,0.0012\]/



=== TEST 4: request embeddings, check token_count field in response
--- request
POST /anything
{"input": "Your text string goes here"}
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body eval
qr/"total_tokens":7/



=== TEST 5: set route with right auth gcp service account
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "vertex-ai",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "auth": {
                                        "gcp": { "max_ttl": 8 }
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false
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
--- error_code: 200
--- error_log
[test] GCP service account auth works
--- response_body eval
qr/"content":"1 \+ 1 = 2\."/



=== TEST 7: check gcp access token caching works
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local send_request = function()
                local code, _, body = t("/anything",
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    nil,
                    {
                        ["Content-Type"] = "application/json",
                    }
                )
                assert(code == 200, "request should be successful")
                return body
            end
            for i = 1, 6 do
                send_request()
            end
            
            ngx.sleep(5.5)
            send_request()

            ngx.say("passed")
        }
    }
--- timeout: 7
--- response_body
passed
--- error_log
[test] mocked gcp_accesstoken called
[test] mocked gcp_accesstoken called
set gcp access token in cache with ttl: 5
set gcp access token in cache with ttl: 8



=== TEST 8: set route with multiple instances and gcp service account
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "vertex-ai-one",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "auth": {
                                        "gcp": {}
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                },
                                {
                                    "name": "vertex-ai-multi",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "auth": {
                                        "gcp": {}
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false
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



=== TEST 9: check gcp access token caching works
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local send_request = function()
                local code, _, body = t("/anything",
                    ngx.HTTP_POST,
                    [[{
                        "messages": [
                            { "role": "system", "content": "You are a mathematician" },
                            { "role": "user", "content": "What is 1+1?" }
                        ]
                    }]],
                    nil,
                    {
                        ["Content-Type"] = "application/json",
                    }
                )
                assert(code == 200, "request should be successful")
                return body
            end
            for i = 1, 12 do
                send_request()
            end

            ngx.say("passed")
        }
    }
--- timeout: 7
--- response_body
passed
--- error_log
#vertex-ai-one
#vertex-ai-multi



=== TEST 10: set ai-proxy-multi with health checks
--- config
    location /t {
        content_by_lua_block {
            local checks = [[
            "checks": {
                "active": {
                    "timeout": 5,
                    "http_path": "/status/gpt4",
                    "host": "foo.com",
                    "healthy": {
                        "interval": 1,
                        "successes": 1
                    },
                    "unhealthy": {
                        "interval": 1,
                        "http_failures": 1
                    },
                    "req_headers": ["User-Agent: curl/7.29.0"]
                }
            }]]
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 string.format([[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "vertex-ai",
                                    "provider": "vertex-ai",
                                    "weight": 1,
                                    "priority": 2,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gemini-2.0-flash",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/v1/chat/completions"
                                    },
                                    %s
                                },
                                {
                                    "name": "openai-gpt3",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-3"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    }
                }]], checks)
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: check health check works
--- wait: 5
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
--- error_code: 200
--- response_body eval
qr/"content":"1 \+ 1 = 2\."/
--- error_log
creating healthchecker for upstream
request head: GET /status/gpt4
