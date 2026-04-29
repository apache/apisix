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

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai_rate_limit;
            default_type 'application/json';
            listen 6726;
            location / {
              content_by_lua_block {
                ngx.status = 429
                ngx.say([[{ "error": {"message":"rate limit exceeded"}}]])
                return
              }
            }
        }
        server {
            server_name openai_internal_error;
            default_type 'application/json';
            listen 6727;
            location / {
              content_by_lua_block {
                ngx.status = 500
                ngx.say([[{ "error": {"message":"internal server error"}}]])
                return
              }
            }
        }
        server {
            server_name openai_internal_error;
            default_type 'application/json';
            listen 6728;
            location / {
              content_by_lua_block {
                ngx.status = 503
                ngx.say([[{ "error": {"message":"service unavailable"}}]])
                return
              }
            }
        }
        server {
            server_name healthcheck;
            default_type 'application/json';
            listen 6729;
            location /status_200 {
                return 200 "OK";
            }
            location /status_500 {
                return 500 "Internal Server Error";
            }
        }
        server {
            server_name openai;
            listen 6724;

            default_type 'application/json';

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

                        ngx.status = 200
                        ngx.print("openai")
                        return
                    end


                    ngx.status = 503
                    ngx.say("reached the end of the test suite")
                }
            }

            location /chat/completions {
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
                        body, err = json.decode(body)

                        if not body.messages or #body.messages < 1 then
                            ngx.status = 400
                            ngx.say([[{ "error": "bad request"}]])
                            return
                        end

                        ngx.status = 200
                        ngx.print("deepseek")
                        return
                    end


                    ngx.status = 503
                    ngx.say("reached the end of the test suite")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set route with roundrobin balancer, weight 4 and 1
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
                                    "name": "openai",
                                    "provider": "openai",
                                    "weight": 4,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724"
                                    }
                                },
                                {
                                    "name": "deepseek",
                                    "provider": "deepseek",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "deepseek-chat",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/chat/completions"
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



=== TEST 2: test
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"

            local restab = {}

            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "POST", body = body})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end

            table.sort(restab)
            ngx.log(ngx.WARN, "test picked instances: ", table.concat(restab, "."))

        }
    }
--- request
GET /t
--- error_log
deepseek.deepseek.openai.openai.openai.openai.openai.openai.openai.openai



=== TEST 3: set route with chash balancer, weight 4 and 1
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
                            "balancer": {
                                "algorithm": "chash",
                                "hash_on": "vars",
                                "key": "query_string"
                            },
                            "instances": [
                                {
                                    "name": "openai",
                                    "provider": "openai",
                                    "weight": 4,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724"
                                    }
                                },
                                {
                                    "name": "deepseek",
                                    "provider": "deepseek",
                                    "weight": 1,
                                    "auth": {"header": {"Authorization": "Bearer token"}},
                                    "options": {"model": "deepseek-chat","max_tokens": 512,"temperature": 1.0},
                                    "override": {"endpoint": "http://localhost:6724/chat/completions"}
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



=== TEST 4: test
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"

            local restab = {}

            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end

            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end

            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end

        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
distribution: deepseek: 2
distribution: openai: 8



=== TEST 5: set route with fallback_strategy with 500 response code openai.
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
                            "fallback_strategy": ["http_5xx"],
                            "balancer": {
                                "algorithm": "chash",
                                "hash_on": "vars",
                                "key": "query_string"
                            },
                            "instances": [
                                {
                                    "name": "openai",
                                    "provider": "openai",
                                    "weight": 4,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6727"
                                    }
                                },
                                {
                                    "name": "deepseek",
                                    "provider": "deepseek",
                                    "weight": 1,
                                    "auth": {"header": {"Authorization": "Bearer token"}},
                                    "options": {"model": "deepseek-chat","max_tokens": 512,"temperature": 1.0},"override": {"endpoint": "http://localhost:6724/chat/completions"}}
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



=== TEST 6: test all requests success with fallback deepseek
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"
            local restab = {}
            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end
            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end
            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end
        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
distribution: deepseek: 10



=== TEST 7: set route with fallback_strategy with too many requests openai.
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
                            "fallback_strategy": ["http_429"],
                            "balancer": {
                                "algorithm": "chash",
                                "hash_on": "vars",
                                "key": "query_string"
                            },
                            "instances": [
                                {
                                    "name": "openai",
                                    "provider": "openai",
                                    "weight": 4,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6726"
                                    }
                                },
                                {"name":"deepseek","provider":"deepseek","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"deepseek-chat","max_tokens":512,"temperature":1.0},"override":{"endpoint":"http://localhost:6724/chat/completions"}}
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



=== TEST 8: test all requests success with fallback deepseek
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"
            local restab = {}
            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end
            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end
            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end
        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
distribution: deepseek: 10



=== TEST 9: set route with fallback_strategy with unreachable openai.
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
                            "fallback_strategy": ["http_5xx"],
                            "balancer": {
                                "algorithm": "chash",
                                "hash_on": "vars",
                                "key": "query_string"
                            },
                            "instances": [
                                {
                                    "name": "openai",
                                    "provider": "openai",
                                    "weight": 4,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6725"
                                    }
                                },
                                {"name":"deepseek","provider":"deepseek","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"deepseek-chat","max_tokens":512,"temperature":1.0},"override":{"endpoint":"http://localhost:6724/chat/completions"}}
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



=== TEST 10: test all requests success with fallback deepseek
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"
            local restab = {}
            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end
            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end
            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end
        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
distribution: deepseek: 10



=== TEST 11: set route with fallback_strategy with service unavailable openai.
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
                            "fallback_strategy": ["http_5xx"],
                            "balancer": {
                                "algorithm": "chash",
                                "hash_on": "vars",
                                "key": "query_string"
                            },
                            "instances": [
                                {
                                    "name": "openai",
                                    "provider": "openai",
                                    "weight": 4,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4",
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6728"
                                    }
                                },
                                {"name":"deepseek","provider":"deepseek","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"deepseek-chat","max_tokens":512,"temperature":1.0},"override":{"endpoint":"http://localhost:6724/chat/completions"}}
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



=== TEST 12: test all requests success with fallback deepseek
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"
            local restab = {}
            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end
            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end
            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end
        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
distribution: deepseek: 10



=== TEST 13: set route with fallback_strategy with service unavailable openai having high priority.
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
                            "balancer": {
                                "algorithm": "roundrobin",
                                "hash_on": "vars"
                            },
                            "fallback_strategy": [
                                "http_429",
                                "http_5xx"
                            ],
                            "instances": [
                               {"auth":{"header":{"Authorization":"Bearer token"}},"name":"mock-429","override":{"endpoint":"http://localhost:6726"},"priority":10,"provider":"openai-compatible","weight":10},{"auth":{"header":{"Authorization":"Bearer token"}},"name":"mock-500","override":{"endpoint":"http://localhost:6727"},"priority":0,"provider":"openai-compatible","weight":10},{"auth":{"header":{"Authorization":"Bearer token"}},"name":"mock-200","override":{"endpoint":"http://localhost:6724/chat/completions"},"priority":0,"provider":"openai-compatible","weight":1}
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



=== TEST 14: test all requests success with fallback deepseek
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"
            local restab = {}
            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end
            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end
            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end
        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
distribution: deepseek: 10



=== TEST 15: set route with fallback_strategy with only service unavailable and 429.
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
                            "balancer": {
                                "algorithm": "roundrobin",
                                "hash_on": "vars"
                            },
                            "fallback_strategy": [
                                "http_429",
                                "http_5xx"
                            ],
                            "instances": [
                                {
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "name": "mock-429",
                                    "override": {
                                        "endpoint":  "http://localhost:6726"
                                    },
                                    "priority": 10,
                                    "provider": "openai-compatible",
                                    "weight": 10
                                    },
                                {
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "name": "mock-500",
                                    "override": {
                                        "endpoint": "http://localhost:6727"
                                    },
                                    "priority": 0,
                                    "provider": "openai-compatible",
                                    "weight": 10
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



=== TEST 16: test all requests success with fallback deepseek should return 502
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"
            local restab = {}
            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.status)
            end
            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end
            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end
        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
distribution: 502: 10



=== TEST 17: set route with 2 instances with checks
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local request_body = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        instances = {
                          {
                            name = "openai",
                            provider = "openai",
                            weight = 1,
                            auth = {
                                header = {Authorization = "Bearer token" }
                            },
                            options = {
                                model = "gpt-4",
                                max_tokens = 512,
                                temperature = 1
                            },
                            override = { endpoint = "http://localhost:6724" },
                            checks = {
                                active = {
                                    type = "http", host = "localhost", port = 6729, http_path = "/status_200",
                                    healthy = { interval = 1, successes = 1 },
                                    unhealthy = { interval = 1, http_failures = 1 }
                                }
                            }
                          },
                          {
                            name = "deepseek",
                            provider = "deepseek",
                            weight = 1,
                            auth = {
                                header = { Authorization = "Bearer token" }
                            },
                            options = {
                              model = "deepseek-chat",
                              max_tokens = 512,
                              temperature = 1
                            },
                            override = { endpoint = "http://localhost:6724/chat/completions" },
                            checks = {
                                active = {
                                    type = "http", host = "localhost", port = 6729, http_path = "/status_500",
                                    healthy = { interval = 1, successes = 1 },
                                    unhealthy = { interval = 1, http_failures = 1 }
                                }
                            }
                          }
                        },
                        ssl_verify = false
                    }
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(request_body)
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 18: request route and all requests are proxied to openai because deepseek is not healthy
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"

            -- request once before counting
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.sleep(2.2)

            local restab = {}

            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end

            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end

            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end

        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
distribution: openai: 10



=== TEST 19: switch on disable_upstream_healthcheck
--- yaml_config
apisix:
    disable_upstream_healthcheck: true
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"

            -- request once before counting
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.sleep(2.2)

            local restab = {}

            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end

            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end

            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end

        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
disabled upstream healthcheck
distribution: deepseek: 5
distribution: openai: 5



=== TEST 20: set route with only one instance and configure it with http_5xx fallback_strategy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local request_body = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = {"http_5xx"},
                        instances = {
                          {
                            name = "deepseek",
                            provider = "deepseek",
                            auth = {
                                header = {Authorization = "Bearer token" }
                            },
                            weight = 1,
                            override = { endpoint = "http://localhost:6727" }
                          }
                        },
                        ssl_verify = false
                    }
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(request_body)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Host: openai_internal_error
--- error_code: 500
--- no_error_log
[error]



=== TEST 22: construct_upstream works without _dns_value (compute_endpoint_node fallback)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy-multi")
            local instance = {
                name = "test-openai",
                provider = "openai",
                weight = 1,
                override = {
                    endpoint = "http://localhost:6724"
                },
                auth = {
                    header = { Authorization = "Bearer token" }
                },
                checks = {
                    active = {
                        type = "http",
                        host = "localhost",
                        port = 6729,
                        http_path = "/status_200",
                        healthy = { interval = 1, successes = 1 },
                        unhealthy = { interval = 1, http_failures = 1 }
                    }
                }
            }
            -- _dns_value is nil, simulating timer context after config update
            local upstream, err = plugin.construct_upstream(instance)
            if not upstream then
                ngx.say("FAIL: " .. (err or "unknown error"))
                return
            end

            ngx.say("nodes: " .. #upstream.nodes)
            ngx.say("host: " .. upstream.nodes[1].host)
            ngx.say("port: " .. upstream.nodes[1].port)
            ngx.say("scheme: " .. upstream.nodes[1].scheme)
            ngx.say("has_checks: " .. tostring(upstream.checks ~= nil))
        }
    }
--- response_body
nodes: 1
host: 127.0.0.1
port: 6724
scheme: http
has_checks: true
--- no_error_log
[error]



=== TEST 23: construct_upstream uses provider defaults when no override and no _dns_value
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy-multi")
            local instance = {
                name = "test-openai-default",
                provider = "openai",
                weight = 1,
                auth = {
                    header = { Authorization = "Bearer token" }
                },
            }
            -- No override.endpoint and no _dns_value
            local upstream, err = plugin.construct_upstream(instance)
            if not upstream then
                ngx.say("FAIL: " .. (err or "unknown error"))
                return
            end

            ngx.say("nodes: " .. #upstream.nodes)
            ngx.say("host: " .. upstream.nodes[1].host)
            ngx.say("port: " .. upstream.nodes[1].port)
            ngx.say("scheme: " .. upstream.nodes[1].scheme)
        }
    }
--- response_body_like eval
qr/^nodes: 1\shost: \d+\.\d+\.\d+\.\d+\sport: 443\sscheme: https$/m
--- no_error_log
[error]



=== TEST 24: construct_upstream prefers _dns_value over compute_endpoint_node
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy-multi")
            local instance = {
                name = "test-openai-dns",
                provider = "openai",
                weight = 1,
                override = {
                    endpoint = "http://localhost:6724"
                },
                _dns_value = {
                    host = "10.0.0.1",
                    port = 8080,
                    scheme = "http",
                },
                _nodes_ver = 3,
            }
            local upstream, err = plugin.construct_upstream(instance)
            if not upstream then
                ngx.say("FAIL: " .. (err or "unknown error"))
                return
            end

            -- Should use _dns_value, not the override endpoint
            ngx.say("host: " .. upstream.nodes[1].host)
            ngx.say("port: " .. upstream.nodes[1].port)
            ngx.say("nodes_ver: " .. upstream._nodes_ver)
        }
    }
--- response_body
host: 10.0.0.1
port: 8080
nodes_ver: 3
--- no_error_log
[error]



=== TEST 25: set route with healthcheck for config update test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local request_body = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        instances = {
                          {
                            name = "openai",
                            provider = "openai",
                            weight = 1,
                            auth = {
                                header = {Authorization = "Bearer token" }
                            },
                            options = {
                                model = "gpt-4",
                                max_tokens = 512,
                                temperature = 1
                            },
                            override = { endpoint = "http://localhost:6724" },
                            checks = {
                                active = {
                                    type = "http", host = "localhost", port = 6729, http_path = "/status_200",
                                    healthy = { interval = 1, successes = 1 },
                                    unhealthy = { interval = 1, http_failures = 1 }
                                }
                            }
                          }
                        },
                        ssl_verify = false
                    }
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(request_body)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 26: healthcheck does not crash after route config update
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/anything"

            -- Step 1: Send request to activate healthcheck
            local httpc = http.new()
            local chat_body = [[{"messages":[{"role":"user","content":"hi"}]}]]
            local res, err = httpc:request_uri(uri, {method = "POST", body = chat_body})
            if not res then
                ngx.say("first request failed: " .. err)
                return
            end
            ngx.say("first request: " .. res.status)

            -- Step 2: Wait for healthcheck checker to be created
            ngx.sleep(2.5)

            -- Step 3: Update route config (triggers config refresh, new object without _dns_value)
            local request_body = {
                uri = "/anything",
                plugins = {
                    ["ai-proxy-multi"] = {
                        instances = {
                          {
                            name = "openai",
                            provider = "openai",
                            weight = 2,
                            auth = {
                                header = {Authorization = "Bearer token" }
                            },
                            options = {
                                model = "gpt-4",
                                max_tokens = 1024,
                                temperature = 1
                            },
                            override = { endpoint = "http://localhost:6724" },
                            checks = {
                                active = {
                                    type = "http", host = "localhost", port = 6729, http_path = "/status_200",
                                    healthy = { interval = 1, successes = 1 },
                                    unhealthy = { interval = 1, http_failures = 1 }
                                }
                            }
                          }
                        },
                        ssl_verify = false
                    }
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(request_body)
            )
            if code >= 300 then
                ngx.say("update failed: " .. code)
                return
            end
            ngx.say("route updated: " .. code)

            -- Step 4: Wait for healthcheck timer to process the new config
            ngx.sleep(3)

            -- Step 5: Verify healthcheck still works with another request
            local httpc2 = http.new()
            local res2, err2 = httpc2:request_uri(uri, {method = "POST", body = chat_body})
            if not res2 then
                ngx.say("second request failed: " .. err2)
                return
            end
            ngx.say("second request: " .. res2.status)
        }
    }
--- request
GET /t
--- timeout: 15
--- response_body
first request: 200
route updated: 200
second request: 200
--- no_error_log
attempt to index local 'upstream'
unable to construct upstream
