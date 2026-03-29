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
no_shuffle();
workers(4);
worker_connections(256);

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->timeout) {
        $block->set_value("timeout", "10");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 16724;

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
                    if header_auth ~= "Bearer token" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    if not body.messages or #body.messages < 1 then
                        ngx.status = 400
                        ngx.say([[{ "error": "bad request"}]])
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
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set route with Redis policy in multi-worker suite
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_all()

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
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
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60,
                            "policy": "redis",
                            "redis_host": "127.0.0.1"
                        },
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions": [
                                "return function() ngx.header['X-Test-Worker-Id'] = tostring(ngx.worker.id()) end"
                            ]
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



=== TEST 2: reject the 4th request with Redis policy across multiple workers
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ai"
            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            local codes = {}
            local remainings = {}
            local workers = {}

            for i = 1, 20 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = body,
                    keepalive = false,
                    headers = {
                        Authorization = "Bearer token",
                        ["Content-Type"] = "application/json"
                    }
                })
                if not res then
                    ngx.say("failed: ", err)
                    return
                end

                local worker_id = res.headers["X-Test-Worker-Id"]
                if worker_id then
                    workers[worker_id] = true
                end

                if i <= 4 then
                    codes[i] = res.status
                    remainings[i] = res.headers["X-AI-RateLimit-Remaining-ai-proxy-openai"]
                end
            end

            local worker_count = 0
            for _ in pairs(workers) do
                worker_count = worker_count + 1
            end

            ngx.say("codes: ", table.concat(codes, ","))
            ngx.say("remaining: ", table.concat(remainings, ","))
            ngx.say("workers: ", worker_count)
        }
    }
--- response_body_like eval
qr/codes: 200,200,200,503\nremaining: 29,19,9,0\nworkers: [2-9]/



=== TEST 3: set rejected_code to 403 with Redis policy in multi-worker suite
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_all()

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
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
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60,
                            "rejected_code": 403,
                            "rejected_msg": "rate limit exceeded",
                            "policy": "redis",
                            "redis_host": "127.0.0.1"
                        },
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions": [
                                "return function() ngx.header['X-Test-Worker-Id'] = tostring(ngx.worker.id()) end"
                            ]
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



=== TEST 4: check code and message with Redis across multiple workers
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ai"
            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            local codes = {}
            local response_bodies = {}
            local workers = {}

            for i = 1, 20 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = body,
                    keepalive = false,
                    headers = {
                        Authorization = "Bearer token",
                        ["Content-Type"] = "application/json"
                    }
                })
                if not res then
                    ngx.say("failed: ", err)
                    return
                end

                local worker_id = res.headers["X-Test-Worker-Id"]
                if worker_id then
                    workers[worker_id] = true
                end

                if i <= 4 then
                    codes[i] = res.status
                    response_bodies[i] = res.body:gsub("%s+$", "")
                end
            end

            local worker_count = 0
            for _ in pairs(workers) do
                worker_count = worker_count + 1
            end

            ngx.say("codes: ", table.concat(codes, ","))
            for i = 1, 4 do
                ngx.say("body ", i, ": ", response_bodies[i])
            end
            ngx.say("workers: ", worker_count)
        }
    }
--- response_body_like eval
qr/codes: 200,200,200,403\nbody 1: (?s:.*?)\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}(?s:.*?)\nbody 2: (?s:.*?)\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}(?s:.*?)\nbody 3: (?s:.*?)\{ "content": "1 \+ 1 = 2\.", "role": "assistant" \}(?s:.*?)\nbody 4: \{"error_msg":"rate limit exceeded"\}\nworkers: [2-9]/



=== TEST 5: set route with Redis Cluster policy in multi-worker suite
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_all()

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
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
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60,
                            "policy": "redis-cluster",
                            "redis_cluster_nodes": [
                                "127.0.0.1:5000",
                                "127.0.0.1:5002"
                            ],
                            "redis_cluster_name": "redis-cluster-1"
                        },
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions": [
                                "return function() ngx.header['X-Test-Worker-Id'] = tostring(ngx.worker.id()) end"
                            ]
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



=== TEST 6: reject request with Redis Cluster policy across multiple workers
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ai"
            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            local codes = {}
            local remainings = {}
            local workers = {}

            for i = 1, 20 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body = body,
                    keepalive = false,
                    headers = {
                        Authorization = "Bearer token",
                        ["Content-Type"] = "application/json"
                    }
                })
                if not res then
                    ngx.say("failed: ", err)
                    return
                end

                local worker_id = res.headers["X-Test-Worker-Id"]
                if worker_id then
                    workers[worker_id] = true
                end

                if i <= 4 then
                    codes[i] = res.status
                    remainings[i] = res.headers["X-AI-RateLimit-Remaining-ai-proxy-openai"]
                end
            end

            local worker_count = 0
            for _ in pairs(workers) do
                worker_count = worker_count + 1
            end

            ngx.say("codes: ", table.concat(codes, ","))
            ngx.say("remaining: ", table.concat(remainings, ","))
            ngx.say("workers: ", worker_count)
        }
    }
--- response_body_like eval
qr/codes: 200,200,200,503\nremaining: 29,19,9,0\nworkers: [2-9]/
