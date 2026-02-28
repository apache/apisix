use t::APISIX 'no_plan';

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();

my $resp_file = 't/assets/openai-compatible-api-response.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $resp = do { local $/; <$fh> };
close($fh);

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 6724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    if not body.messages or #body.messages < 1 then
                        ngx.status = 400
                        ngx.say([[{ "error": "bad request"}]] )
                        return
                    end

                    -- Check if it is a Claude to OpenAI conversion
                    local is_claude = ngx.req.get_headers()["X-Claude-Test"]
                    if is_claude == "system" then
                        if body.messages[1].role == "system" and body.messages[1].content == "You are a bot" then
                            ngx.status = 200
                            ngx.say([[$resp]])
                            return
                        else
                            ngx.status = 500
                            ngx.say("conversion failed")
                            return
                        end
                    elseif is_claude == "system_array" then
                        if body.messages[1].role == "system" and body.messages[1].content == "Text1Text2" then
                            ngx.status = 200
                            ngx.say([[$resp]])
                            return
                        else
                            ngx.status = 500
                            ngx.say("conversion failed")
                            return
                        end
                    elseif is_claude == "no_system" then
                        if body.messages[1].role == "user" and body.messages[1].content == "Hello!" then
                            ngx.status = 200
                            ngx.say([[$resp]])
                            return
                        else
                            ngx.status = 500
                            ngx.say("conversion failed")
                            return
                        end
                    elseif is_claude == "upstream_error" then
                        ngx.status = 401
                        ngx.say([[{"error": {"message": "Unauthorized"}}]])
                        return
                    elseif is_claude == "missing_usage" then
                        ngx.status = 200
                        local no_usage_resp = [[{"id":"chatcmpl-123","object":"chat.completion","created":1694268190,"model":"gpt-3.5-turbo-0613","choices":[{"index":0,"message":{"role":"assistant","content":"Hello without usage"},"finish_reason":"stop"}]}]]
                        ngx.say(no_usage_resp)
                        return
                    elseif is_claude == "streaming" then
                        ngx.req.read_body()
                        ngx.header.content_type = "text/event-stream"
                        ngx.header.cache_control = "no-cache"
                        ngx.header.connection = "keep-alive"
                        
                        ngx.say('data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-3.5-turbo-0613","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}')
                        ngx.say('')
                        ngx.flush(true)
                        ngx.sleep(0.1)
                        
                        ngx.say('data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-3.5-turbo-0613","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}')
                        ngx.say('')
                        ngx.flush(true)
                        ngx.sleep(0.1)
                        
                        ngx.say('data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-3.5-turbo-0613","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}')
                        ngx.say('')
                        ngx.flush(true)
                        ngx.sleep(0.1)

                        ngx.say('data: [DONE]')
                        ngx.say('')
                        ngx.flush(true)
                        return
                    elseif is_claude == "streaming_diff_reason" then
                        ngx.req.read_body()
                        ngx.header.content_type = "text/event-stream"
                        ngx.header.cache_control = "no-cache"
                        ngx.header.connection = "keep-alive"
                        
                        ngx.say('data: {"id":"chatcmpl-124","object":"chat.completion.chunk","created":1694268190,"model":"gpt-3.5-turbo-0613","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}')
                        ngx.say('')
                        ngx.flush(true)
                        ngx.sleep(0.1)
                        
                        ngx.say('data: {"id":"chatcmpl-124","object":"chat.completion.chunk","created":1694268190,"model":"gpt-3.5-turbo-0613","choices":[{"index":0,"delta":{"content":"Hello again"},"finish_reason":null}]}')
                        ngx.say('')
                        ngx.flush(true)
                        ngx.sleep(0.1)
                        
                        -- Finish reason is length, not stop
                        ngx.say('data: {"id":"chatcmpl-124","object":"chat.completion.chunk","created":1694268190,"model":"gpt-3.5-turbo-0613","choices":[{"index":0,"delta":{},"finish_reason":"length"}]}')
                        ngx.say('')
                        ngx.flush(true)
                        ngx.sleep(0.1)

                        ngx.say('data: [DONE]')
                        ngx.say('')
                        ngx.flush(true)
                        return
                    end

                    ngx.status = 200
                    ngx.say([[$resp]])
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: setup route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/v1/messages",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:6724/v1/chat/completions"
                            }
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



=== TEST 2: Basic Chat Request (Claude -> OpenAI -> Claude)
--- request
POST /v1/messages
{
  "model": "claude-3-5-sonnet",
  "max_tokens": 1024,
  "system": "You are a bot",
  "messages": [
    {
      "role": "user",
      "content": "Hello!"
    }
  ]
}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
X-Claude-Test: system
--- error_code: 200
--- response_body_like eval
qr/"role":"assistant"/



=== TEST 3: Basic Chat Request with Complex System Prompt (Claude -> OpenAI -> Claude)
--- request
POST /v1/messages
{
  "model": "claude-3-5-sonnet",
  "max_tokens": 1024,
  "system": [
    {
      "type": "text",
      "text": "Text1"
    },
    {
      "type": "text",
      "text": "Text2"
    }
  ],
  "messages": [
    {
      "role": "user",
      "content": "Hello!"
    }
  ]
}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
X-Claude-Test: system_array
--- error_code: 200
--- response_body_like eval
qr/"role":"assistant"/



=== TEST 4: SSE Streaming Test (Claude -> OpenAI -> Claude)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "127.0.0.1",
                port = 9080,
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
                    ["X-Claude-Test"] = "streaming",
                },
                path = "/v1/messages",
                body = [[{
                    "model": "claude-3-5-sonnet",
                    "max_tokens": 1024,
                    "messages": [
                        { "role": "user", "content": "hello" }
                    ],
                    "stream": true
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
                local chunk, err = res.body_reader()
                if err then
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end

            ngx.print(table.concat(final_res, ""))
        }
    }
--- response_body_like eval
qr/event: message_start/



=== TEST 5: Abnormal Test - Missing messages
--- request
POST /v1/messages
{
  "model": "claude-3-5-sonnet",
  "max_tokens": 1024,
  "system": "You are a bot"
}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
--- error_code: 400
--- response_body_like eval
qr/request format doesn't match/



=== TEST 6: Basic Chat Request (No System Prompt)
--- request
POST /v1/messages
{
  "model": "claude-3-5-sonnet",
  "max_tokens": 1024,
  "messages": [
    {
      "role": "user",
      "content": "Hello!"
    }
  ]
}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
X-Claude-Test: no_system
--- error_code: 200
--- response_body_like eval
qr/"role":"assistant"/



=== TEST 7: Abnormal Test - Empty messages array
--- request
POST /v1/messages
{
  "model": "claude-3-5-sonnet",
  "max_tokens": 1024,
  "messages": []
}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
--- error_code: 400
--- response_body_like eval
qr/request format doesn't match/



=== TEST 8: Upstream Error Passed Through (e.g., 401 Unauthorized)
--- request
POST /v1/messages
{
  "model": "claude-3-5-sonnet",
  "max_tokens": 1024,
  "messages": [
    {
      "role": "user",
      "content": "Hello!"
    }
  ]
}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
X-Claude-Test: upstream_error
--- error_code: 401
--- response_body_like eval
qr/Unauthorized/



=== TEST 9: Response missing usage data
--- request
POST /v1/messages
{
  "model": "claude-3-5-sonnet",
  "max_tokens": 1024,
  "messages": [
    {
      "role": "user",
      "content": "Hello!"
    }
  ]
}
--- more_headers
Authorization: Bearer token
Content-Type: application/json
X-Claude-Test: missing_usage
--- error_code: 200
--- response_body_like eval
qr/"Hello without usage"/



=== TEST 10: SSE Streaming with different stop reason (length)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "127.0.0.1",
                port = 9080,
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
                    ["X-Claude-Test"] = "streaming_diff_reason",
                },
                path = "/v1/messages",
                body = [[{
                    "model": "claude-3-5-sonnet",
                    "max_tokens": 1024,
                    "messages": [
                        { "role": "user", "content": "hello" }
                    ],
                    "stream": true
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
                local chunk, err = res.body_reader()
                if err then
                    break
                end
                if not chunk then
                    break
                end
                core.table.insert_tail(final_res, chunk)
            end

            ngx.print(table.concat(final_res, ""))
        }
    }
--- response_body_like eval
qr/"stop_reason":"length"/
