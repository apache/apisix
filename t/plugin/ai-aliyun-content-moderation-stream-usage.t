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
                local fixture = args.Service == "response_security_check"
                    and "aliyun/moderation-risk.json" or "aliyun/moderation-safe.json"
                ngx.header.content_type = "application/json"
                ngx.print(assert(require("lib.fixture_loader").load(fixture)))
            }
        }
    }
_EOC_
    if ($block->fixture) {
        my $fixture = $block->fixture;
        my $flush_events = $block->buffered ? "nil" : '"true"';
        $block->set_value("config", <<_EOC_);
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local httpc = require("resty.http").new()
            local res = assert(httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port
                .. "/chat", {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["apikey"] = "stream-usage-key",
                    ["X-AI-Fixture"] = "$fixture",
                    ["X-AI-Fixture-Flush-Events"] = $flush_events,
                },
                body = [[{"messages":[{"role":"user","content":"hello"}],"stream":true}]],
            }))
            ngx.say("status: ", res.status)
            for _, service in ipairs({"query_security_check", "response_security_check"}) do
                ngx.say(service, ": ", ngx.shared.test:get(service .. "_calls"),
                        " / ", ngx.shared.test:get(service .. "_content"))
            end
            local text = {}
            local events = require("apisix.plugins.ai-transport.sse").decode_buf(res.body)
            for _, event in ipairs(events) do
                if event.data ~= "[DONE]" then
                    local data = assert(core.json.decode(event.data))
                    local content = core.table.try_read_attr(data, "choices", 1,
                                                              "delta", "content")
                    if type(content) == "string" then
                        text[#text + 1] = content
                    end
                end
            end
            ngx.say("text: ", table.concat(text))
            local _, done_count = res.body:gsub("data: %[DONE%]", "")
            ngx.say("done events: ", done_count)
        }
    }
_EOC_
    }
});

run_tests();

__DATA__

=== TEST 1: configure consumer request and final-packet response moderation
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.test_admin").test
            local code, body = test("/apisix/admin/consumers", ngx.HTTP_PUT, [[{
                "username": "stream-usage",
                "plugins": {
                    "key-auth": {"key": "stream-usage-key"},
                    "ai-aliyun-content-moderation": {
                        "endpoint": "http://127.0.0.1:6724",
                        "region_id": "cn-beijing",
                        "access_key_id": "fake-key-id",
                        "access_key_secret": "fake-key-secret",
                        "check_request": true,
                        "check_response": true,
                        "request_check_service": "query_security_check",
                        "response_check_service": "response_security_check",
                        "stream_check_mode": "final_packet"
                    }
                }
            }]])
            assert(code < 300, body)
            code, body = test("/apisix/admin/routes/1", ngx.HTTP_PUT, [[{
                "uri": "/chat",
                "plugins": {
                    "key-auth": {},
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": {"header": {"Authorization": "Bearer test"}},
                        "override": {"endpoint": "http://127.0.0.1:1980"},
                        "streaming_flush_interval_ms": 0
                    }
                }
            }]])
            assert(code < 300, body)
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: moderate complete text when the stream ends without usage
--- fixture: openai/moderation-no-usage.sse
--- response_body
status: 200
query_security_check: 1 / hello
response_security_check: 1 / kill you
text: kill you
done events: 1



=== TEST 3: preserve moderation when the stream includes usage
--- fixture: openai/moderation-with-usage.sse
--- response_body
status: 200
query_security_check: 1 / hello
response_security_check: 1 / kill you
text: kill you
done events: 1



=== TEST 4: moderate complete text at clean EOF without usage or a done event
--- fixture: openai/moderation-eof-no-usage.sse
--- response_body
status: 200
query_security_check: 1 / hello
response_security_check: 1 / kill you
text: kill you
done events: 1



=== TEST 5: do not finalize a stream with an incomplete trailing SSE event
--- fixture: openai/moderation-incomplete-event.sse
--- buffered: 1
--- response_body
status: 200
query_security_check: 1 / hello
response_security_check: nil / nil
text: kill you
done events: 0
--- error_log
dropping incomplete stream frame at EOF
