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
        listen 18724;

        default_type 'application/json';

        location /v1/chat/completions {
            content_by_lua_block {
                ngx.sleep(0.2)
                ngx.req.read_body()
                local body = ngx.req.get_body_data() or ""
                local status = ngx.req.get_headers()["x-test-status"]
                if status == "500" or body:find("FAIL", 1, true) then
                    ngx.status = 500
                    ngx.say('{"error":"internal"}')
                    return
                end
                if status == "429" then
                    ngx.status = 429
                    ngx.say('{"error":"rate limited"}')
                    return
                end
                ngx.say('{"choices":[{"finish_reason":"stop","index":0,"message":{"content":"2","role":"assistant"}}],"model":"gpt-4","object":"chat.completion","usage":{"completion_tokens":5,"prompt_tokens":8,"total_tokens":13}}')
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set up a route with ai-proxy and a log-phase printer of both vars
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
                            "provider": "openai",
                            "auth": {"header": {"Authorization": "Bearer token"}},
                            "options": {"model": "gpt-4"},
                            "override": {"endpoint": "http://localhost:18724"},
                            "ssl_verify": false
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(conf, ctx) ngx.log(ngx.WARN, \"LATENCYVARS status=\", ngx.status, \" aurt=\", tostring(ctx.var.apisix_upstream_response_time), \" ttft=\", tostring(ctx.var.llm_time_to_first_token)) end"]
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



=== TEST 2: 200 response records both vars in milliseconds
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 200
--- error_log eval
qr/LATENCYVARS status=200 aurt=\d{3,4}(?![\.\d]) ttft=\d{3,4}(?![\.\d])/



=== TEST 3: 500 early exit records both vars in milliseconds, not seconds
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
x-test-status: 500
--- error_code: 500
--- error_log eval
qr/LATENCYVARS status=500 aurt=\d{3,4}(?![\.\d]) ttft=\d{3,4}(?![\.\d])/



=== TEST 4: 429 early exit records both vars in milliseconds
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
x-test-status: 429
--- error_code: 429
--- error_log eval
qr/LATENCYVARS status=429 aurt=\d{3,4}(?![\.\d]) ttft=\d{3,4}(?![\.\d])/



=== TEST 5: the unit no longer flips between a 200 and a 500 in one lifecycle
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/anything"
            local body_ok = [[{ "messages": [ { "role": "user", "content": "ok"} ] }]]
            local body_fail = [[{ "messages": [ { "role": "user", "content": "FAIL"} ] }]]
            local res1 = http.new():request_uri(uri, {method = "POST", body = body_ok})
            local res2 = http.new():request_uri(uri, {method = "POST", body = body_fail})
            ngx.sleep(0.5)
            ngx.say(res1.status, " ", res2.status)
        }
    }
--- request
GET /t
--- response_body
200 500
--- error_log eval
[qr/LATENCYVARS status=200 aurt=\d{3,4}(?![\.\d]) ttft=\d{3,4}(?![\.\d])/,
 qr/LATENCYVARS status=500 aurt=\d{3,4}(?![\.\d]) ttft=\d{3,4}(?![\.\d])/]



=== TEST 6: set up a route pointing at a dead upstream
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
                            "provider": "openai",
                            "auth": {"header": {"Authorization": "Bearer token"}},
                            "options": {"model": "gpt-4"},
                            "override": {"endpoint": "http://localhost:18725"},
                            "ssl_verify": false
                        },
                        "serverless-post-function": {
                            "phase": "log",
                            "functions": ["return function(conf, ctx) ngx.log(ngx.WARN, \"LATENCYVARS status=\", ngx.status, \" aurt=\", tostring(ctx.var.apisix_upstream_response_time), \" ttft=\", tostring(ctx.var.llm_time_to_first_token)) end"]
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



=== TEST 7: transport error records a millisecond value, ttft stays 0
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 500
--- error_log eval
qr/LATENCYVARS status=500 aurt=\d+(?![\.\d]) ttft=0(?![\.\d])/



=== TEST 8: set up a route with prometheus enabled, plus the metrics endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "prometheus": {},
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {"header": {"Authorization": "Bearer token"}},
                            "options": {"model": "gpt-4"},
                            "override": {"endpoint": "http://localhost:18724"},
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("route failed")
                return
            end

            code = t('/apisix/admin/routes/metrics',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/apisix/prometheus/metrics",
                    "plugins": {"public-api": {}}
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("metrics route failed")
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 9: only the served response is observed in llm_latency
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local body = [[{ "messages": [ { "role": "user", "content": "hi"} ] }]]

            local function call(status_hdr)
                local headers = {["Content-Type"] = "application/json"}
                if status_hdr then
                    headers["x-test-status"] = status_hdr
                end
                local res = http.new():request_uri(base .. "/anything",
                    {method = "POST", body = body, headers = headers})
                return res.status
            end

            local s_ok = call(nil)
            local s_500 = call("500")
            local s_429 = call("429")
            ngx.sleep(0.5)

            local res = http.new():request_uri(base .. "/apisix/prometheus/metrics")
            local count = res.body:match("apisix_llm_latency_count%b{}%s+(%d+)")
            ngx.say(s_ok, " ", s_500, " ", s_429, " llm_latency_count=", tostring(count))
        }
    }
--- response_body
200 500 429 llm_latency_count=1
