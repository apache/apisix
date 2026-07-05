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
  - ai-proxy
  - ai-cache
_EOC_
    if (!defined $block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", $user_yaml_config);
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 6724;
        default_type 'text/event-stream';

        location /v1/embeddings {
            content_by_lua_block { require("lib.ai_cache_mock").embeddings() }
        }

        location /v1/chat/completions-truncated {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/event-stream"
                ngx.print('data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hel"},"finish_reason":null}]}\\n\\n')
                ngx.flush(true)
            }
        }

        location /v1/chat/completions-runaway {
            content_by_lua_block {
                ngx.header["Content-Type"] = "text/event-stream"
                for i = 1, 40 do
                    ngx.print('data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"tokentokentokentokentoken"},"finish_reason":null}]}\\n\\n')
                    ngx.flush(true)
                end
                ngx.print('data: [DONE]\\n\\n')
                ngx.flush(true)
            }
        }

        # An SSE stream carried under a non-success status (HTTP 400) that still
        # ends with a valid [DONE] sentinel: ai-proxy's 429/5xx gate does not catch
        # 400, so without status propagation this would stream as 200 and get
        # cached as a successful HIT.
        location /v1/chat/completions-error-sse {
            content_by_lua_block {
                ngx.status = 400
                ngx.header["Content-Type"] = "text/event-stream"
                ngx.print('data: {"error":{"message":"bad request"}}\\n\\n')
                ngx.print('data: [DONE]\\n\\n')
                ngx.flush(true)
            }
        }

        location /v1/chat/completions-flaky-once {
            content_by_lua_block { require("lib.ai_cache_mock").chat_flaky_once() }
        }
    }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: folding stream into the fingerprint isolates stream from non-stream
--- config
    location /t {
        content_by_lua_block {
            local key = require("apisix.plugins.ai-cache.key")
            local ctx = {
                picked_ai_instance = { provider = "openai", options = { model = "gpt-4" } },
                ai_client_protocol = "openai-chat",
                var = { route_id = "1" },
            }
            local base   = { messages = {{ role = "user", content = "hi" }}, model = "gpt-4" }
            local stream = { messages = {{ role = "user", content = "hi" }}, model = "gpt-4", stream = true }
            local fp_a = key.fingerprint(ctx, base)
            local fp_b = key.fingerprint(ctx, stream)
            local conf = { cache_key = {} }
            local pt_a = key.partition(conf, ctx, base, nil)
            local pt_b = key.partition(conf, ctx, stream, nil)
            ngx.say((fp_a ~= fp_b) and (pt_a ~= pt_b) and "ISOLATED" or "COLLISION")
        }
    }
--- response_body
ISOLATED



=== TEST 2: stream_completed is protocol-aware (openai [DONE], anthropic message_stop) and immune to a [DONE] substring
--- config
    location /t {
        content_by_lua_block {
            local stream = require("apisix.plugins.ai-cache.stream")
            local octx = { ai_client_protocol = "openai-chat", var = {} }
            local actx = { ai_client_protocol = "anthropic-messages", var = {} }
            local complete   = 'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n' .. 'data: [DONE]\n\n'
            local truncated  = 'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n'
            -- a "[DONE]" substring inside content must NOT count as completion
            local fake_done  = 'data: {"choices":[{"delta":{"content":"[DONE]"}}]}\n\n'
            -- anthropic's terminal sentinel is the message_stop event, not [DONE]
            local anthropic_done      = 'event: message_stop\ndata: {}\n\n'
            local anthropic_truncated = 'event: message_start\ndata: {}\n\n'
            -- a terminal frame cut off mid-data (no closing blank line) must NOT
            -- count as complete, even though its event TYPE parses as message_stop
            local anthropic_partial   = 'event: message_start\ndata: {}\n\n'
                                        .. 'event: message_stop\ndata: {"ty'
            -- spec-legal comment/heartbeat frames AFTER the terminal event must
            -- not hide it (upstreams/proxies that ping after [DONE])
            local keepalive_after_done = complete .. ': keepalive\n\n'
            -- ...but a comment truncated mid-write is not a frame boundary
            local keepalive_truncated  = complete .. ': keepal'
            ngx.say(table.concat({
                tostring(stream.stream_completed(octx, complete)),
                tostring(stream.stream_completed(octx, truncated)),
                tostring(stream.stream_completed(octx, fake_done)),
                tostring(stream.stream_completed(actx, anthropic_done)),
                tostring(stream.stream_completed(actx, anthropic_truncated)),
                tostring(stream.stream_completed(actx, anthropic_partial)),
                tostring(stream.stream_completed(octx, keepalive_after_done)),
                tostring(stream.stream_completed(octx, keepalive_truncated)),
            }, ","))
        }
    }
--- response_body
true,false,false,true,false,false,true,false



=== TEST 3: capture_format tags a capture by wire framing and completeness
--- config
    location /t {
        content_by_lua_block {
            local stream = require("apisix.plugins.ai-cache.stream")
            -- framing is stamped by ai-providers parse_streaming_response;
            -- absent means the response was a single-shot (non-streaming) body
            local plain = { var = {} }
            local sse_ctx = { ai_stream_framing = "sse",
                              ai_client_protocol = "openai-chat", var = {} }
            local bin_ctx = { ai_stream_framing = "aws-eventstream",
                              ai_client_protocol = "bedrock-converse", var = {} }
            local done = 'data: {"choices":[]}\n\ndata: [DONE]\n\n'
            ngx.say(table.concat({
                stream.capture_format(plain, '{"id":"1"}'),          -- json
                stream.capture_format(sse_ctx, done),                -- sse
                tostring(stream.capture_format(sse_ctx, 'data: {}\n\n')), -- nil: incomplete
                tostring(stream.capture_format(bin_ctx, done)),      -- nil: binary framing
                tostring(stream.capture_format(plain, done)),        -- nil: mislabeled sse
                tostring(stream.capture_format(plain, ': ping\ndata: {}\n\n')), -- nil: comment first line
                tostring(stream.capturable(plain)),                  -- true
                tostring(stream.capturable(sse_ctx)),                -- true
                tostring(stream.capturable(bin_ctx)),                -- false
                -- access-time prediction from the picked provider
                tostring(stream.provider_capturable({provider = "openai"})),  -- true
                tostring(stream.provider_capturable({provider = "bedrock"})), -- false
            }, ","))
        }
    }
--- response_body
json,sse,nil,nil,nil,nil,true,true,false,true,false



=== TEST 4: set a streaming route (ai-proxy stream + ai-cache), pointed at the :1980 SSE fixture
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/stream",
                "plugins": {
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer test" } },
                        "options": { "model": "gpt-4", "stream": true },
                        "override": { "endpoint": "http://127.0.0.1:1980" }
                    },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379 }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: a cold streaming request is a MISS and is streamed from upstream
--- request
POST /stream
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: MISS
Content-Type: text/event-stream
--- response_body_like
data: \[DONE\]
--- wait: 0.5



=== TEST 6: an identical streaming request is a HIT, replayed as a valid text/event-stream
--- request
POST /stream
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Age: \d+
Content-Type: text/event-stream
--- response_body_like
data: \[DONE\]



=== TEST 7: set a route whose upstream truncates the stream (no terminal [DONE])
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/stream-trunc",
                "plugins": {
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer test" } },
                        "options": { "model": "gpt-4", "stream": true },
                        "override": { "endpoint": "http://127.0.0.1:6724/v1/chat/completions-truncated" }
                    },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379 }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: the truncated stream is a MISS and is NOT written back (no terminal sentinel)
--- request
POST /stream-trunc
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- response_headers_like
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 9: an identical request is STILL a MISS -- the truncated stream was never cached
--- request
POST /stream-trunc
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- response_headers_like
X-AI-Cache-Status: MISS



=== TEST 10: set a route that FORCES streaming via options.stream (client body has none)
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/forced-stream",
                "plugins": {
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer test" } },
                        "options": { "model": "gpt-4", "stream": true },
                        "override": { "endpoint": "http://127.0.0.1:1980" }
                    },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379 }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: options.stream makes the response SSE though request_type is ai_chat -- MISS, streamed
--- request
POST /forced-stream
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4"}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: MISS
Content-Type: text/event-stream
--- wait: 0.5



=== TEST 12: the forced-stream entry replays as text/event-stream (format follows the response, not request_type)
--- request
POST /forced-stream
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4"}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: HIT
Content-Type: text/event-stream
--- response_body_like
data: \[DONE\]



=== TEST 13: set a non-streaming and a streaming route that share one cache space
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/iso-json", "plugins": {
                    "ai-proxy": { "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer test" } },
                        "options": { "model": "gpt-4" },
                        "override": { "endpoint": "http://127.0.0.1:1980" } },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379,
                        "cache_key": { "share_across_routes": true } } } }]])
            if code >= 300 then ngx.status = code; ngx.say(code); return end
            code = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "uri": "/iso-sse", "plugins": {
                    "ai-proxy": { "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer test" } },
                        "options": { "model": "gpt-4", "stream": true },
                        "override": { "endpoint": "http://127.0.0.1:1980" } },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379,
                        "cache_key": { "share_across_routes": true } } } }]])
            ngx.say(code < 300 and "passed" or code)
        }
    }
--- response_body
passed



=== TEST 14: prime the non-streaming (JSON) entry
--- request
POST /iso-json
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4"}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers_like
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 15: the SAME prompt as a stream is a MISS (never serves the JSON entry) and is SSE
--- request
POST /iso-sse
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: MISS
Content-Type: text/event-stream
--- wait: 0.5



=== TEST 16: reverse isolation -- flush and reuse the shared routes from TEST 13
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            ngx.say("flushed")
        }
    }
--- response_body
flushed



=== TEST 17: prime the streaming (SSE) entry
--- request
POST /iso-sse
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 18: the SAME prompt non-streamed is a MISS (never serves the SSE entry) and is JSON
--- request
POST /iso-json
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4"}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers_like
X-AI-Cache-Status: MISS
Content-Type: application/json



=== TEST 19: set a runaway streaming route with a low max_response_bytes
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/stream-runaway",
                "plugins": {
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer test" } },
                        "options": { "model": "gpt-4", "stream": true },
                        "max_response_bytes": 512,
                        "override": { "endpoint": "http://127.0.0.1:6724/v1/chat/completions-runaway" }
                    },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379 }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 20: max_response_bytes aborts the stream (llm_request_done=true) before [DONE]
--- request
POST /stream-runaway
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- error_log
aborting AI stream: max_response_bytes exceeded
--- wait: 0.5



=== TEST 21: the aborted stream was NOT cached -- an identical request is STILL a MISS
--- request
POST /stream-runaway
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- response_headers_like
X-AI-Cache-Status: MISS



=== TEST 22: set a semantic (exact+semantic) streaming route
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/sse-sem", "plugins": {
                    "ai-proxy": { "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer test-key" } },
                        "options": { "model": "gpt-4o", "stream": true },
                        "override": { "endpoint": "http://127.0.0.1:1980" } },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379,
                        "layers": ["exact","semantic"],
                        "semantic": {
                            "similarity_threshold": 0.9,
                            "embedding": { "openai": {
                                "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                "model": "text-embedding-3-small", "api_key": "test-key" } },
                            "vector_search": { "redis": {} } } } } }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 23: a cold streaming prompt is a semantic MISS
--- request
POST /sse-sem
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}],"stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: MISS
--- wait: 0.6



=== TEST 24: a paraphrased streaming prompt is a semantic (L2) HIT, replayed as SSE
--- request
POST /sse-sem
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital city of France?"}],"stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: HIT
X-AI-Cache-Similarity: 0\.92\d\d
Content-Type: text/event-stream
--- response_body_like
data: \[DONE\]



=== TEST 25: set a streaming and a non-streaming semantic route over one shared index
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local function sem(uri, stream_opt)
                return [[{
                    "uri": "]] .. uri .. [[", "plugins": {
                        "ai-proxy": { "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer test-key" } },
                            "options": { "model": "gpt-4o"]] .. stream_opt .. [[ },
                            "override": { "endpoint": "http://127.0.0.1:1980" } },
                        "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379,
                            "cache_key": { "share_across_routes": true },
                            "layers": ["exact","semantic"],
                            "semantic": {
                                "similarity_threshold": 0.9,
                                "embedding": { "openai": {
                                    "endpoint": "http://127.0.0.1:6724/v1/embeddings",
                                    "model": "text-embedding-3-small", "api_key": "test-key" } },
                                "vector_search": { "redis": { "index": "ai-cache-iso" } } } } } }]]
            end
            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, sem("/sse-sem2", ', "stream": true'))
            if code >= 300 then ngx.status = code; ngx.say(code); return end
            code = t('/apisix/admin/routes/2', ngx.HTTP_PUT, sem("/json-sem2", ""))
            ngx.say(code < 300 and "passed" or code)
        }
    }
--- response_body
passed



=== TEST 26: prime a STREAM L2 doc
--- request
POST /sse-sem2
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}],"stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: MISS
--- wait: 0.6



=== TEST 27: a non-stream paraphrase MISSES (the stream doc is in a different partition)
--- request
POST /json-sem2
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital city of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers_like
X-AI-Cache-Status: MISS
--- wait: 0.6



=== TEST 28: a non-stream paraphrase of TEST 27 HITs L2 -- L2 works for non-stream, stream doc stayed isolated
--- request
POST /json-sem2
{"model":"gpt-4o","messages":[{"role":"user","content":"What is the capital of France?"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers_like
X-AI-Cache-Status: HIT
Content-Type: application/json



=== TEST 29: buffered/one-write upstream + low max_response_bytes (limit trips AFTER [DONE] is buffered)
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            -- The shared :1980 loader sends the whole .sse fixture (826 bytes,
            -- ending with [DONE]) in ONE write, so the terminal sentinel is
            -- already in the captured buffer when max_response_bytes (256) trips.
            -- stream_completed() alone would treat this as a cacheable complete
            -- stream; ctx.ai_stream_aborted must veto the write.
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/stream-onewrite",
                "plugins": {
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer test" } },
                        "options": { "model": "gpt-4", "stream": true },
                        "max_response_bytes": 256,
                        "override": { "endpoint": "http://127.0.0.1:1980" }
                    },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379 }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 30: the one-write stream carries [DONE] yet max_response_bytes still aborts it
--- request
POST /stream-onewrite
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- error_log
aborting AI stream: max_response_bytes exceeded
--- wait: 0.5



=== TEST 31: the limit-aborted stream was NOT cached despite the buffered [DONE] -- identical request STILL a MISS
--- request
POST /stream-onewrite
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 32: stream folds by `== true` (mirrors is_streaming); false/omitted/null/0 share ONE key, only true isolates
--- config
    location /t {
        content_by_lua_block {
            local key  = require("apisix.plugins.ai-cache.key")
            local null = require("cjson").null   -- what cjson.decode gives for JSON null
            local ctx = {
                picked_ai_instance = { provider = "openai", options = { model = "gpt-4" } },
                ai_client_protocol = "openai-chat",
                var = { route_id = "1" },
            }
            local msgs = {{ role = "user", content = "hi" }}
            local conf = { cache_key = {} }
            local function fp(stream_val)
                local body = { messages = msgs, model = "gpt-4" }
                if stream_val ~= nil then body.stream = stream_val end
                return key.fingerprint(ctx, body)
            end
            -- ai-proxy is_streaming does `body.stream == true`, so null (truthy
            -- userdata) and 0 (truthy in Lua) are NON-streaming and must not split
            -- off from omitted/false, nor collide with a real streaming request.
            local base = fp(nil)
            local non_stream = (fp(false) == base) and (fp(null) == base) and (fp(0) == base)
            ngx.say((non_stream and fp(true) ~= base) and "CANONICAL" or "FRAGMENTED")
        }
    }
--- response_body
CANONICAL



=== TEST 33: set a streaming route whose upstream returns HTTP 400 SSE ending in [DONE]
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/stream-error-sse",
                "plugins": {
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer test" } },
                        "options": { "model": "gpt-4", "stream": true },
                        "override": { "endpoint": "http://127.0.0.1:6724/v1/chat/completions-error-sse" }
                    },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379 }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 34: the 400 upstream status is propagated (not served as 200) and the error stream is a MISS
--- request
POST /stream-error-sse
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- error_code: 400
--- response_headers_like
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 35: the 400 error stream was NOT cached despite the [DONE] sentinel -- identical request STILL a MISS (400)
--- request
POST /stream-error-sse
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- error_code: 400
--- response_headers_like
X-AI-Cache-Status: MISS
--- wait: 0.5



=== TEST 36: set an ai-proxy-multi route on the flaky-once upstream (weight-0 spare keeps the re-pick on the SAME instance)
--- extra_yaml_config
plugins:
  - ai-proxy-multi
  - ai-cache
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/stream-retry",
                "plugins": {
                    "ai-proxy-multi": {
                        "fallback_strategy": ["http_5xx"],
                        "timeout": 1000,
                        "ssl_verify": false,
                        "instances": [
                            {"name":"flaky","provider":"openai","weight":1,
                             "auth":{"header":{"Authorization":"Bearer test"}},
                             "options":{"model":"gpt-4","stream":true},
                             "override":{"endpoint":"http://127.0.0.1:6724/v1/chat/completions-flaky-once"}},
                            {"name":"spare","provider":"openai","weight":0,
                             "auth":{"header":{"Authorization":"Bearer test"}},
                             "options":{"model":"gpt-4","stream":true},
                             "override":{"endpoint":"http://127.0.0.1:6724/v1/chat/completions-flaky-once"}}
                        ]
                    },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379 }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 37: attempt 1 dies before the first byte, the retry re-picks the SAME instance and streams to [DONE]
--- extra_yaml_config
plugins:
  - ai-proxy-multi
  - ai-cache
--- request
POST /stream-retry
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: MISS
Content-Type: text/event-stream
--- response_body_like
data: \[DONE\]
--- error_log
failed to read response chunk
falling back to flaky
--- timeout: 5
--- wait: 0.5



=== TEST 38: the retried stream WAS cached -- attempt 1's stale abort flag no longer vetoes the write
--- extra_yaml_config
plugins:
  - ai-proxy-multi
  - ai-cache
--- request
POST /stream-retry
{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers_like
X-AI-Cache-Status: HIT
Content-Type: text/event-stream
--- response_body_like
data: \[DONE\]



=== TEST 39: set a bedrock streaming route (aws-eventstream framing) with ai-cache
--- config
    location /t {
        content_by_lua_block {
            require("lib.test_redis").flush_port("127.0.0.1", 6379)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/bedrock-stream/converse",
                "plugins": {
                    "ai-proxy": {
                        "provider": "bedrock",
                        "auth": {
                            "aws": {
                                "access_key_id": "AKIAIOSFODNN7EXAMPLE",
                                "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                            }
                        },
                        "provider_conf": { "region": "us-east-1" },
                        "options": { "model": "anthropic.claude-3-5-sonnet-20241022-v2:0" },
                        "override": { "endpoint": "http://127.0.0.1:1980" },
                        "ssl_verify": false
                    },
                    "ai-cache": { "redis_host": "127.0.0.1", "redis_port": 6379 }
                }
            }]])
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 40: a binary-framed stream BYPASSes the lookup (could never be written back) and flows through intact
--- main_config
    env AWS_EC2_METADATA_DISABLED=true;
--- request
POST /bedrock-stream/converse
{"stream":true,"messages":[{"role":"user","content":[{"text":"Say hi"}]}]}
--- error_code: 200
--- response_headers
X-AI-Cache-Status: BYPASS
Content-Type: application/vnd.amazon.eventstream
--- response_body eval
qr/messageStart.*contentBlockDelta.*messageStop/s
--- wait: 0.5



=== TEST 41: the bypassed stream was never cached -- identical request STILL a BYPASS
--- main_config
    env AWS_EC2_METADATA_DISABLED=true;
--- request
POST /bedrock-stream/converse
{"stream":true,"messages":[{"role":"user","content":[{"text":"Say hi"}]}]}
--- error_code: 200
--- response_headers
X-AI-Cache-Status: BYPASS
Content-Type: application/vnd.amazon.eventstream



=== TEST 42: a NON-stream request on the same bedrock route is a MISS -- the bypass is stream-scoped
--- main_config
    env AWS_EC2_METADATA_DISABLED=true;
--- request
POST /bedrock-stream/converse
{"messages":[{"role":"user","content":[{"text":"What is 1+1?"}]}]}
--- error_code: 200
--- response_headers
X-AI-Cache-Status: MISS
--- response_body eval
qr/"text"\s*:\s*"Hello!"/
