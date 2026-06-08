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

run_tests();

__DATA__

=== TEST 1: effective_request_for_cache applies model_options override
--- config
    location /t {
        content_by_lua_block {
            local base = require("apisix.plugins.ai-proxy.base")

            -- Build a forged ctx with a pre-parsed body so we bypass ngx.req reading.
            -- get_json_request_body_table() uses ngx.ctx.api_ctx._request_body_table
            -- as its cache; injecting it directly avoids the I/O path.
            local client_body = {
                model    = "client-model",
                messages = {{ role = "user", content = "hello" }},
            }

            local ctx = {
                var = {},
                -- Pre-populate the parsed-body cache (CONTENT_TYPE_JSON = "application/json")
                _request_body_table = client_body,
                _request_body_type  = "application/json",
                picked_ai_instance = {
                    provider = "openai",
                    options   = { model = "forced-model" },
                },
                ai_client_protocol = "openai-chat",
                ai_target_protocol = "openai-chat",
            }
            ngx.ctx.api_ctx = ctx

            local eff = base.effective_request_for_cache(ctx)
            if not eff then
                ngx.say("ERROR: eff is nil")
                return
            end

            -- override should have set model to forced-model
            ngx.say("eff.model=" .. tostring(eff.model))

            -- the original parsed body (the cached table itself) should be unchanged
            ngx.say("orig.model=" .. tostring(client_body.model))
        }
    }
--- request
GET /t
--- response_body
eff.model=forced-model
orig.model=client-model



=== TEST 2: effective_request_for_cache with no picked_ai_instance returns client body unchanged
--- config
    location /t {
        content_by_lua_block {
            local base = require("apisix.plugins.ai-proxy.base")

            local client_body = {
                model    = "my-model",
                messages = {{ role = "user", content = "hi" }},
            }

            local ctx = {
                var = {},
                _request_body_table = client_body,
                _request_body_type  = "application/json",
                ai_client_protocol  = "openai-chat",
                ai_target_protocol  = "openai-chat",
            }
            ngx.ctx.api_ctx = ctx

            local eff = base.effective_request_for_cache(ctx)
            if not eff then
                ngx.say("ERROR: eff is nil")
                return
            end
            ngx.say("eff.model=" .. tostring(eff.model))
        }
    }
--- request
GET /t
--- response_body
eff.model=my-model



=== TEST 3: effective_request_for_cache is cached on ctx (idempotent)
--- config
    location /t {
        content_by_lua_block {
            local base = require("apisix.plugins.ai-proxy.base")

            local client_body = {
                model    = "original",
                messages = {{ role = "user", content = "x" }},
            }

            local ctx = {
                var = {},
                _request_body_table = client_body,
                _request_body_type  = "application/json",
                picked_ai_instance = {
                    provider = "openai",
                    options   = { model = "cached-model" },
                },
                ai_client_protocol = "openai-chat",
                ai_target_protocol = "openai-chat",
            }
            ngx.ctx.api_ctx = ctx

            local eff1 = base.effective_request_for_cache(ctx)
            local eff2 = base.effective_request_for_cache(ctx)
            ngx.say(eff1 == eff2 and "SAME_OBJECT" or "different")
        }
    }
--- request
GET /t
--- response_body
SAME_OBJECT
