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


my $resp_file = 't/assets/anthropic-native-response.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $resp = do { local $/; <$fh> };
close($fh);


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $extra_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $extra_yaml_config);

    # Default mock server: native Anthropic Messages API on port 6726
    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name anthropic-native;
            listen 6726;

            default_type 'application/json';

            location /v1/messages {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                        return
                    end

                    ngx.req.read_body()
                    local body_str = ngx.req.get_body_data()
                    local body, err = json.decode(body_str)
                    if not body then
                        ngx.status = 400
                        ngx.say("bad json: " .. (err or ""))
                        return
                    end

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

                    -- test-type: inspect — echo back request details for assertion
                    local test_type = ngx.req.get_headers()["test-type"]
                    if test_type == "inspect" then
                        local result = {
                            anthropic_version = ngx.req.get_headers()["anthropic-version"],
                            has_stream_options = (body.stream_options ~= nil),
                        }
                        ngx.status = 200
                        ngx.say(json.encode(result))
                        return
                    end

                    ngx.status = 200
                    ngx.say([[$resp]])
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: schema accepts anthropic-native provider
--- apisix_yaml
routes:
  - id: 1
    uri: /t
    plugins: {}
#END
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy-multi")
            local ok, err = plugin.check_schema({
                instances = {
                    {
                        name = "anthropic-native-instance",
                        provider = "anthropic-native",
                        weight = 1,
                        auth = {
                            header = {
                                ["Authorization"] = "Bearer token"
                            }
                        },
                        options = {
                            model = "claude-3-5-sonnet-20241022",
                            max_tokens = 512,
                        },
                        override = {
                            endpoint = "http://localhost:6726/v1/messages"
                        }
                    }
                },
                ssl_verify = false
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 2: non-streaming request returns Anthropic response
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: anthropic-native-instance
            provider: anthropic-native
            weight: 1
            auth:
              header:
                Authorization: "Bearer token"
            options:
              model: claude-3-5-sonnet-20241022
              max_tokens: 512
            override:
              endpoint: "http://localhost:6726/v1/messages"
        ssl_verify: false
#END
--- request
POST /anything
{"messages":[{"role":"user","content":"What is 1+1?"}]}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
--- error_code: 200
--- response_body eval
qr/"text":\s*"1 \+ 1 = 2\."/



=== TEST 3: anthropic-version header is injected into upstream request
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: anthropic-native-instance
            provider: anthropic-native
            weight: 1
            auth:
              header:
                Authorization: "Bearer token"
            options:
              model: claude-3-5-sonnet-20241022
              max_tokens: 512
            override:
              endpoint: "http://localhost:6726/v1/messages"
        ssl_verify: false
#END
--- request
POST /anything
{"messages":[{"role":"user","content":"hello"}]}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
test-type: inspect
--- error_code: 200
--- response_body eval
qr/"anthropic_version":"2023-06-01"/



=== TEST 4: stream_options is stripped from upstream request
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: anthropic-native-instance
            provider: anthropic-native
            weight: 1
            auth:
              header:
                Authorization: "Bearer token"
            options:
              model: claude-3-5-sonnet-20241022
              max_tokens: 512
            override:
              endpoint: "http://localhost:6726/v1/messages"
        ssl_verify: false
#END
--- request
POST /anything
{"messages":[{"role":"user","content":"hello"}],"stream":true,"stream_options":{"include_usage":true}}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
test-type: inspect
--- error_code: 200
--- response_body eval
qr/"has_stream_options":false/



=== TEST 5: token usage is recorded from input_tokens / output_tokens
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: anthropic-native-instance
            provider: anthropic-native
            weight: 1
            auth:
              header:
                Authorization: "Bearer token"
            options:
              model: claude-3-5-sonnet-20241022
              max_tokens: 512
            override:
              endpoint: "http://localhost:6726/v1/messages"
        ssl_verify: false
#END
--- request
POST /anything
{"messages":[{"role":"user","content":"What is 1+1?"}]}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
--- error_code: 200
--- error_log eval
qr/got token usage from ai service \(anthropic-native\):.*"prompt_tokens":23.*"completion_tokens":8/



=== TEST 6: streaming SSE events are forwarded correctly
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: anthropic-native-stream
            provider: anthropic-native
            weight: 1
            auth:
              header:
                Authorization: "Bearer token"
            options:
              model: claude-3-5-sonnet-20241022
              max_tokens: 512
              stream: true
            override:
              endpoint: "http://localhost:7738/v1/messages"
        ssl_verify: false
#END
--- http_config
    server {
        server_name anthropic-native-sse;
        listen 7738;

        location /v1/messages {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/event-stream"
                ngx.header["Cache-Control"] = "no-cache"
                ngx.header["X-Accel-Buffering"] = "no"

                ngx.print("event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_01\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-5-sonnet-20241022\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":23,\"output_tokens\":1}}}\n\n")
                ngx.flush(true)

                ngx.print("event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n")
                ngx.flush(true)

                ngx.print("event: ping\ndata: {\"type\":\"ping\"}\n\n")
                ngx.flush(true)

                ngx.print("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"1 + 1 = 2.\"}}\n\n")
                ngx.flush(true)

                ngx.print("event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n")
                ngx.flush(true)

                ngx.print("event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":8}}\n\n")
                ngx.flush(true)

                ngx.print("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
                ngx.flush(true)
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })
            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local res, err = httpc:request({
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer token",
                },
                path = "/anything",
                body = [[{"messages":[{"role":"user","content":"What is 1+1?"}],"stream":true}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local chunks = {}
            while true do
                local chunk, err = res.body_reader()
                if err then
                    core.log.error("failed to read chunk: ", err)
                    break
                end
                if not chunk then break end
                core.table.insert_tail(chunks, chunk)
            end

            local full = table.concat(chunks, "")
            if full:find("text_delta") then
                ngx.say("streaming ok")
            else
                ngx.say("streaming failed: " .. full)
            end
        }
    }
--- response_body
streaming ok



=== TEST 7: streaming token usage from message_delta, not message_start output_tokens
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: anthropic-native-stream
            provider: anthropic-native
            weight: 1
            auth:
              header:
                Authorization: "Bearer token"
            options:
              model: claude-3-5-sonnet-20241022
              max_tokens: 512
              stream: true
            override:
              endpoint: "http://localhost:7738/v1/messages"
        ssl_verify: false
#END
--- http_config
    server {
        server_name anthropic-native-sse;
        listen 7738;

        location /v1/messages {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/event-stream"

                -- message_start has output_tokens=1 (pre-allocated, must NOT be used as final)
                ngx.print("event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":10,\"output_tokens\":1}}}\n\n")
                ngx.flush(true)

                ngx.print("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"hello\"}}\n\n")
                ngx.flush(true)

                -- message_delta carries the real output_tokens=5
                ngx.print("event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":5}}\n\n")
                ngx.flush(true)

                ngx.print("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
                ngx.flush(true)
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })
            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local res, err = httpc:request({
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer token",
                },
                path = "/anything",
                body = [[{"messages":[{"role":"user","content":"hi"}],"stream":true}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local found_text = false
            while true do
                local chunk, err = res.body_reader()
                if err then break end
                if not chunk then break end
                if chunk:find("text_delta") then found_text = true end
            end

            -- wait for the /anything coroutine to finish writing warn logs
            ngx.sleep(0.5)

            if found_text then
                ngx.say("streaming ok")
            else
                ngx.say("streaming failed")
            end
        }
    }
--- response_body
streaming ok
--- wait: 0.5
--- error_log eval
qr/got token usage from ai service \(anthropic-native\):.*"prompt_tokens":10.*"completion_tokens":5/



=== TEST 8: [DONE] sentinel from compatible endpoints is silently ignored
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: anthropic-done-test
            provider: anthropic-native
            weight: 1
            auth:
              header:
                Authorization: "Bearer token"
            options:
              model: claude-3-5-sonnet-20241022
              max_tokens: 100
              stream: true
            override:
              endpoint: "http://localhost:7739/v1/messages"
        ssl_verify: false
#END
--- http_config
    server {
        server_name anthropic-native-sse-done;
        listen 7739;

        location /v1/messages {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/event-stream"

                ngx.print("event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":5,\"output_tokens\":1}}}\n\n")
                ngx.flush(true)

                ngx.print("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"hi\"}}\n\n")
                ngx.flush(true)

                ngx.print("event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":3}}\n\n")
                ngx.flush(true)

                ngx.print("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
                ngx.flush(true)

                -- OpenAI-style sentinel appended by some compatible endpoints (e.g. DeepSeek)
                ngx.print("data: [DONE]\n\n")
                ngx.flush(true)
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })
            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local res, err = httpc:request({
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer token",
                },
                path = "/anything",
                body = [[{"messages":[{"role":"user","content":"hi"}],"stream":true}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            while true do
                local chunk = res.body_reader()
                if not chunk then break end
            end
            ngx.say("no error")
        }
    }
--- response_body
no error
--- no_error_log
failed to decode SSE data



=== TEST 9: error event in stream is logged as warn and does not crash
--- apisix_yaml
routes:
  - id: 1
    uri: /anything
    plugins:
      ai-proxy-multi:
        instances:
          - name: anthropic-error-test
            provider: anthropic-native
            weight: 1
            auth:
              header:
                Authorization: "Bearer token"
            options:
              model: claude-3-5-sonnet-20241022
              max_tokens: 100
              stream: true
            override:
              endpoint: "http://localhost:7740/v1/messages"
        ssl_verify: false
#END
--- http_config
    server {
        server_name anthropic-native-sse-err;
        listen 7740;

        location /v1/messages {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/event-stream"

                ngx.print("event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":5,\"output_tokens\":1}}}\n\n")
                ngx.flush(true)

                -- Simulate an overloaded error mid-stream
                ngx.print("event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n")
                ngx.flush(true)

                ngx.print("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
                ngx.flush(true)
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local ok, err = httpc:connect({
                scheme = "http",
                host = "localhost",
                port = ngx.var.server_port,
            })
            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local res, err = httpc:request({
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer token",
                },
                path = "/anything",
                body = [[{"messages":[{"role":"user","content":"hi"}],"stream":true}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            while true do
                local chunk = res.body_reader()
                if not chunk then break end
            end

            -- wait for the /anything coroutine to finish writing warn logs
            ngx.sleep(0.5)

            ngx.say("completed")
        }
    }
--- response_body
completed
--- wait: 0.5
--- error_log eval
qr/received error event from anthropic stream/
