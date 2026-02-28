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

    my $extra_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - ai-rate-limiting
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $extra_yaml_config);

    # Default mock LLM backend on port 6799
    if (!defined $block->http_config) {
        my $http_config = <<_EOC_;
    server {
        server_name mock-llm;
        listen 6799;

        default_type 'application/json';

        location /v1/chat/completions {
            content_by_lua_block {
                ngx.status = 200
                ngx.say([[{
                    "id": "chatcmpl-test",
                    "object": "chat.completion",
                    "choices": [{"index":0,"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}],
                    "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
                }]])
            }
        }
    }
_EOC_
        $block->set_value("http_config", $http_config);
    }
});

run_tests();

__DATA__

=== TEST 1: schema check — standard_headers field is accepted
--- apisix_yaml
routes:
  - id: 1
    uri: /t
    plugins:
      ai-rate-limiting:
        instances:
          - name: mock-instance
            limit: 1000
            time_window: 60
        limit_strategy: total_tokens
        standard_headers: true
        rejected_code: 429
    upstream:
      nodes:
        "127.0.0.1:6799": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rate-limiting")
            local ok, err = plugin.check_schema({
                instances = {
                    { name = "mock-instance", limit = 1000, time_window = 60 }
                },
                limit_strategy = "total_tokens",
                standard_headers = true,
                rejected_code = 429,
            })
            if not ok then
                ngx.say("schema error: ", err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 2: schema check — standard_headers defaults to false
--- apisix_yaml
routes:
  - id: 1
    uri: /t
    plugins:
      ai-rate-limiting:
        instances:
          - name: mock-instance
            limit: 1000
            time_window: 60
    upstream:
      nodes:
        "127.0.0.1:6799": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-rate-limiting")
            local conf = {
                instances = {
                    { name = "mock-instance", limit = 1000, time_window = 60 }
                },
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say("schema error: ", err)
                return
            end
            -- default should be false
            if conf.standard_headers == false then
                ngx.say("default is false")
            else
                ngx.say("unexpected default: ", tostring(conf.standard_headers))
            end
        }
    }
--- response_body
default is false



=== TEST 3: standard_headers=true returns X-RateLimit-Limit-Tokens header
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: mock-instance
            provider: openai
            weight: 1
            auth:
              header:
                Authorization: "Bearer test-key"
            options:
              model: gpt-4o-mini
            override:
              endpoint: "http://localhost:6799/v1/chat/completions"
        ssl_verify: false
      ai-rate-limiting:
        instances:
          - name: mock-instance
            limit: 10000
            time_window: 60
        limit_strategy: total_tokens
        standard_headers: true
        rejected_code: 429
#END
--- request
POST /anything
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
apikey: test-key-123
--- error_code: 200
--- response_headers_like
X-RateLimit-Limit-Tokens: \d+
X-RateLimit-Remaining-Tokens: \d+
X-RateLimit-Reset-Tokens: \d+



=== TEST 4: standard_headers=true, 429 response has Remaining-Tokens: 0
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: mock-instance
            provider: openai
            weight: 1
            auth:
              header:
                Authorization: "Bearer test-key"
            options:
              model: gpt-4o-mini
            override:
              endpoint: "http://localhost:6799/v1/chat/completions"
        ssl_verify: false
      ai-rate-limiting:
        instances:
          - name: mock-instance
            limit: 1
            time_window: 60
        limit_strategy: total_tokens
        standard_headers: true
        rejected_code: 429
#END
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            -- First request: should succeed and consume the 1-token budget
            local res1, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/anything", {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["apikey"] = "test-key-123",
                },
                body = [[{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}]],
            })
            if not res1 then
                ngx.say("req1 error: ", err)
                return
            end

            -- Second request: should be rate-limited (429)
            local res2, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/anything", {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["apikey"] = "test-key-123",
                },
                body = [[{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi again"}]}]],
            })
            if not res2 then
                ngx.say("req2 error: ", err)
                return
            end

            ngx.say("status: ", res2.status)
            local remaining = res2.headers["X-RateLimit-Remaining-Tokens"]
            ngx.say("remaining: ", remaining or "nil")
        }
    }
--- response_body
status: 429
remaining: 0



=== TEST 5: limit_strategy=prompt_tokens uses PromptTokens suffix
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: mock-instance
            provider: openai
            weight: 1
            auth:
              header:
                Authorization: "Bearer test-key"
            options:
              model: gpt-4o-mini
            override:
              endpoint: "http://localhost:6799/v1/chat/completions"
        ssl_verify: false
      ai-rate-limiting:
        instances:
          - name: mock-instance
            limit: 10000
            time_window: 60
        limit_strategy: prompt_tokens
        standard_headers: true
        rejected_code: 429
#END
--- request
POST /anything
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
apikey: test-key-123
--- error_code: 200
--- response_headers_like
X-RateLimit-Limit-PromptTokens: \d+
X-RateLimit-Remaining-PromptTokens: \d+
X-RateLimit-Reset-PromptTokens: \d+



=== TEST 6: limit_strategy=completion_tokens uses CompletionTokens suffix
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: mock-instance
            provider: openai
            weight: 1
            auth:
              header:
                Authorization: "Bearer test-key"
            options:
              model: gpt-4o-mini
            override:
              endpoint: "http://localhost:6799/v1/chat/completions"
        ssl_verify: false
      ai-rate-limiting:
        instances:
          - name: mock-instance
            limit: 10000
            time_window: 60
        limit_strategy: completion_tokens
        standard_headers: true
        rejected_code: 429
#END
--- request
POST /anything
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
apikey: test-key-123
--- error_code: 200
--- response_headers_like
X-RateLimit-Limit-CompletionTokens: \d+
X-RateLimit-Remaining-CompletionTokens: \d+
X-RateLimit-Reset-CompletionTokens: \d+



=== TEST 7: standard_headers=false (default) outputs legacy X-AI-RateLimit headers
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: mock-instance
            provider: openai
            weight: 1
            auth:
              header:
                Authorization: "Bearer test-key"
            options:
              model: gpt-4o-mini
            override:
              endpoint: "http://localhost:6799/v1/chat/completions"
        ssl_verify: false
      ai-rate-limiting:
        instances:
          - name: mock-instance
            limit: 10000
            time_window: 60
        limit_strategy: total_tokens
        standard_headers: false
        rejected_code: 429
#END
--- request
POST /anything
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
apikey: test-key-123
--- error_code: 200
--- response_headers_like
X-AI-RateLimit-Limit-mock-instance: \d+
X-AI-RateLimit-Remaining-mock-instance: \d+
X-AI-RateLimit-Reset-mock-instance: \d+
