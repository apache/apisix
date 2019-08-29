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



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_id = 123, client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "type" in docuement at pointer "#/client_id"
done
--- no_error_log
[error]



=== TEST 4: sanity
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



=== TEST 5: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "scope": "apisix"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": "no",
                                    "scope": "apisix"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
