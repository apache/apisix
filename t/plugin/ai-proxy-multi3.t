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
            listen 16724;

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
                        ngx.say(string.format([[
{
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "message": { "content": "1 + 1 = 2.", "role": "assistant" }
    }
  ],
  "created": 1723780938,
  "id": "chatcmpl-9wiSIg5LYrrpxwsr2PubSQnbtod1P",
  "model": "%s",
  "object": "chat.completion",
  "system_fingerprint": "fp_abc28019ad",
  "usage": { "completion_tokens": 5, "prompt_tokens": 8, "total_tokens": 10 }
}
                        ]], body.model))
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

            location /error {
                content_by_lua_block {
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

=== TEST 1: set route, only one instance has checker
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": "instance_health_and_rate_limiting",
                            "instances": [
                                {
                                    "name": "openai-gpt4",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:16724"
                                    },
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
                                    }
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
                                        "endpoint": "http://localhost:16724"
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



=== TEST 2: once instance changes from unhealthy to healthy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local test_dict = ngx.shared["test"]

            local send_request = function()
                local code, _, body = t("/ai",
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
                assert(code == 200, "request should be successful")
                return body
            end

            -- set the instance to unhealthy
            test_dict:set("/status/gpt4#total", 0)
            -- trigger the health check
            send_request()
            ngx.sleep(1)

            local instances_count = {
                ["gpt-4"] = 0,
                ["gpt-3"] = 0,
            }
            for i = 1, 10 do
                local resp = send_request()
                if core.string.find(resp, "gpt-4") then
                    instances_count["gpt-4"] = instances_count["gpt-4"] + 1
                else
                    instances_count["gpt-3"] = instances_count["gpt-3"] + 1
                end
            end

            ngx.log(ngx.INFO, "instances_count test:", core.json.delay_encode(instances_count))
            assert(instances_count["gpt-4"] <= 2, "gpt-4 should be unhealthy")
            assert(instances_count["gpt-3"] >= 8, "gpt-3 should be healthy")

            -- set the instance to healthy
            test_dict:set("/status/gpt4#total", 30)
            ngx.sleep(1)

            local instances_count = {
                ["gpt-4"] = 0,
                ["gpt-3"] = 0,
            }
            for i = 1, 10 do
                local resp = send_request()
                if core.string.find(resp, "gpt-4") then
                    instances_count["gpt-4"] = instances_count["gpt-4"] + 1
                else
                    instances_count["gpt-3"] = instances_count["gpt-3"] + 1
                end
            end
            ngx.log(ngx.INFO, "instances_count test:", core.json.delay_encode(instances_count))

            local v = instances_count["gpt-4"] - instances_count["gpt-3"]
            assert(v <= 2, "difference between gpt-4 and gpt-3 should be less than 2")
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed



=== TEST 3: set service, only one instance has checker
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": "instance_health_and_rate_limiting",
                            "instances": [
                                {
                                    "name": "openai-gpt4",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:16724"
                                    },
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
                                    }
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
                                        "endpoint": "http://localhost:16724"
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



=== TEST 4: set route 1 related to service 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai",
                    "service_id": 1
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



=== TEST 5: instance changes from unhealthy to healthy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local test_dict = ngx.shared["test"]

            local send_request = function()
                local code, _, body = t("/ai",
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
                assert(code == 200, "request should be successful")
                return body
            end

            -- set the instance to unhealthy
            test_dict:set("/status/gpt4#total", 0)
            -- trigger the health check
            send_request()
            ngx.sleep(1.2)

            local instances_count = {
                ["gpt-4"] = 0,
                ["gpt-3"] = 0,
            }
            for i = 1, 10 do
                local resp = send_request()
                if core.string.find(resp, "gpt-4") then
                    instances_count["gpt-4"] = instances_count["gpt-4"] + 1
                else
                    instances_count["gpt-3"] = instances_count["gpt-3"] + 1
                end
            end

            ngx.log(ngx.INFO, "instances_count test:", core.json.delay_encode(instances_count))
            assert(instances_count["gpt-4"] <= 2, "gpt-4 should be unhealthy")
            assert(instances_count["gpt-3"] >= 8, "gpt-3 should be healthy")

            -- set the instance to healthy
            test_dict:set("/status/gpt4#total", 30)
            ngx.sleep(1.2)

            local instances_count = {
                ["gpt-4"] = 0,
                ["gpt-3"] = 0,
            }
            for i = 1, 10 do
                local resp = send_request()
                if core.string.find(resp, "gpt-4") then
                    instances_count["gpt-4"] = instances_count["gpt-4"] + 1
                else
                    instances_count["gpt-3"] = instances_count["gpt-3"] + 1
                end
            end
            ngx.log(ngx.INFO, "instances_count test:", core.json.delay_encode(instances_count))

            local diff = instances_count["gpt-4"] - instances_count["gpt-3"]
            assert(diff <= 2, "difference between gpt-4 and gpt-3 should be less than 2")
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed



=== TEST 6: set route, two instances have checker
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local checks_tmp = [[
                "checks": {
                    "active": {
                        "timeout": 5,
                        "http_path": "/status/%s",
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
                }
            ]]
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": "instance_health_and_rate_limiting",
                            "instances": [
                                {
                                    "name": "openai-gpt4",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:16724"
                                    },
                                    ]] .. string.format(checks_tmp, "gpt4").. [[
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
                                        "endpoint": "http://localhost:16724"
                                    },
                                    ]] .. string.format(checks_tmp, "gpt3") .. [[
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



=== TEST 7: healthy conversion of two instances
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local test_dict = ngx.shared["test"]

            local send_request = function()
                local code, _, body = t("/ai",
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
                assert(code == 200, "request should be successful")
                return body
            end

            -- set the gpt4 instance to unhealthy
            -- set the gpt3 instance to healthy
            test_dict:set("/status/gpt4#total", 0)
            test_dict:set("/status/gpt3#total", 50)
            -- trigger the health check
            send_request()
            ngx.sleep(1.2)

            local instances_count = {
                ["gpt-4"] = 0,
                ["gpt-3"] = 0,
            }
            for i = 1, 10 do
                local resp = send_request()
                if core.string.find(resp, "gpt-4") then
                    instances_count["gpt-4"] = instances_count["gpt-4"] + 1
                else
                    instances_count["gpt-3"] = instances_count["gpt-3"] + 1
                end
            end

            ngx.log(ngx.INFO, "instances_count test:", core.json.delay_encode(instances_count))
            assert(instances_count["gpt-4"] <= 2, "gpt-4 should be unhealthy")
            assert(instances_count["gpt-3"] >= 8, "gpt-3 should be healthy")

            -- set the gpt4 instance to healthy
            -- set the gpt3 instance to unhealthy
            test_dict:set("/status/gpt4#total", 50)
            test_dict:set("/status/gpt3#total", 0)
            ngx.sleep(1.2)

            local instances_count = {
                ["gpt-4"] = 0,
                ["gpt-3"] = 0,
            }
            for i = 1, 10 do
                local resp = send_request()
                if core.string.find(resp, "gpt-4") then
                    instances_count["gpt-4"] = instances_count["gpt-4"] + 1
                else
                    instances_count["gpt-3"] = instances_count["gpt-3"] + 1
                end
            end
            ngx.log(ngx.INFO, "instances_count test:", core.json.delay_encode(instances_count))

            assert(instances_count["gpt-4"] >= 8, "gpt-4 should be healthy")
            assert(instances_count["gpt-3"] <= 2, "gpt-3 should be unhealthy")
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed



=== TEST 8: set route, two instances have checker
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local checks_tmp = [[
                "checks": {
                    "active": {
                        "timeout": 5,
                        "http_path": "/status/%s",
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
                }
            ]]
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": "instance_health_and_rate_limiting",
                            "instances": [
                                {
                                    "name": "openai-gpt4",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:16724"
                                    },
                                    ]] .. string.format(checks_tmp, "gpt4").. [[
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
                                        "endpoint": "http://localhost:16724"
                                    },
                                    ]] .. string.format(checks_tmp, "gpt3") .. [[
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



=== TEST 9: set route 1 related to service 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/ai",
                    "service_id": 1
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



=== TEST 10: healthy conversion of two instances
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local test_dict = ngx.shared["test"]

            local send_request = function()
                local code, _, body = t("/ai",
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
                assert(code == 200, "request should be successful")
                return body
            end

            -- set the gpt4 instance to unhealthy
            -- set the gpt3 instance to healthy
            test_dict:set("/status/gpt4#total", 0)
            test_dict:set("/status/gpt3#total", 50)
            -- trigger the health check
            send_request()
            ngx.sleep(1.2)

            local instances_count = {
                ["gpt-4"] = 0,
                ["gpt-3"] = 0,
            }
            for i = 1, 10 do
                local resp = send_request()
                if core.string.find(resp, "gpt-4") then
                    instances_count["gpt-4"] = instances_count["gpt-4"] + 1
                else
                    instances_count["gpt-3"] = instances_count["gpt-3"] + 1
                end
            end

            ngx.log(ngx.INFO, "instances_count test:", core.json.delay_encode(instances_count))
            assert(instances_count["gpt-4"] <= 2, "gpt-4 should be unhealthy")
            assert(instances_count["gpt-3"] >= 8, "gpt-3 should be healthy")

            -- set the gpt4 instance to healthy
            -- set the gpt3 instance to unhealthy
            test_dict:set("/status/gpt4#total", 50)
            test_dict:set("/status/gpt3#total", 0)
            ngx.sleep(1.2)

            local instances_count = {
                ["gpt-4"] = 0,
                ["gpt-3"] = 0,
            }
            for i = 1, 10 do
                local resp = send_request()
                if core.string.find(resp, "gpt-4") then
                    instances_count["gpt-4"] = instances_count["gpt-4"] + 1
                else
                    instances_count["gpt-3"] = instances_count["gpt-3"] + 1
                end
            end
            ngx.log(ngx.INFO, "instances_count test:", core.json.delay_encode(instances_count))

            assert(instances_count["gpt-4"] >= 8, "gpt-4 should be healthy")
            assert(instances_count["gpt-3"] <= 2, "gpt-3 should be unhealthy")
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response_body
passed
