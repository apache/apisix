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

BEGIN { $ENV{TEST_ENABLE_CONTROL_API_V1} = "0"; }
use t::APISIX 'no_plan';
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;
    $block->set_value("request", "GET /t");
    $block->set_value("extra_yaml_config", <<_EOC_);
plugins:
  - ai-proxy
  - ai-aliyun-content-moderation
  - key-auth
  - serverless-post-function
_EOC_
    $block->set_value("http_config", <<'_EOC_');
    server {
        listen 6724;
        location / {
            content_by_lua_block {
                local core = require("apisix.core")
                ngx.req.read_body()
                local args = ngx.req.get_post_args()
                local params = assert(core.json.decode(args.ServiceParameters))
                assert(ngx.shared.test:incr(args.Service .. "_calls", 1, 0))
                assert(ngx.shared.test:set(args.Service .. "_content", params.content))
                if params.content == "scan-error" then
                    ngx.status = 500
                    ngx.say("scan failed")
                    return
                end
                require("lib.server").aliyun_moderation()
            }
        }
    }
    server {
        listen 6725;
        location / {
            content_by_lua_block {
                local fixture = ngx.req.get_headers()["X-AI-Fixture"]
                local content = assert(require("lib.fixture_loader").load(fixture))
                ngx.header.content_type = "text/event-stream"
                if ngx.req.get_headers()["X-Split-Done"] then
                    ngx.print(content:sub(1, -6))
                    ngx.flush(true)
                    ngx.sleep(0.01)
                    ngx.print(content:sub(-5))
                elseif ngx.req.get_headers()["X-Buffered"] then
                    ngx.print(content)
                else
                    for event in content:gmatch("(.-\n\n)") do
                        ngx.print(event)
                        ngx.flush(true)
                        ngx.sleep(0.01)
                    end
                end
            }
        }
    }
_EOC_
    if ($block->case) {
        my $case = $block->case;
        $block->set_value("config", <<_EOC_);
    location /t {
        content_by_lua_block {
            require("lib.ai_moderation_result").check($case)
            ngx.say("passed")
        }
    }
_EOC_
    }
});
run_tests();
__DATA__

=== TEST 1: configure native protocol routes and Consumer moderation
--- config
    location /t {
        content_by_lua_block {
            require("lib.ai_moderation_result").setup()
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: Chat standalone DONE exposes denial and zero usage
--- case: {fixture="chat-deny", protocol="chat"}
--- response_body
passed



=== TEST 3: Chat coalesced JSON and DONE has the same result
--- case: {fixture="chat-deny", protocol="chat", buffered=true}
--- response_body
passed



=== TEST 4: Chat split DONE never exposes a partial terminator
--- case: {fixture="chat-deny", protocol="chat", split_done=true}
--- response_body
passed



=== TEST 5: Chat real token accounting survives the zero usage result
--- case: {fixture="chat-usage", protocol="chat", tokens=18}
--- response_body
passed



=== TEST 6: Chat safe result has no denial text
--- case: {fixture="chat-safe", protocol="chat", text="safe output", safe=true}
--- response_body
passed



=== TEST 7: Failed response scan cannot reuse the request risk level
--- case: {fixture="chat-failure", protocol="chat", text="scan-error", failure=true}
--- response_body
passed
--- error_log
failed to check content:



=== TEST 8: All choices finish before the single moderation result
--- case: {fixture="chat-multiple-choices", protocol="chat", tokens=18}
--- response_body
passed



=== TEST 9: Anthropic standalone stop gets metadata without new content blocks
--- case: {fixture="anthropic-deny", protocol="anthropic"}
--- response_body
passed



=== TEST 10: Anthropic split usage remains in billing context
--- case: {fixture="anthropic-usage", protocol="anthropic", tokens=18}
--- response_body
passed



=== TEST 11: Anthropic coalesced message_delta is decorated in place
--- case: {fixture="anthropic-usage", protocol="anthropic", tokens=18, buffered=true}
--- response_body
passed



=== TEST 12: Responses completed retains output and denial metadata
--- case: {fixture="responses-deny", protocol="responses"}
--- response_body
passed



=== TEST 13: Responses completed preserves actual usage
--- case: {fixture="responses-usage", protocol="responses", tokens=18}
--- response_body
passed



=== TEST 14: Responses EOF does not fabricate a completed response
--- case: {fixture="responses-eof", protocol="responses", eof=true}
--- response_body
passed



=== TEST 15: Chat provider emits the final result in the Anthropic client protocol
--- case: {fixture="chat-usage", protocol="anthropic", converted=true, tokens=18}
--- response_body
passed



=== TEST 16: chat-error is preserved without a final moderation result
--- case: {fixture="chat-error", protocol="chat", error=true}
--- response_body
passed



=== TEST 17: anthropic-error is preserved without a final moderation result
--- case: {fixture="anthropic-error", protocol="anthropic", error=true, tokens=18}
--- response_body
passed



=== TEST 18: responses-error is preserved without a final moderation result
--- case: {fixture="responses-error", protocol="responses", error=true}
--- response_body
passed



=== TEST 19: responses-failed is preserved without a final moderation result
--- case: {fixture="responses-failed", protocol="responses", error=true}
--- response_body
passed



=== TEST 20: responses-incomplete is preserved without a final moderation result
--- case: {fixture="responses-incomplete", protocol="responses", error=true, error_text="max_output_tokens"}
--- response_body
passed



=== TEST 21: Chat result preserves the upstream length finish reason
--- case: {fixture="chat-length", protocol="chat", tokens=18, finish_reason="length"}
--- response_body
passed



=== TEST 22: Chat result preserves the upstream tool_calls finish reason
--- case: {fixture="chat-tool_calls", protocol="chat", tokens=18, finish_reason="tool_calls"}
--- response_body
passed



=== TEST 23: Anthropic result does not invent missing stop information
--- case: {fixture="anthropic-null-delta", protocol="anthropic", tokens=18, missing_stop=true}
--- response_body
passed



=== TEST 24: Chat clean EOF does not invent a finish reason
--- case: {fixture="chat-clean-eof", protocol="chat", tokens=18}
--- response_body
passed



=== TEST 25: multiple choices retain their independent finish reasons
--- case: {fixture="chat-multiple-reasons", protocol="chat", tokens=18, finish_reason="tool_calls"}
--- response_body
passed



=== TEST 26: anthropic safe result has an empty top-level denial message
--- case: {fixture="anthropic-safe", protocol="anthropic", text="safe output", safe=true, tokens=18}
--- response_body
passed



=== TEST 27: anthropic safe result has an empty top-level denial message in an existing event
--- case: {fixture="anthropic-safe", protocol="anthropic", text="safe output", safe=true, tokens=18, buffered=true}
--- response_body
passed



=== TEST 28: responses safe result has an empty top-level denial message
--- case: {fixture="responses-safe", protocol="responses", text="safe output", safe=true, tokens=18}
--- response_body
passed



=== TEST 29: Anthropic result preserves stop sequence after the original event was sent
--- case: {fixture="anthropic-stop-sequence", protocol="anthropic", tokens=18, stop_sequence="END"}
--- response_body
passed



=== TEST 30: Anthropic result preserves stop sequence in the original event
--- case: {fixture="anthropic-stop-sequence", protocol="anthropic", tokens=18, stop_sequence="END", buffered=true}
--- response_body
passed
