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

            location /v1/chat/completions {
                content_by_lua_block {

                   ngx.req.read_body()
                   local body = ngx.req.get_body_data()

                   local json = require("cjson.safe")
                   local request_data = json.decode(body)
                    local header_auth = ngx.req.get_headers()["authorization"]
                    local query_auth = ngx.req.get_uri_args()["apikey"]

                    if header_auth ~= "Bearer token" then
                    ngx.log(ngx.ERR, "header_auth: " .. header_auth)
                        ngx.status = 401
                        ngx.say("Unauthorized")
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

            location /random {
                content_by_lua_block {

                   local response = {
                        choices = {
                            {
                                message = {
                                    content = 'return by random endpoint'
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

# === TEST 1: minimal viable configuration
# --- config
#     location /t {
#         content_by_lua_block {
#             local plugin = require("apisix.plugins.ai-request-rewrite")
#             local ok, err = plugin.check_schema({
#                 prompt = "some prompt",
#                 provider = "openai",
#                 auth = {
#                     header = {
#                         "Authorization": "Bearer token"
#                     }
#                 }
#             })

#             if not ok then
#                 ngx.print(err)
#             else
#                 ngx.say("passed")
#             end
#         }
#     }
# --- response_body
# passed



# === TEST 2: missing prompt field should not pass
# --- config
#     location /t {
#         content_by_lua_block {
#             local plugin = require("apisix.plugins.ai-request-rewrite")
#             local ok, err = plugin.check_schema({
#                 provider = "openai",
#                 auth = {
#                     header = {
#                         "Authorization": "Bearer token"
#                     }
#                 }
#             })

#             if not ok then
#                 ngx.say(err)
#             else
#                 ngx.say("passed")
#             end
#         }
#     }
# --- response_body
# property "prompt" is required




# === TEST 3: missing auth field should not pass
# --- config
#     location /t {
#         content_by_lua_block {
#             local plugin = require("apisix.plugins.ai-request-rewrite")
#             local ok, err = plugin.check_schema({
#                 prompt = "some prompt",
#                 provider = "openai",
#             })

#             if not ok then
#                 ngx.say(err)
#             else
#                 ngx.say("passed")
#             end
#         }
#     }
# --- response_body
# property "auth" is required



# === TEST 4: missing provider field should not pass
# --- config
#     location /t {
#         content_by_lua_block {
#             local plugin = require("apisix.plugins.ai-request-rewrite")
#             local ok, err = plugin.check_schema({
#                 prompt = "some prompt",
#                 auth = {
#                     header = {
#                         "Authorization": "Bearer token"
#                     }
#                 }
#             })

#             if not ok then
#                 ngx.say(err)
#             else
#                 ngx.say("passed")
#             end
#         }
#     }
# --- response_body
# property "provider" is required



# === TEST 5: provider must be one of: deepseek, openai, openai-compatible
# --- config
#     location /t {
#         content_by_lua_block {
#             local plugin = require("apisix.plugins.ai-request-rewrite")
#             local ok, err = plugin.check_schema({
#                 prompt = "some prompt",
#                 provider = "invalid-provider",
#                 auth = {
#                     header = {
#                         "Authorization": "Bearer token"
#                     }
#                 }
#             })

#             if not ok then
#                 ngx.say(err)
#             else
#                 ngx.say("passed")
#             end
#         }
#     }
# --- response_body
# property "provider" validation failed: matches none of the enum values




# === TEST 6: provider deepseek 
# --- config
#     location /t {
#         content_by_lua_block {
#             local plugin = require("apisix.plugins.ai-request-rewrite")
#             local ok, err = plugin.check_schema({ 
#                 prompt = "some prompt",
#                 provider = "deepseek",
#                 auth = {
#                     header = {
#                         "Authorization": "Bearer token"
#                     }
#                 }
#             })

#             if not ok then
#                 ngx.say(err)
#             else
#                 ngx.say("passed")
#             end
#         }
#     }
# --- response_body
# passed



# === TEST 7: provider openai-compatible 
# --- config
#     location /t {
#         content_by_lua_block {
#             local plugin = require("apisix.plugins.ai-request-rewrite")
#             local ok, err = plugin.check_schema({ 
#                 prompt = "some prompt",
#                 provider = "openai-compatible",
#                 auth = {
#                     header = {
#                         "Authorization": "Bearer token"
#                     }
#                 }
#             })

#             if not ok then
#                 ngx.say(err)
#             else
#                 ngx.say("passed")
#             end
#         }
#     }
# --- response_body
# passed



# === TEST 8: override endpoint works
# --- config
#     location /t {
#         content_by_lua_block {
#             local t = require("lib.test_admin").test
#             local code, body = t('/apisix/admin/routes/1',
#                  ngx.HTTP_PUT,
#                  [[{
#                     "uri": "/anything",
#                     "plugins": {
#                         "ai-request-rewrite": {
#                             "prompt": "some prompt",
#                             "provider": "openai",
#                             "auth": {
#                                 "header": {
#                                     "Authorization": "Bearer token"
#                                 }
#                             },
#                             "override": {
#                                 "endpoint": "http://localhost:6724/random"
#                             },
#                             "ssl_verify": false
#                         }
#                     },
#                     "upstream": {
#                         "type": "roundrobin",
#                         "nodes": {
#                             "httpbin.org:80": 1
#                         }
#                     }
#                 }]]
#             )
#             if code >= 300 then
#                 ngx.status = code
#                 ngx.say(body)
#                 return
#             end


#             local code, body, actual_body = t("/anything",
#                 ngx.HTTP_POST,
#                 "some random content",
#                 nil,
#                 {
#                     ["Content-Type"] = "text/plain",
#                 }
#             )
#             local json = require("cjson.safe")
#             local response_data = json.decode(actual_body)

#             if response_data.data == 'return by random endpoint' then
#                 ngx.say("passed")
#             else
#                 ngx.say(actual_body)
#             end
#         }
#     }
# --- response_body
# passed



=== TEST 9: set route with wrong auth header
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
                            "prompt": "some prompt",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer wrong-token"
                                }
                            },
                            "provider": "openai",
                            "override": {
                                "endpoint": "http://localhost:6724"
                            },
                            "ssl_verify": false
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
            if code == 500 then
                ngx.say('passed')
                return
            end
        }
    }

--- error_log
llm service returned status: 401
--- response_body
passed

