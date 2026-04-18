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

    # Mock upstream: slow SSE server that streams chunks until the connection
    # is closed, tracking the final chunk count in the "test" shared dict.
    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name slow_openai_sse;
            listen 7750;

            default_type 'text/event-stream';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.header["Content-Type"] = "text/event-stream"
                    local dict = ngx.shared["test"]
                    dict:set("upstream_chunks", 0)
                    -- Stream up to 2000 chunks with 30ms sleep between each.
                    -- The proxy should abort well before this completes when
                    -- the client disconnects.
                    for i = 1, 2000 do
                        local ok, err = ngx.print(
                            'data: {"id":"chatcmpl-1","object":'
                            .. '"chat.completion.chunk","choices":[{"delta":'
                            .. '{"content":"tok"},"index":0,'
                            .. '"finish_reason":null}],"usage":null}\\n\\n')
                        if not ok then
                            return
                        end
                        local flush_ok = ngx.flush(true)
                        if not flush_ok then
                            return
                        end
                        dict:set("upstream_chunks", i)
                        ngx.sleep(0.03)
                    end
                }
            }

            -- Probe endpoint to read the current chunk count.
            location /chunks {
                content_by_lua_block {
                    local dict = ngx.shared["test"]
                    ngx.say(dict:get("upstream_chunks") or 0)
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});


run_tests();

__DATA__

=== TEST 1: set route for client disconnect test
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
                                "model": "gpt-4",
                                "stream": true
                            },
                            "override": {
                                "endpoint": "http://localhost:7750"
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



=== TEST 2: client disconnect aborts upstream read early
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
                ngx.say("connect failed: ", err)
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
                ngx.say("request failed: ", err)
                return
            end

            -- Read exactly 3 chunks then close the connection abruptly.
            for i = 1, 3 do
                local chunk, rerr = res.body_reader()
                if rerr or not chunk then
                    ngx.status = 500
                    ngx.say("unexpected end of stream at chunk ", i, ": ", rerr)
                    return
                end
            end
            httpc:close()

            -- Allow time for the proxy to detect the disconnect and stop
            -- feeding the upstream connection, then capture the chunk count.
            ngx.sleep(0.3)

            -- Read chunk count from the mock upstream's probe endpoint.
            local probe = http.new()
            ok, err = probe:connect({ scheme = "http", host = "localhost", port = 7750 })
            if not ok then
                ngx.status = 500
                ngx.say("probe connect failed: ", err)
                return
            end
            local probe_res, probe_err = probe:request({
                method = "GET",
                path = "/chunks",
                headers = { Host = "localhost" },
            })
            if not probe_res then
                ngx.status = 500
                ngx.say("probe request failed: ", probe_err)
                return
            end
            local count_str = probe_res:read_body()
            probe:close()

            local count = tonumber(count_str) or 0
            -- Without the fix, the upstream would have produced hundreds of
            -- chunks by now. With the fix it stops shortly after disconnect.
            -- We expect well under 50 chunks after only 0.3s budget.
            if count > 50 then
                ngx.status = 500
                ngx.say("upstream was not aborted promptly, chunks: ", count)
                return
            end
            ngx.say("ok, upstream aborted after ~", count, " chunks")
        }
    }
--- response_body_like
^ok, upstream aborted after ~\d+ chunks$
--- error_log
client disconnected during AI streaming
