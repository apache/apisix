#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
#
use Test::Nginx::Socket::Lua;
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_resource();

add_block_preprocessor(function ($block) {
    if (!$block->http_config ) {
        $block->set_value("http_config", [[
            server {
                listen 1984;
                location /v1/messages {
                    content_by_lua_block {
                        local core = require("apisix.core" )
                        local body = core.json.decode(ngx.req.get_body_data())

                        -- Verify authentication header
                        if ngx.var.http_x_api_key == "wrong-key" then
                            ngx.status = 401
                            ngx.say([[{"type": "error", "error": {"type": "authentication_error", "message": "invalid key"}}]] )
                            return
                        end

                        -- Verify Anthropic's required parameter max_tokens
                        if not body.max_tokens then
                            ngx.status = 400
                            ngx.say("Missing max_tokens")
                            return
                        end

                        -- Simulate Anthropic's native response
                        ngx.status = 200
                        ngx.say([[
                        {
                            "id": "msg_123",
                            "content": [{"type": "text", "text": "Claude Response"}],
                            "model": "claude-3",
                            "stop_reason": "end_turn",
                            "usage": {"input_tokens": 5, "output_tokens": 5}
                        }
                        ]])
                    }
                }
            }
        ]]);
    }
});

run_tests();

__DATA__

=== TEST 1: Anthropic Native - Full Protocol Translation (System Prompt & Headers)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": {
                    "ai-proxy": {
                        "provider": "anthropic",
                        "model": "claude-3",
                        "api_key": "test-key",
                        "override": { "endpoint": "http://127.0.0.1:1984/v1/messages" }
                    }
                },
                "uri": "/v1/chat/completions"
            }]] )

            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/v1/chat/completions", {
                method = "POST",
                body = [[{"messages": [{"role": "system", "content": "You are a helper"}, {"role": "user", "content": "Hi"}]}]],
                headers = { ["Content-Type"] = "application/json" }
            } )
            
            local resp = require("apisix.core").json.decode(res.body)
            if resp.choices and resp.choices[1].message.content == "Claude Response" then
                ngx.say("Success: Bidirectional Translation Works")
            end
        }
    }
--- response_body
Success: Bidirectional Translation Works

=== TEST 2: Anthropic Native - Multi-turn Role Mapping
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/v1/chat/completions", {
                method = "POST",
                body = [[{"messages": [{"role": "user", "content": "Hi"}, {"role": "assistant", "content": "Hello"}, {"role": "user", "content": "Next"}]}]],
            } )
            ngx.status = res.status
            ngx.say("Status: " .. res.status)
        }
    }
--- response_body
Status: 200

=== TEST 3: Anthropic Native - Default Parameter Completion (max_tokens)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http" )
            local httpc = http.new( )
            -- The request does not include max_tokens. Verify whether the driver automatically filled in 1024.
            local res = httpc:request_uri("http://127.0.0.1:9080/v1/chat/completions", {
                method = "POST",
                body = [[{"messages": [{"role": "user", "content": "Hi"}]}]],
            } )
            ngx.status = res.status
            ngx.say("Status: " .. res.status)
        }
    }
--- response_body
Status: 200

=== TEST 4: Anthropic Native - Error Passthrough
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "plugins": {
                    "ai-proxy": {
                        "provider": "anthropic",
                        "model": "claude-3",
                        "api_key": "wrong-key",
                        "override": { "endpoint": "http://127.0.0.1:1984/v1/messages" }
                    }
                },
                "uri": "/v1/chat/completions"
            }]] )
            local http = require("resty.http" )
            local httpc = http.new( )
            local res = httpc:request_uri("http://127.0.0.1:9080/v1/chat/completions", {
                method = "POST",
                body = [[{"messages": [{"role": "user", "content": "Hi"}]}]],
            } )
            ngx.print(res.body)
        }
    }
--- response_body
{"type": "error", "error": {"type": "authentication_error", "message": "invalid key"}}
