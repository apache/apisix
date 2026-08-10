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

run_tests;

__DATA__

=== TEST 1: ai-proxy resolves phase timeout fallbacks at the transport call site
--- config
    location /t {
        content_by_lua_block {
            local provider_name = "apisix.plugins.ai-providers.timeout-capture"
            local transport_name = "apisix.plugins.ai-transport.http"
            local exporter_name = "apisix.plugins.prometheus.exporter"
            local sanitize_name = "apisix.utils.log-sanitize"
            local base_name = "apisix.plugins.ai-proxy.base"

            local saved = {}
            for _, name in ipairs({
                provider_name,
                transport_name,
                exporter_name,
                sanitize_name,
                base_name,
            }) do
                saved[name] = package.loaded[name]
            end

            local observed
            package.loaded[provider_name] = {
                capabilities = {
                    ["openai-chat"] = {
                        path = "/v1/chat/completions",
                        host = "127.0.0.1",
                    },
                },
                build_body = function(_, body)
                    return body, true
                end,
                build_request = function(_, _, body)
                    return {
                        method = "POST",
                        host = "127.0.0.1",
                        port = 80,
                        path = "/v1/chat/completions",
                        headers = {},
                        body = body,
                    }
                end,
            }
            package.loaded[transport_name] = {
                request = function(_, timeout)
                    observed = timeout
                    return nil, "captured timeout"
                end,
                handle_error = function()
                    return 504
                end,
            }
            package.loaded[exporter_name] = {
                inc_llm_active_connections = function() end,
            }
            package.loaded[sanitize_name] = {
                redact_params = function(params)
                    return params
                end,
            }
            package.loaded[base_name] = nil

            local base = require(base_name)
            local cases = {
                {name = "omitted", conf = {timeout = 900}},
                {name = "connect", conf = {timeout = 900, connect_timeout = 101}},
                {name = "send", conf = {timeout = 900, send_timeout = 202}},
                {name = "read", conf = {timeout = 900, read_timeout = 303}},
            }

            for _, case in ipairs(cases) do
                observed = nil
                local ctx = {
                    ai_client_protocol = "openai-chat",
                    picked_ai_instance = {
                        name = "capture",
                        provider = "timeout-capture",
                        options = {model = "gpt-4"},
                    },
                    var = {uri = "/t"},
                }

                ngx.ctx.api_ctx = ctx
                base.before_proxy(case.conf, ctx)
                if type(observed) == "number" then
                    ngx.say(case.name, ":number:", observed)
                else
                    ngx.say(case.name, ":table:",
                            observed.connect_timeout, ",",
                            observed.send_timeout, ",",
                            observed.read_timeout)
                end
            end
            ngx.ctx.api_ctx = nil

            for name, value in pairs(saved) do
                package.loaded[name] = value
            end
        }
    }
--- request
POST /t
{"model":"gpt-4","messages":[{"role":"user","content":"hello"}]}
--- more_headers
Content-Type: application/json
--- response_body
omitted:number:900
connect:table:101,900,900
send:table:900,202,900
read:table:900,900,303
