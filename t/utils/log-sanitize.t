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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: redact_params returns a raw table (not a delay_encode slot)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local log_sanitize = require("apisix.utils.log-sanitize")

            local redacted = log_sanitize.redact_params({
                method = "POST",
                scheme = "https",
                host = "api.openai.com",
                port = 443,
                path = "/v1/chat/completions",
                headers = {
                    ["Authorization"] = "Bearer sk-secret",
                    ["Content-Type"] = "application/json",
                },
            })

            -- a raw table has no __tostring metamethod and no wrapper fields
            ngx.say("has_tostring_mt: ", tostring(getmetatable(redacted) ~= nil
                                                  and getmetatable(redacted).__tostring ~= nil))
            ngx.say("authorization: ", redacted.headers["Authorization"])
            ngx.say("content_type: ", redacted.headers["Content-Type"])
        }
    }
--- response_body
has_tostring_mt: false
authorization: [REDACTED]
content_type: application/json



=== TEST 2: wrapping once in delay_encode logs the redacted JSON, not the wrapper
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local log_sanitize = require("apisix.utils.log-sanitize")

            -- mirrors the AI plugin call sites: one delay_encode at the call site
            local slot = core.json.delay_encode(log_sanitize.redact_params({
                method = "POST",
                host = "api.openai.com",
                headers = { ["api-key"] = "secret" },
            }), true)

            local decoded = core.json.decode(tostring(slot))
            ngx.say("api_key: ", decoded.headers["api-key"])
            ngx.say("host: ", decoded.host)
            -- if double-wrapped the output would be the {data=,force=} wrapper
            ngx.say("is_wrapper: ", tostring(decoded.data ~= nil))
        }
    }
--- response_body
api_key: [REDACTED]
host: api.openai.com
is_wrapper: false



=== TEST 3: redact_extra_opts strips auth and returns a raw table
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local log_sanitize = require("apisix.utils.log-sanitize")

            local opts = {
                model = "gpt-4",
                auth = { header = { ["Authorization"] = "Bearer sk-secret" } },
            }
            local redacted = log_sanitize.redact_extra_opts(opts)

            ngx.say("auth: ", tostring(redacted.auth))
            ngx.say("model: ", redacted.model)
            -- source must not be mutated
            ngx.say("source_auth: ", tostring(opts.auth ~= nil))
        }
    }
--- response_body
auth: nil
model: gpt-4
source_auth: true
