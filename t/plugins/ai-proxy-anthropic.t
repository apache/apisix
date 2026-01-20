use Test::Nginx::Socket::Lua;
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_resource();

run_tests();

__DATA__

=== TEST 1: Sanity check, transform request to Anthropic format
--- config
    location /t {
        content_by_lua_block {
            local anthropic = require("apisix.plugins.ai-drivers.anthropic")
            local drv = anthropic.new({ name = "anthropic", conf = {} })
            local openai_body = {
                model = "claude-3-opus",
                messages = {
                    { role = "system", content = "sys prompt" },
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
{"messages":[{"content":"hello","role":"user"}],"model":"claude-3-opus","max_tokens":4096,"system":"sys prompt"}
--- no_error_log
[error]
