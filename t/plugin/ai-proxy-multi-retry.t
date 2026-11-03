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

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - prometheus
  - serverless-post-function
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name fast_internal_error;
            default_type 'application/json';
            listen 6731;
            location / {
              content_by_lua_block {
                ngx.status = 500
                ngx.say([[{ "error": {"message":"fast internal error"}}]])
                return
              }
            }
        }
        server {
            server_name slow_internal_error;
            default_type 'application/json';
            listen 6732;
            location / {
              content_by_lua_block {
                ngx.sleep(0.5)
                ngx.status = 500
                ngx.say([[{ "error": {"message":"slow internal error"}}]])
                return
              }
            }
        }
        # Instances whose API key is rejected or out of quota. Neither status
        # takes the 429/5xx error path, so they exercise fallback_http_statuses.
        server {
            server_name unauthorized_instance;
            default_type 'application/json';
            listen 6735;
            location / {
              content_by_lua_block {
                ngx.status = 401
                ngx.say([[{ "error": {"message":"invalid api key"}}]])
                return
              }
            }
        }
        server {
            server_name payment_required_instance;
            default_type 'application/json';
            listen 6736;
            location / {
              content_by_lua_block {
                ngx.status = 402
                ngx.say([[{ "error": {"message":"insufficient balance"}}]])
                return
              }
            }
        }
        server {
            server_name success_instance;
            default_type 'application/json';
            listen 6733;
            location / {
              content_by_lua_block {
                ngx.status = 200
                ngx.print("success")
                return
              }
            }
        }
        # Upstream that echoes the request body it receives inside a well-formed
        # chat completion so the test can assert exactly what was forwarded to
        # the fallback instance.
        server {
            server_name echo_instance;
            default_type 'application/json';
            listen 6734;
            location / {
              content_by_lua_block {
                local json = require("cjson.safe")
                ngx.req.read_body()
                local raw = ngx.req.get_body_data() or ""
                ngx.status = 200
                ngx.say(json.encode({
                    id = "chatcmpl-echo",
                    object = "chat.completion",
                    model = "echo",
                    choices = {{
                        index = 0,
                        message = { role = "assistant", content = raw },
                        finish_reason = "stop",
                    }},
                    usage = { prompt_tokens = 1, completion_tokens = 1, total_tokens = 2 },
                }))
              }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: max_retries caps fallback so all instances are not exhausted
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
                            "max_retries": 1,
                            "balancer": {
                                "algorithm": "roundrobin"
                            },
                            "instances": [
                                {"name":"err-1","provider":"openai-compatible","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6731"}},
                                {"name":"err-2","provider":"openai-compatible","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6731"}},
                                {"name":"err-3","provider":"openai-compatible","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6731"}}
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



=== TEST 2: request stops after max_retries and returns the upstream error (500, not 502)
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 500
--- error_log
reached max_retries 1



=== TEST 3: fast failure within retry_on_failure_within_ms still triggers fallback
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
                            "retry_on_failure_within_ms": 5000,
                            "instances": [
                                {"name":"fast-err","provider":"openai-compatible","weight":1,"priority":10,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6731"}},
                                {"name":"success","provider":"openai-compatible","weight":1,"priority":0,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6733"}}
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



=== TEST 4: fast failure falls back to the healthy instance and logs the upstream error body
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- response_body chomp
success
--- error_code: 200
--- error_log
fast internal error



=== TEST 5: slow failure beyond retry_on_failure_within_ms is returned directly
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
                            "retry_on_failure_within_ms": 200,
                            "instances": [
                                {"name":"slow-err","provider":"openai-compatible","weight":1,"priority":10,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6732"}},
                                {"name":"success","provider":"openai-compatible","weight":1,"priority":0,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6733"}}
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



=== TEST 6: slow failure does not fall back and returns the upstream error body to the client
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 500
--- response_body_like: slow internal error
--- error_log
exceeding retry_on_failure_within_ms 200



=== TEST 7: fallback preserves the client body: set up asymmetric instances
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
                            "instances": [
                                {"name":"err-a","provider":"openai-compatible","weight":1,"priority":10,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"upstream-model-A","temperature":0.9},"override":{"endpoint":"http://127.0.0.1:6731"}},
                                {"name":"echo-b","provider":"openai-compatible","weight":1,"priority":0,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"upstream-model-B"},"override":{"endpoint":"http://127.0.0.1:6734"}}
                            ],
                            "ssl_verify": false
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(conf, ctx) ngx.log(ngx.WARN, \"FALLBACKVARS request_llm_model=\", tostring(ctx.var.request_llm_model), \" llm_model=\", tostring(ctx.var.llm_model)) end"]
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



=== TEST 8: retry keeps the original model in vars and does not leak instance A options into instance B
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http").new()
            local cjson = require("cjson.safe")
            local res = assert(http:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/anything", {
                method = "POST",
                body = '{ "model": "client-model", "messages": [ { "role": "user", "content": "What is 1+1?"} ] }',
                headers = { ["Content-Type"] = "application/json" },
            }))
            local completion = cjson.decode(res.body)
            local forwarded = cjson.decode(completion.choices[1].message.content)
            ngx.say("model=", forwarded.model)
            ngx.say(forwarded.temperature == nil and "no temperature leak" or "temperature leaked")
        }
    }
--- response_body
model=upstream-model-B
no temperature leak
--- error_log
FALLBACKVARS request_llm_model=client-model llm_model=upstream-model-B



=== TEST 9: fallback_http_statuses makes 401 and 402 fall back to another instance
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
                            "fallback_http_statuses": [401, 402],
                            "instances": [
                                {"name":"expired-key","provider":"openai-compatible","weight":1,"priority":20,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6735"}},
                                {"name":"drained-key","provider":"openai-compatible","weight":1,"priority":10,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6736"}},
                                {"name":"good-key","provider":"openai-compatible","weight":1,"priority":0,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6733"}}
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



=== TEST 10: the request is served by the instance with a working key
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- response_body chomp
success
--- error_code: 200
--- error_log
returned status 401, falling back to
returned status 402, falling back to



=== TEST 11: max_retries also bounds the fallback_http_statuses retries
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
                            "fallback_http_statuses": [401, 402],
                            "max_retries": 0,
                            "instances": [
                                {"name":"expired-key","provider":"openai-compatible","weight":1,"priority":20,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6735"}},
                                {"name":"good-key","provider":"openai-compatible","weight":1,"priority":0,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6733"}}
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



=== TEST 12: the upstream status and error body reach the client once retries are capped
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 401
--- response_body eval
qr/invalid api key/
--- error_log
reached max_retries 0



=== TEST 13: without fallback_http_statuses a 401 is still returned as is
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
                            "fallback_strategy": ["http_429", "http_5xx"],
                            "instances": [
                                {"name":"expired-key","provider":"openai-compatible","weight":1,"priority":20,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6735"}},
                                {"name":"good-key","provider":"openai-compatible","weight":1,"priority":0,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6733"}}
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



=== TEST 14: the 401 is not retried and reaches the client
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 401
--- response_body eval
qr/invalid api key/
--- no_error_log
falling back to



=== TEST 15: fallback_http_statuses only accepts error statuses
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
                            "fallback_http_statuses": [200],
                            "instances": [
                                {"name":"good-key","provider":"openai-compatible","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6733"}}
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
--- error_code: 400
--- response_body eval
qr/expected 200 to be at least 400/
