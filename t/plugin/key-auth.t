use t::APISix 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.key-auth")
            local ok, err = plugin.check_schema({key = 'test-key'})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.key-auth")
            local ok, err = plugin.check_schema({key = 123})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "type" in docuement at pointer "#/key"
done
--- no_error_log
[error]



=== TEST 3: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                 ngx.HTTP_PUT,
                 [[{
                    "username": "jack",
                    "plugins": {
                            "key-auth": {
                                "key": "auth-one"
                            }
                        }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack",
                            "plugins": {
                                "key-auth": {
                                    "key": "auth-one"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: add key auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "key-auth": {}
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: invalid consumer
--- request
GET /hello
--- more_headers
apikey: 123
--- error_code: 401
--- response_body
{"message":"Invalid API key in request"}
--- no_error_log
[error]



=== TEST 6: not found apikey header
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing API key found in request"}
--- no_error_log
[error]



=== TEST 7: valid consumer
--- request
GET /hello
--- more_headers
apikey: auth-one
--- response_body
hello world
--- no_error_log
[error]
