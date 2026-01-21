use Test::Nginx::Socket::Lua;
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_resource();

run_tests();

__DATA__

=== TEST 1: Transform request roles (user/assistant)
--- config
    location /t {
        content_by_lua_block {
            local anthropic = require("apisix.plugins.ai-drivers.anthropic")
            local drv = anthropic.new({ name = "anthropic", conf = {} })
            local openai_body = {
                model = "claude-3",
                messages = {
                    { role = "user", content = "hello" },
                    { role = "assistant", content = "hi there" },
                    { role = "user", content = "how are you?" }
                }
            }
            local transformed = drv:transform_request(openai_body)
            local json = require("apisix.core.json")
            ngx.say(json.encode(transformed))
        }
    }
--- request
GET /t
--- response_body
{"messages":[{"content":"hello","role":"user"},{"content":"hi there","role":"assistant"},{"content":"how are you?","role":"user"}],"model":"claude-3","max_tokens":4096}
--- no_error_log
[error]

=== TEST 2: Extract system prompt correctly
--- config
    location /t {
        content_by_lua_block {
            local anthropic = require("apisix.plugins.ai-drivers.anthropic")
            local drv = anthropic.new({ name = "anthropic", conf = {} })
            local openai_body = {
                model = "claude-3",
                messages = {
                    { role = "system", content = "you are a helpful assistant" },
                    { role = "user", content = "hello" }
                }
            }
            local transformed = drv:transform_request(openai_body)
            local json = require("apisix.core.json")
            ngx.say(json.encode(transformed))
        }
    }
--- request
GET /t
--- response_body
{"messages":[{"content":"hello","role":"user"}],"model":"claude-3","max_tokens":4096,"system":"you are a helpful assistant"}
--- no_error_log
[error]

=== TEST 3: Transform Anthropic response to OpenAI format
--- config
    location /t {
        content_by_lua_block {
            local anthropic = require("apisix.plugins.ai-drivers.anthropic")
            local drv = anthropic.new({ name = "anthropic", conf = {} })
            local anthropic_res = {
                body = [[{
                    "id": "msg_123",
                    "model": "claude-3",
                    "content": [{"text": "Hello! I am Claude."}],
                    "stop_reason": "end_turn",
                    "usage": {"input_tokens": 10, "output_tokens": 20}
                }]]
            }
            local transformed = drv:transform_response(anthropic_res)
            local json = require("apisix.core.json")
            ngx.say(transformed.choices[1].message.content)
            ngx.say(transformed.usage.total_tokens)
        }
    }
--- request
GET /t
--- response_body
Hello! I am Claude.
30
--- no_error_log
[error]
