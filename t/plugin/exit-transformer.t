use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_yaml_config = <<_EOC_;
plugins:
    - exit-transformer
    - key-auth
    - limit-count
_EOC_

    if (!$block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();


__DATA__

=== TEST 1: failed schema check with invalid lua code
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.exit-transformer")
            local ok, err = plugin.check_schema({
                functions = {
                    "return (function(code, body, header) if code == then return 405 end return code, body, header end)(...)",
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body eval
qr/unexpected symbol/



=== TEST 2: set plugin to convert 404 to 405
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "exit-transformer": {
                            "functions": ["return (function(code, body, header) if code == 404 then return 405 end return code, body, header end)(...)"]
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
--- request
GET /t
--- response_body
passed



=== TEST 3: hit route
--- error_code: 405
--- request
GET /hello



=== TEST 4: set plugin to convert 401 to 402 for auth plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "exit-transformer": {
                            "functions": ["return (function(code, body, header) if code == 401 then return 402, body, header end return code, body, header end)(...)"]
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
--- request
GET /t
--- response_body
passed



=== TEST 5: add consumer with username and plugins
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



=== TEST 6: add key auth plugin using admin api
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



=== TEST 7: valid consumer
--- request
GET /hello
--- more_headers
apikey: auth-one
--- response_body
hello world



=== TEST 8: invalid consumer
--- request
GET /hello
--- more_headers
apikey: 123
--- error_code: 402
--- response_body
{"message":"Invalid API key in request"}



=== TEST 9: set plugin to convert 503 to 502 for auth plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "exit-transformer": {
                            "functions": ["return (function(code, body, header) if code == 503 then return 502, \"Modified 503 to 502\", header end return code, body, header end)(...)"]
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
--- request
GET /t
--- response_body
passed



=== TEST 10: set limit count plugin on route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
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
--- response_body
passed



=== TEST 11: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 502, 502]
--- response_body eval
["hello world\n", "hello world\n", "Modified 503 to 502", "Modified 503 to 502"]



=== TEST 12: set plugin with invalid code inside function
# attempt to call code as a function)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "exit-transformer": {
                            "functions": ["return (function(code, body, header) if code == 404 then return code() end return code, body, header end)(...)"]
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
--- request
GET /t
--- response_body
passed



=== TEST 13: hit a non existent route and expect 404 status code
# exit transformer will catch the invalid code inside func and print an error log gracefully
--- error_code: 404
--- request
GET /nohello
--- error_log
attempt to call local 'code' (a number value)



=== TEST 14: set plugin with judgement based on request content-type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "exit-transformer": {
                            "functions": [
                                "return
                                    (function(code, body, header)
                                        local core = require(\"apisix.core\")
                                        local ct = core.request.headers()[\"Content-Type\"]

                                        core.log.warn(\"exit transformer running outside if check\")

                                        if ct == \"application/json\" and code == 404 then
                                            core.log.warn(\"exit transformer running inside if check\")
                                            return 405
                                        end
                                        return code, body, header
                                    end)
                                (...)"
                            ]
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
--- request
GET /t
--- response_body
passed



=== TEST 15: hit a request with non `application/json` content-type
--- request
GET /nohello
--- more_headers
Content-Type: text/html
--- error_code: 404
--- error_log
exit transformer running outside if check



=== TEST 16: hit a request with `application/json` content-type
--- request
GET /nohello
--- more_headers
Content-Type: application/json
--- error_code: 405
--- error_log
exit transformer running outside if check
exit transformer running inside if check



=== TEST 17: treat body as a table
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {},
                        "exit-transformer": {
                            "functions": [
                                "return
                                    (function(code, body, header)
                                        if code == 401 and body.message == \"Missing API key found in request\" then
                                            return 400, {message = \"authentication Failed\"}, {[\"content-type\"] = \"application/json\"}
                                        end
                                        return code, body, header
                                    end)
                                (...)"
                            ]
                        }
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



=== TEST 18: valid consumer
--- request
GET /hello
--- more_headers
apikey: auth-one
--- response_headers
content-type: text/plain
--- response_body
hello world



=== TEST 19: missing api key
--- request
GET /hello
--- error_code: 400
--- response_headers
content-type: application/json
--- response_body
{"message":"authentication Failed"}



=== TEST 20: invalid consumer
--- request
GET /hello
--- more_headers
apikey: 123
--- error_code: 401
--- response_headers
content-type: text/plain
--- response_body
{"message":"Invalid API key in request"}
