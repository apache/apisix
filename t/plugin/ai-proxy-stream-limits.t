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

    # Shared mock upstream: a runaway SSE server that streams OpenAI chat
    # completion chunks indefinitely and never sends "[DONE]".
    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name runaway_openai_sse;
            listen 7740;

            default_type 'text/event-stream';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.header["Content-Type"] = "text/event-stream"
                    -- Bound by an upper limit so test-nginx never hangs even
                    -- if the plugin safeguard misfires; in practice the plugin
                    -- should abort long before this completes.
                    for i = 1, 10000 do
                        ngx.print('data: {"id":"chatcmpl-1","object":'
                            .. '"chat.completion.chunk","choices":[{"delta":'
                            .. '{"content":"token"},"index":0,'
                            .. '"finish_reason":null}],"usage":null}\\n\\n')
                        ngx.flush(true)
                        ngx.sleep(0.01)
                    end
                    -- Deliberately never send [DONE].
                }
            }

            location /v1/oversized {
                content_by_lua_block {
                    -- Advertise a large Content-Length to trigger the
                    -- non-streaming max_response_bytes pre-check.
                    ngx.header["Content-Type"] = "application/json"
                    ngx.header["Content-Length"] = "100000"
                    ngx.print(string.rep("x", 100000))
                }
            }

            location /v1/oversized_chunked {
                content_by_lua_block {
                    -- No Content-Length; chunked transfer. Exercises the
                    -- incremental body_reader enforcement in parse_response.
                    ngx.header["Content-Type"] = "application/json"
                    -- Write in chunks so nginx uses chunked transfer-encoding.
                    for i = 1, 10 do
                        ngx.print(string.rep("x", 10000))
                        ngx.flush(true)
                    end
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});


run_tests();

__DATA__

=== TEST 1: set route with max_stream_duration_ms against runaway SSE upstream
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
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-3.5-turbo",
                                "stream": true
                            },
                            "max_stream_duration_ms": 500,
                            "override": {
                                "endpoint": "http://localhost:7740"
                            },
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



=== TEST 2: max_stream_duration_ms aborts the stream within budget
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

            local start = ngx.now()
            local res, err = httpc:request({
                method = "POST",
                headers = { ["Content-Type"] = "application/json" },
                path = "/anything",
                body = [[{"messages": [{"role": "user", "content": "hi"}]}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            -- Drain whatever the gateway is willing to send; it must end
            -- within a few seconds because the plugin will close the
            -- upstream after ~500ms.
            local chunks = 0
            while true do
                local chunk, rerr = res.body_reader()
                if rerr or not chunk then break end
                chunks = chunks + 1
            end
            local elapsed = ngx.now() - start

            -- The test mock would run for ~100s without the safeguard;
            -- with the safeguard the whole exchange must finish in well
            -- under 5s.
            if elapsed >= 5 then
                ngx.status = 500
                ngx.say("stream did not abort in time: ", elapsed, "s")
                return
            end
            if chunks == 0 then
                ngx.status = 500
                ngx.say("no chunks received")
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
ok
--- error_log
aborting AI stream: max_stream_duration_ms exceeded



=== TEST 3: set route with max_response_bytes against runaway SSE upstream
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
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-3.5-turbo",
                                "stream": true
                            },
                            "max_response_bytes": 2048,
                            "override": {
                                "endpoint": "http://localhost:7740"
                            },
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



=== TEST 4: max_response_bytes aborts the stream after byte budget
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
                headers = { ["Content-Type"] = "application/json" },
                path = "/anything",
                body = [[{"messages": [{"role": "user", "content": "hi"}]}]],
            })
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local total = 0
            local start = ngx.now()
            while true do
                local chunk, rerr = res.body_reader()
                if rerr or not chunk then break end
                total = total + #chunk
            end
            local elapsed = ngx.now() - start

            if elapsed >= 5 then
                ngx.status = 500
                ngx.say("stream did not abort in time: ", elapsed, "s")
                return
            end
            if total == 0 then
                ngx.status = 500
                ngx.say("no bytes received")
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
ok
--- error_log
aborting AI stream: max_response_bytes exceeded



=== TEST 5: set route for non-streaming oversized Content-Length
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
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-3.5-turbo"
                            },
                            "max_response_bytes": 1024,
                            "override": {
                                "endpoint": "http://localhost:7740/v1/oversized"
                            },
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



=== TEST 6: non-streaming response with oversized Content-Length is rejected
--- request
POST /anything
{"messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
--- error_code: 502
--- error_log
aborting AI response: Content-Length 100000 exceeds max_response_bytes 1024



=== TEST 7: schema rejects non-positive max_stream_duration_ms
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
                            "auth": {"header": {"Authorization": "Bearer x"}},
                            "options": {"model": "gpt-3.5-turbo"},
                            "max_stream_duration_ms": 0
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like eval
qr/max_stream_duration_ms/



=== TEST 8: set route with max_response_bytes against chunked (no-CL) upstream
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
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-3.5-turbo"
                            },
                            "max_response_bytes": 1024,
                            "override": {
                                "endpoint": "http://localhost:7740/v1/oversized_chunked"
                            },
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



=== TEST 9: chunked non-streaming response exceeding max_response_bytes returns 502
--- request
POST /anything
{"messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
--- error_code: 502
--- error_log
aborting AI response: body size exceeds max_response_bytes 1024
