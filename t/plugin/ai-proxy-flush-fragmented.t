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
use File::Slurp ();

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;
    $block->set_value("http_config", <<'_EOC_');
        server {
            listen 7752;
            location /stream {
                content_by_lua_block {
                    local loader = require("lib.fixture_loader")
                    local body = assert(loader.load(ngx.req.get_headers()["X-AI-Fixture"]))
                    local args = ngx.req.get_uri_args()
                    ngx.header["Content-Type"] = "text/event-stream"
                    local function send(chunk)
                        if not ngx.print(chunk) or not ngx.flush(true) then
                            return false
                        end
                        ngx.sleep(0.05)
                        return true
                    end
                    if args.skip then
                        if not send(": keepalive\n\n") or not send(": keepalive\n\n") then
                            return
                        end
                    end
                    local offset = 0
                    if args.after_first then
                        offset = assert(body:find("\n\n", 1, true)) + 1
                        if not send(body:sub(1, offset)) then
                            return
                        end
                    end
                    -- Two fragments leave the next frame incomplete across a flush interval.
                    if not send(body:sub(offset + 1, offset + 10))
                       or not send(body:sub(offset + 11, offset + 20)) then
                        return
                    end
                    ngx.print(body:sub(offset + 21))
                }
            }
        }
_EOC_
    $block->set_value("apisix_yaml", <<'_EOC_');
routes:
  - id: native
    uri: /fragmented/v1/responses
    plugins:
      ai-proxy-multi:
        instances:
          - name: native
            provider: openai-compatible
            weight: 1
            auth:
              header:
                Authorization: Bearer test-key
            override:
              endpoint: http://127.0.0.1:7752/stream
  - id: after-first
    uri: /after-first/v1/responses
    plugins:
      ai-proxy-multi:
        instances:
          - name: native
            provider: openai-compatible
            weight: 1
            auth:
              header:
                Authorization: Bearer test-key
            override:
              endpoint: http://127.0.0.1:7752/stream?after_first=true
  - id: sync
    uri: /sync/v1/responses
    plugins:
      ai-proxy-multi:
        streaming_flush_interval_ms: 0
        instances:
          - name: native
            provider: openai-compatible
            weight: 1
            auth:
              header:
                Authorization: Bearer test-key
            override:
              endpoint: http://127.0.0.1:7752/stream
  - id: converted
    uri: /converted/v1/messages
    plugins:
      ai-proxy:
        provider: openai-compatible
        auth:
          header:
            Authorization: Bearer test-key
        override:
          endpoint: http://127.0.0.1:7752/stream?skip=true
#END
_EOC_
});

run_tests();

__DATA__

=== TEST 1: async flush waits for the first complete native SSE frame
--- request
POST /fragmented/v1/responses
{"model":"test","input":"hi","stream":true}
--- more_headers
X-AI-Fixture: openai/responses-streaming.sse
--- response_body eval
scalar File::Slurp::read_file("t/fixtures/openai/responses-streaming.sse")
--- no_error_log
[error]
nothing to flush
client disconnected during AI streaming



=== TEST 2: async flush preserves partial frames after earlier output
--- request
POST /after-first/v1/responses
{"model":"test","input":"hi","stream":true}
--- more_headers
X-AI-Fixture: openai/responses-streaming.sse
--- response_body eval
scalar File::Slurp::read_file("t/fixtures/openai/responses-streaming.sse")
--- no_error_log
[error]
nothing to flush
client disconnected during AI streaming



=== TEST 3: synchronous flush waits for a complete native SSE frame
--- request
POST /sync/v1/responses
{"model":"test","input":"hi","stream":true}
--- more_headers
X-AI-Fixture: openai/responses-streaming.sse
--- response_body eval
scalar File::Slurp::read_file("t/fixtures/openai/responses-streaming.sse")
--- no_error_log
[error]
nothing to flush
client disconnected during AI streaming



=== TEST 4: converter waits through skipped events and partial frames before output
--- request
POST /converted/v1/messages
{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":32,"stream":true}
--- more_headers
X-AI-Fixture: protocol-conversion/openai-to-anthropic-stream.sse
--- response_body_like eval
qr/event: message_start.*Hello.* world.*event: message_stop/s
--- no_error_log
[error]
nothing to flush
client disconnected during AI streaming
