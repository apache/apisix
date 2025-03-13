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
