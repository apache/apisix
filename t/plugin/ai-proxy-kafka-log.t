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
});

add_block_preprocessor(sub {
    my ($block) = @_;

    # The plugin no longer logs the payload; reproduce the observability the
    # tests rely on by logging each batch entry from a test-only hook.
    my $extra_init_by_lua = <<_EOC_;
    local bp_manager = require("apisix.utils.batch-processor-manager")
    local core = require("apisix.core")
    local function log_send_data(entry)
        local data = type(entry) == "table" and core.json.encode(entry) or entry
        core.log.info("send data to kafka: ", data)
    end
    local old_add = bp_manager.add_entry
    bp_manager.add_entry = function(self, conf, entry, max_pending_entries)
        local ok = old_add(self, conf, entry, max_pending_entries)
        if ok then
            log_send_data(entry)
        end
        return ok
    end
    local old_new = bp_manager.add_entry_to_new_processor
    bp_manager.add_entry_to_new_processor = function(self, conf, entry, ctx, func, max_pending_entries)
        local ok = old_new(self, conf, entry, ctx, func, max_pending_entries)
        if ok then
            log_send_data(entry)
        end
        return ok
    end
_EOC_

    if (!defined $block->extra_init_by_lua) {
        $block->set_value("extra_init_by_lua", $extra_init_by_lua);
    }
});

run_tests();

__DATA__

=== TEST 1: set route with logging summaries and payloads
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
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false,
                            "logging": {
                                "summaries": true,
                                "payloads": true
                            }
                        },
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1
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



=== TEST 2: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/chat-basic.json
--- error_log
send data to kafka:
llm_request
llm_summary
tool_count
cache_read_input_tokens
cache_creation_input_tokens
reasoning_tokens
You are a mathematician
gpt-35-turbo-instruct
llm_response_text



=== TEST 3: set route with logging summary but no payload
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
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false,
                            "logging": {
                                "summaries": true,
                                "payloads": false
                            }
                        },
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1
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



=== TEST 4: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/chat-basic.json
--- error_log
send data to kafka:
llm_summary
gpt-35-turbo-instruct
--- no_error_log
llm_request
llm_response_text



=== TEST 5: set route with no logging summary and payload - default behaviour
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
                                "model": "gpt-35-turbo-instruct",
                                "max_tokens": 512,
                                "temperature": 1.0
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false,
                            "logging": {
                                "summaries": false,
                                "payloads": false
                            }
                        },
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1
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



=== TEST 6: send request
--- request
POST /anything
{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }
--- more_headers
Authorization: Bearer token
X-AI-Fixture: openai/chat-basic.json
--- no_error_log
llm_request
llm_response_text
llm_summary



=== TEST 7: set route with stream = true (SSE) with ai-proxy-multi plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "instances": [
                                {
                                    "name": "self-hosted",
                                    "provider": "openai-compatible",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "custom-instruct",
                                        "max_tokens": 512,
                                        "temperature": 1.0,
                                        "stream": true
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:7737/v1/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false,
                            "logging": {
                                "summaries": true,
                                "payloads": true
                            }
                        },
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1
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



=== TEST 8: test is SSE works as expected
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

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

            local params = {
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                },
                path = "/anything",
                body = [[{
                    "stream": true,
                    "messages": [
                        { "role": "system", "content": "some content" }
                    ]
                }]],
            }

            local res, err = httpc:request(params)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local final_res = {}
            while true do
                local chunk, err = res.body_reader() -- will read chunk by chunk
                if err then
                    core.log.error("failed to read response chunk: ", err)
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end

            ngx.print(#final_res .. final_res[6])
        }
    }
--- response_body_eval
qr/6data: \[DONE\]\n\n/
--- error_log
send data to kafka:
llm_request
llm_summary
some content



=== TEST 9: set_logging records every observability field in llm_summary
--- config
    location /t {
        content_by_lua_block {
            local base = require("apisix.plugins.ai-proxy.base")
            local ctx = {
                var = {
                    request_llm_model = "m-req",
                    llm_model = "m",
                    llm_time_to_first_token = 12,
                    llm_prompt_tokens = 11,
                    llm_completion_tokens = 22,
                    llm_total_tokens = 33,
                    apisix_upstream_response_time = 1.5,
                    llm_stream = "true",
                    llm_tool_count = 2,
                    llm_has_tool_calls = "true",
                    llm_end_user_id = "user-1",
                    llm_cache_read_input_tokens = 5,
                    llm_cache_creation_input_tokens = 6,
                    llm_reasoning_tokens = 7,
                    llm_content_risk_level = "low",
                }
            }
            base.set_logging(ctx, true, false)
            local s = ctx.llm_summary
            local keys = {
                "request_model", "model", "duration", "prompt_tokens",
                "completion_tokens", "total_tokens", "upstream_response_time",
                "stream", "tool_count", "has_tool_calls", "end_user_id",
                "cache_read_input_tokens", "cache_creation_input_tokens",
                "reasoning_tokens", "content_risk_level",
            }
            for _, k in ipairs(keys) do
                ngx.say(k, "=", tostring(s[k]))
            end
        }
    }
--- response_body
request_model=m-req
model=m
duration=12
prompt_tokens=11
completion_tokens=22
total_tokens=33
upstream_response_time=1.5
stream=true
tool_count=2
has_tool_calls=true
end_user_id=user-1
cache_read_input_tokens=5
cache_creation_input_tokens=6
reasoning_tokens=7
content_risk_level=low
