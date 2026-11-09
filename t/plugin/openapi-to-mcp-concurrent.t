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

# Four workers, so the POST that carries a message and the GET that streams the
# answer land on different processes as a matter of course.
workers(4);

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request && !$block->exec) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 11480;

        location /openapi.json {
            content_by_lua_block {
                local core = require("apisix.core")
                ngx.header["Content-Type"] = "application/json"
                ngx.say(core.json.encode({
                    openapi = "3.0.0",
                    info = { title = "Demo", version = "1.0.0" },
                    paths = { ["/pet/{petId}"] = { get = {
                        operationId = "getPet",
                        summary = "Get a pet",
                        parameters = {
                            { name = "petId", ["in"] = "path", required = true,
                              schema = { type = "integer" } },
                        },
                    } } },
                }))
            }
        }

        location / {
            content_by_lua_block {
                local core = require("apisix.core")
                ngx.header["Content-Type"] = "application/json"
                ngx.say(core.json.encode({ seen_path = ngx.var.request_uri }))
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: one route per transport
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp-concurrent-sse", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11480",
                    openapi_url = "http://127.0.0.1:11480/openapi.json",
                } },
                { 2, "/mcp-concurrent-http", {
                    transport = "streamable_http",
                    base_url = "http://127.0.0.1:11480",
                    openapi_url = "http://127.0.0.1:11480/openapi.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 2: sixteen requests in flight at once, on both transports
--- timeout: 120
--- max_size: 2048000
--- exec
python3 t/plugin/openapi_to_mcp_concurrent.py /mcp-concurrent-sse /mcp-concurrent-http 2>&1
--- response_body
0 problem(s) across 16 concurrent requests per transport



=== TEST 3: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            t('/apisix/admin/routes/2', ngx.HTTP_DELETE)
            ngx.say("cleaned")
        }
    }
--- response_body
cleaned
