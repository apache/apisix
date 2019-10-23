BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
log_level('info');
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.redirect")
            local ok, err = plugin.check_schema({
                ret_code = 302,
                uri = '/foo',
            })
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



=== TEST 2: default ret_code
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.redirect")
            local ok, err = plugin.check_schema({
                -- ret_code = 302,
                uri = '/foo',
            })
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



=== TEST 3: add plugin with new uri: /test/add
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "/test/add",
                            "ret_code": 301
                        }
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



=== TEST 4: redirect
--- request
GET /hello
--- response_headers
Location: /test/add
--- error_code: 301
--- no_error_log
[error]



=== TEST 5: add plugin with new uri: $uri/test/add
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "$uri/test/add",
                            "ret_code": 301
                        }
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



=== TEST 6: redirect
--- request
GET /hello
--- response_headers
Location: /hello/test/add
--- error_code: 301
--- no_error_log
[error]



=== TEST 7: add plugin with new uri: $uri/test/a${arg_name}c
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "$uri/test/a${arg_name}c",
                            "ret_code": 302
                        }
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



=== TEST 8: redirect
--- request
GET /hello?name=json
--- response_headers
Location: /hello/test/ajsonc
--- error_code: 302
--- no_error_log
[error]



=== TEST 9: add plugin with new uri: /foo$$uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "/foo$$uri",
                            "ret_code": 302
                        }
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



=== TEST 10: redirect
--- request
GET /hello?name=json
--- response_headers
Location: /foo$/hello
--- error_code: 302
--- no_error_log
[error]



=== TEST 11: add plugin with new uri: \\$uri/foo$uri\\$uri/bar
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "redirect": {
                            "uri": "\\$uri/foo$uri\\$uri/bar",
                            "ret_code": 301
                        }
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



=== TEST 12: redirect
--- request
GET /hello
--- response_headers
Location: \$uri/foo/hello\$uri/bar
--- error_code: 301
--- no_error_log
[error]
