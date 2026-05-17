use t::APISIX 'no_plan';

repeat_each(1);
log_level('debug');
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_init_by_lua = <<_EOC_;
    local server = require("lib.server")
    server.token = function()
        local json = require("cjson")
        local headers = ngx.req.get_headers()
        ngx.log(ngx.INFO, ngx.var.request_uri, " receive headers: ", json.encode(headers))

        ngx.req.read_body()
        local data = ngx.req.get_body_data()
        ngx.log(ngx.INFO, ngx.var.request_uri, " payload: ", data)

        local payload = json.decode(data)

        if payload.code ~= "passed" then
            ngx.status = 400
            ngx.say([[{"code": 20051, "error_description": "Unauthorized"}]])
            return
        end

        ngx.log(ngx.INFO, ngx.var.request_uri, " payload: ", data)

        local resp_payload = [[
{
    "code": 0,
    "expires_in": 7200,
    "access_token": "85b8b7665c4c3bc5bd91d8e6cb6594b7",
    "token_type": "Bearer"
}
        ]]

        ngx.say(resp_payload)
    end

    server.userinfo = function()
        local json = require("cjson")
        local headers = ngx.req.get_headers()
        ngx.log(ngx.INFO, ngx.var.request_uri, " receive headers: ", json.encode(headers))

        local resp_payload = [[
{
  "code": 0,
  "data": {
    "avatar_big": "https://s3-imfile.feishucdn.com/static-resource/v1/v2_d8ffef5f-bb1b-4ba0-bf05-1487b4be",
    "avatar_middle": "https://s1-imfile.feishucdn.com/static-resource/v1/v2_d8ffef5f-bb1b-4ba0-bf05-1487b4beba4",
    "avatar_thumb": "https://s3-imfile.feishucdn.com/static-resource/v1/v2_d8ffef5f-bb1b-4ba0-bf05-1487b4beba",
    "avatar_url": "https://s3-imfile.feishucdn.com/static-resource/v1/v2_d8ffef5f-bb1b-4ba0-bf05-1487b4beba4g",
    "en_name": "jack",
    "name": "jack",
    "open_id": "ou_8fc70d9ea27111749a71eb",
    "tenant_key": "1224d18e8d",
    "union_id": "on_c249ec29c9d6"
  },
  "msg": "success"
}
        ]]

        ngx.say(resp_payload)
    end
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);


    if (!$block->request) {
        if (!$block->stream_request) {
            $block->set_value("request", "GET /t");
        }
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: enable feishu-auth plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins":{
                        "feishu-auth":{
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "my-secret",
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
                            "cookie_expires_in": 2,
                            "redirect_uri": "/echo"
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code <= 201 then
                ngx.status = 200
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: missing code
--- request
GET /hello
--- error_code: 302
--- response_headers
Location: /echo



=== TEST 3: invalid code
--- request
GET /hello?code=invalid
--- error_code: 401
--- response_body
{"message":"Invalid authorization code"}



=== TEST 4: valid code
--- request
GET /hello?code=passed
--- error_code: 200
--- response_body
hello world



=== TEST 5: X-Feishu-Code with invalid code
--- request
GET /hello
--- more_headers
X-Feishu-Code: invalid
--- error_code: 401
--- response_body
{"message":"Invalid authorization code"}



=== TEST 6: X-Feishu-Code header
--- request
GET /hello
--- more_headers
X-Feishu-Code: passed
--- error_code: 200
--- response_body
hello world



=== TEST 7: check cookie
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                query = {
                    code = "passed",
                },
                method = "GET",
            })
            assert(res, "request failed: " .. (err or "unknown error"))
            assert(res.status == 200, "unexpected res status: " .. res.status)

            local cookie = res.headers["Set-Cookie"]
            assert(cookie, "missing Set-Cookie header")

            -- request with cookie
            local res2, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Cookie"] = cookie,
                },
            })
            assert(res2, "request failed: " .. (err or "unknown error"))
            assert(res2.status == 200, "unexpected res2 status: " .. res2.status)

            --- request without cookie
            local res3, err = httpc:request_uri(uri, {
                method = "GET",
            })
            assert(res3, "request failed: " .. (err or "unknown error"))
            assert(res3.status == 302, "unexpected res3 status: " .. res3.status)

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 8: cookie expire
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                query = {
                    code = "passed",
                },
                method = "GET",
            })
            assert(res, "request failed: " .. (err or "unknown error"))
            assert(res.status == 200, "unexpected res status: " .. res.status)

            local cookie = res.headers["Set-Cookie"]
            assert(cookie, "missing Set-Cookie header")

            -- request with cookie
            local res2, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Cookie"] = cookie,
                },
            })
            assert(res2, "request failed: " .. (err or "unknown error"))
            assert(res2.status == 200, "unexpected res2 status: " .. res2.status)

            ngx.sleep(3)

            --- request without cookie
            local res3, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ["Cookie"] = cookie,
                },
            })
            assert(res3, "request failed: " .. (err or "unknown error"))
            assert(res3.status == 302, "unexpected res3 status: " .. res3.status)

            ngx.say("passed")
        }
    }
--- timeout: 5
--- request
GET /t
--- response_body
passed



=== TEST 9: specify header and query and redirect_uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins":{
                        "feishu-auth":{
                            "app_id": "123",
                            "app_secret": "456",
                            "secret": "my-secret",
                            "auth_redirect_uri": "https://example.com",
                            "access_token_url": "http://127.0.0.1:1980/token",
                            "userinfo_url": "http://127.0.0.1:1980/userinfo",
                            "code_query": "custom_code",
                            "code_header": "Custom-feishu-Code",
                            "redirect_uri": "/echo"
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code <= 201 then
                ngx.status = 200
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 10: specify query
--- pipelined_requests eval
["GET /hello?code=passed", "GET /hello?custom_code=passed"]
--- error_code eval
[302, 200]



=== TEST 11: specify header
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- more_headers eval
[
"X-Feishu-Code: passed",
"Custom-Feishu-Code: passed"
]
--- error_code eval
[302, 200]
