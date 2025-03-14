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


            location /check_extra_options {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    ngx.req.read_body()
                    local body = ngx.req.get_body_data()
                    local request_data = json.decode(body)

                    if request_data.extra_option ~= "extra option" then
                        ngx.status = 400
                        ngx.say("extra option not match")
                        return
                    end

                    local response = {
                        choices = {
                            {
                                message = {
                                    content = request_data.messages[1].content .. ' ' .. request_data.messages[2].content
                                }
                            }
                        }
                        }
                    local json = require("cjson.safe")
                    local json_response = json.encode(response)
                    ngx.say(json_response)
                }
            }

            location /test/params/in/overridden/endpoint {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    local core = require("apisix.core")

                    local query_auth = ngx.req.get_uri_args()["api_key"]
                    ngx.log(ngx.INFO, "found query params: ", core.json.stably_encode(ngx.req.get_uri_args()))

                    if query_auth ~= "apikey" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    ngx.status = 200
                    ngx.say("passed")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: check plugin options send to llm service correctly
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-request-rewrite": {
                            "prompt": "some prompt to test",
                            "auth": {
                                "query": {
                                    "api_key": "apikey"
                                }
                            },
                            "provider": "openai",
                            "override": {
                                "endpoint": "http://localhost:6724/check_extra_options"
                            },
                            "ssl_verify": false,
                            "options": {
                                "model": "check_options_model",
                                "extra_option": "extra option"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "httpbin.org:80": 1
                        }
                    }
                }]]
            )


            local code, body, actual_body = t("/anything",
                ngx.HTTP_POST,
                "some random content",
                nil,
                {
                    ["Content-Type"] = "text/plain",
                }
            )

            if code == 200 then
                ngx.say('passed')
                return
            end
        }
    }
--- response_body
passed



=== TEST 2: openai-compatible provider should use with override.endpoint
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-request-rewrite")
            local ok, err = plugin.check_schema({
                prompt = "some prompt",
                provider = "openai-compatible",
                auth = {
                    header = {
                        Authorization =  "Bearer token"
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
override.endpoint is required for openai-compatible provider



=== TEST 3: query params in override.endpoint should be sent to LLM
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
                                "query": {
                                    "api_key": "apikey"
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
                                "endpoint": "http://localhost:6724/test/params/in/overridden/endpoint?some_query=yes"
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
            ngx.print(body)
        }
    }
--- response_body
passed
