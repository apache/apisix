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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->http_config) {
        my $http_config = <<_EOC_;
    server {
        listen 10421;

        location /api/public/ingestion {
            content_by_lua_block {
                ngx.req.read_body()
                local data = ngx.req.get_body_data()
                local headers = ngx.req.get_headers()
                ngx.log(ngx.WARN, "langfuse body: ", data)
                ngx.log(ngx.WARN, "langfuse auth: ", headers["Authorization"] or "none")
                ngx.say('{"successes":[],"errors":[]}')
            }
        }
    }
_EOC_
        $block->set_value("http_config", $http_config);
    }
});

run_tests;

__DATA__

=== TEST 1: schema validation - per-route schema accepts empty config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.langfuse")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 2: schema validation - per-route schema with include_metadata
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.langfuse")
            local ok, err = plugin.check_schema({
                include_metadata = false,
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 3: metadata schema validation - missing required fields
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.langfuse")
            local ok, err = plugin.check_schema({}, core.schema.TYPE_METADATA)
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body eval
qr/property "langfuse_public_key" is required/



=== TEST 4: metadata schema validation - valid config
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.langfuse")
            local ok, err = plugin.check_schema({
                langfuse_host = "http://127.0.0.1:10421",
                langfuse_public_key = "pk-lf-test",
                langfuse_secret_key = "sk-lf-test",
            }, core.schema.TYPE_METADATA)
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 5: set plugin_metadata for langfuse
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/langfuse',
                ngx.HTTP_PUT,
                [[{
                    "langfuse_host": "http://127.0.0.1:10421",
                    "langfuse_public_key": "pk-lf-test",
                    "langfuse_secret_key": "sk-lf-test"
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



=== TEST 6: add route with langfuse plugin - AI endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "langfuse": {},
                            "mocking": {
                                "content_type": "application/json",
                                "response_status": 200,
                                "response_example": "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion\",\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/v1/chat/completions"
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



=== TEST 7: AI request triggers langfuse batch with correct auth
--- request
POST /v1/chat/completions
{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
--- error_log
Batch Processor[langfuse logger] successfully processed the entries
langfuse body:
langfuse auth: Basic cGstbGYtdGVzdDpzay1sZi10ZXN0
--- wait: 3



=== TEST 8: non-AI endpoint with detect_ai_requests=true (default) should not trigger
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "langfuse": {}
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 9: access non-AI endpoint - no langfuse trace
--- request
GET /hello
--- response_body
hello world
--- no_error_log
Batch Processor[langfuse logger]
--- wait: 1



=== TEST 10: set plugin_metadata with detect_ai_requests=false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/langfuse',
                ngx.HTTP_PUT,
                [[{
                    "langfuse_host": "http://127.0.0.1:10421",
                    "langfuse_public_key": "pk-lf-test",
                    "langfuse_secret_key": "sk-lf-test",
                    "detect_ai_requests": false
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



=== TEST 11: add route for non-AI endpoint with detect_ai_requests=false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "langfuse": {}
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
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



=== TEST 12: non-AI endpoint with detect_ai_requests=false should trigger
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
Batch Processor[langfuse logger] successfully processed the entries
--- wait: 3



=== TEST 13: restore plugin_metadata with detect_ai_requests=true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/langfuse',
                ngx.HTTP_PUT,
                [[{
                    "langfuse_host": "http://127.0.0.1:10421",
                    "langfuse_public_key": "pk-lf-test",
                    "langfuse_secret_key": "sk-lf-test",
                    "detect_ai_requests": true
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



=== TEST 14: request with traceparent returns traceparent in response
--- request
POST /v1/chat/completions
{"model":"gpt-4","messages":[{"role":"user","content":"hello"}]}
--- more_headers
Content-Type: application/json
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
--- response_headers_like
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-.+-01
--- error_log
Batch Processor[langfuse logger] successfully processed the entries
--- wait: 3



=== TEST 15: request without traceparent gets auto-generated traceparent
--- request
POST /v1/chat/completions
{"model":"gpt-4","messages":[{"role":"user","content":"hello"}]}
--- more_headers
Content-Type: application/json
--- response_headers_like
traceparent: 00-.+-.+-01
--- error_log
Batch Processor[langfuse logger] successfully processed the entries
--- wait: 3



=== TEST 16: embedding endpoint detection
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/4',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "langfuse": {},
                            "mocking": {
                                "content_type": "application/json",
                                "response_status": 200,
                                "response_example": "{\"object\":\"list\",\"model\":\"text-embedding-ada-002\",\"data\":[{\"object\":\"embedding\",\"embedding\":[0.1,0.2,0.3],\"index\":0}],\"usage\":{\"prompt_tokens\":5,\"total_tokens\":5}}"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/v1/embeddings"
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



=== TEST 17: embedding request triggers langfuse
--- request
POST /v1/embeddings
{"model":"text-embedding-ada-002","input":"hello world"}
--- more_headers
Content-Type: application/json
--- error_log
Batch Processor[langfuse logger] successfully processed the entries
--- wait: 3



=== TEST 18: error response setup
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/5',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "langfuse": {},
                            "mocking": {
                                "content_type": "application/json",
                                "response_status": 429,
                                "response_example": "{\"error\":{\"message\":\"Rate limit exceeded\",\"type\":\"rate_limit_error\"}}"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/v1/completions"
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



=== TEST 19: error response triggers langfuse
--- request
POST /v1/completions
{"model":"gpt-4","prompt":"hello"}
--- more_headers
Content-Type: application/json
--- error_code: 429
--- error_log
Batch Processor[langfuse logger] successfully processed the entries
--- wait: 3



=== TEST 20: X-Langfuse-Tags header processing
--- request
POST /v1/chat/completions
{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
X-Langfuse-Tags: prod, gateway, test-tag
--- error_log
Batch Processor[langfuse logger] successfully processed the entries
langfuse body:
--- wait: 3



=== TEST 21: X-Langfuse-Metadata header processing
--- request
POST /v1/chat/completions
{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
X-Langfuse-Metadata: {"environment":"staging","team":"backend"}
--- error_log
Batch Processor[langfuse logger] successfully processed the entries
langfuse body:
--- wait: 3



=== TEST 22: without plugin_metadata, langfuse should skip
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/plugin_metadata/langfuse', ngx.HTTP_DELETE)

            local code, body = t('/apisix/admin/routes/6',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "langfuse": {},
                            "mocking": {
                                "content_type": "application/json",
                                "response_status": 200,
                                "response_example": "{\"id\":\"chatcmpl-123\",\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2,\"total_tokens\":7}}"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/v1/chat/no-metadata"
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



=== TEST 23: request without plugin_metadata skips langfuse
--- request
POST /v1/chat/no-metadata
{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
--- error_log
langfuse: plugin_metadata is required, skipping
--- no_error_log
Batch Processor[langfuse logger]
--- wait: 1



=== TEST 24: cleanup
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for i = 1, 6 do
                t('/apisix/admin/routes/' .. i, ngx.HTTP_DELETE)
            end
            t('/apisix/admin/plugin_metadata/langfuse', ngx.HTTP_DELETE)
            ngx.say("done")
        }
    }
--- response_body
done
