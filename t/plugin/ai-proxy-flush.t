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

log_level("debug");
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
            server_name mock_openai_sse;
            listen 7751;

            default_type 'text/event-stream';

            location /v1/chat/completions {
                content_by_lua_block {
                    local args = ngx.req.get_uri_args()
                    local delay = args["delay"]
                    ngx.header["Content-Type"] = "text/event-stream"
                    local events = {
                        'data: {"id":"1","choices":[{"delta":{"role":"assistant","content":""},"index":0,"finish_reason":null}]}\\n\\n',
                        'data: {"id":"1","choices":[{"delta":{"content":"Hello"},"index":0,"finish_reason":null}]}\\n\\n',
                        'data: {"id":"1","choices":[{"delta":{"content":" world"},"index":0,"finish_reason":null}]}\\n\\n',
                        'data: {"id":"1","choices":[{"delta":{},"index":0,"finish_reason":"stop"}]}\\n\\n',
                        'data: [DONE]\\n\\n',
                    }
                    for _, ev in ipairs(events) do
                        ngx.print(ev)
                        ngx.flush(true)
                        if delay then
                            ngx.sleep(0.05)
                        end
                    end
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: create route with streaming_flush_interval_ms=0 (per-chunk sync flush)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/flush-default",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4",
                                "stream": true
                            },
                            "override": {
                                "endpoint": "http://localhost:7751/v1/chat/completions?delay=true"
                            },
                            "ssl_verify": false,
                            "streaming_flush_interval_ms": 0
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



=== TEST 2: interval_ms=0 (per-chunk flush) - flush_thread must NOT appear, sync flush per chunk
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
                ngx.say("connect: " .. err)
                return
            end

            local res, err = httpc:request({
                method = "POST",
                path = "/flush-default",
                headers = { ["Content-Type"] = "application/json" },
                body = '{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}',
            })
            if not res then
                ngx.status = 500
                ngx.say("request: " .. err)
                return
            end

            local body = res:read_body()
            if body:find("Hello", 1, true) and
               body:find(" world", 1, true) and
               body:find("[DONE]", 1, true) then
                ngx.say("ok")
            else
                ngx.say("FAIL: unexpected body: " .. body:sub(1, 500))
            end
        }
    }
--- response_body
ok
--- no_error_log
ai-proxy: flush_thread periodic flush
--- grep_error_log eval
qr/lua_response_filter: flushing chunk to client/
--- grep_error_log_out
lua_response_filter: flushing chunk to client
lua_response_filter: flushing chunk to client
lua_response_filter: flushing chunk to client
lua_response_filter: flushing chunk to client
lua_response_filter: flushing chunk to client



=== TEST 3: create route with streaming_flush_interval_ms=50 (background thread flush)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/flush-interval",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer test-key"
                                }
                            },
                            "options": {
                                "model": "gpt-4",
                                "stream": true
                            },
                            "override": {
                                "endpoint": "http://localhost:7751/v1/chat/completions?delay=true"
                            },
                            "ssl_verify": false,
                            "streaming_flush_interval_ms": 50
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



=== TEST 4: interval_ms=50 (background thread flush) - flush_thread log must appear
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
                ngx.say("connect: " .. err)
                return
            end

            local res, err = httpc:request({
                method = "POST",
                path = "/flush-interval",
                headers = { ["Content-Type"] = "application/json" },
                body = '{"messages":[{"role":"user","content":"hi"}],"model":"gpt-4","stream":true}',
            })
            if not res then
                ngx.status = 500
                ngx.say("request: " .. err)
                return
            end

            local body = res:read_body()
            if body:find("Hello", 1, true) and
               body:find(" world", 1, true) and
               body:find("[DONE]", 1, true) then
                ngx.say("ok")
            else
                ngx.say("FAIL: unexpected body: " .. body:sub(1, 500))
            end
        }
    }
--- response_body
ok
--- error_log
ai-proxy: flush_thread periodic flush
--- no_error_log
lua_response_filter: flushing chunk to client



=== TEST 5: streaming_flush_interval_ms schema rejects negative value
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local ok, err = plugin.check_schema({
                provider = "openai",
                auth = { header = { Authorization = "Bearer x" } },
                options = { model = "gpt-4" },
                streaming_flush_interval_ms = -1,
            })
            if ok then
                ngx.say("should have failed")
            else
                ngx.say("rejected: " .. tostring(err))
            end
        }
    }
--- response_body_like
rejected: .*



=== TEST 6: streaming_flush_interval_ms=0 is accepted (disables background thread)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local ok, err = plugin.check_schema({
                provider = "openai",
                auth = { header = { Authorization = "Bearer x" } },
                options = { model = "gpt-4" },
                streaming_flush_interval_ms = 0,
            })
            if ok then
                ngx.say("ok")
            else
                ngx.say("FAIL: " .. tostring(err))
            end
        }
    }
--- response_body
ok



=== TEST 7: omitting streaming_flush_interval_ms applies default value of 10
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-proxy")
            local conf = {
                provider = "openai",
                auth = { header = { Authorization = "Bearer x" } },
                options = { model = "gpt-4" },
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say("FAIL: " .. tostring(err))
                return
            end
            ngx.say(conf.streaming_flush_interval_ms)
        }
    }
--- response_body
10
