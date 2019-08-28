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
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_id = "a", client_secret = "b", discovery = "c"})
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



=== TEST 2: missing client_id
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "required" in docuement at pointer "#"
done
--- no_error_log
[error]
--- LAST



=== TEST 3: sanity
--- config
    location /t {
        content_by_lua_block {
            local oidc = require("resty.openidc")
            local opts = {
                client_id = "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                client_secret = "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                discovery = "https://samples.auth0.com/.well-known/openid-configuration",
                redirect_uri = "https://iresty.com",
                ssl_verify = "no",
                scope = "apisix"
            }
            local res, err = oidc.authenticate(opts)

            ngx.log(ngx.ERR, err)
            ngx.log(ngx.ERR, require("cjson").encode(res))
        }
    }
--- request
GET /t
--- error_code: 302
--- response_headers_like
Location: https:\/\/samples.auth0.com\/authorize\?scope=apisix&client_id=kbyuFDidLLm280LIwVFiazOqjO3ty8KH&state=[\d\w]+&nonce=[\d\w]+&redirect_uri=https%3A%2F%2Firesty.com&response_type=code
--- no_error_log
[error]
--- ONLY



=== TEST 4: wrong type of string
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
--- no_error_log
[error]
