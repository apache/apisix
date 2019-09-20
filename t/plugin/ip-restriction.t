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

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")
            local conf = {
                whitelist = {
                    "10.255.254.0/24",
                    "192.168.0.0/16"
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("cjson").encode(conf))
        }
    }
--- request
GET /t
--- response_body
{"whitelist":["10.255.254.0\/24","192.168.0.0\/16"]}
--- no_error_log
[error]



=== TEST 2: wrong CIDR v4 format
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")
            local conf = {
                whitelist = {
                    "10.255.256.0/24",
                    "192.168.0.0/16"
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("cjson").encode(conf))
        }
    }
--- request
GET /t
--- response_body_like eval
qr/invalid cidr range: Invalid octet: 256/
--- no_error_log
[error]



=== TEST 3: wrong CIDR v4 format
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")
            local conf = {
                whitelist = {
                    "10.255.254.0/38",
                    "192.168.0.0/16"
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("cjson").encode(conf))
        }
    }
--- request
GET /t
--- response_body_like eval
qr@invalid cidr range: Invalid prefix: /38@
--- no_error_log
[error]



=== TEST 4: empty conf
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")

            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "oneOf" in docuement at pointer "#"
done
--- no_error_log
[error]



=== TEST 5: empty CIDRs
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")

            local ok, err = plugin.check_schema({blacklist={}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "type" in docuement at pointer "#/blacklist"
done
--- no_error_log
[error]



=== TEST 6: whitelist and blacklist mutual exclusive
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")
            local ok, err = plugin.check_schema({whitelist={"172.17.40.0/24"}, blacklist={"10.255.0.0/16"}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "oneOf" in docuement at pointer "#"
done
--- no_error_log
[error]



=== TEST 7: set whitelist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ip-restriction": {
                                 "whitelist": [
                                     "127.0.0.0/24",
                                     "113.74.26.106"
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
--- no_error_log
[error]



=== TEST 8: hit route and ip cidr in the whitelist
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 9: hit route and ip in the whitelist
--- http_config
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
--- more_headers
X-Forwarded-For: 113.74.26.106
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 10: hit route and ip not in the whitelist
--- http_config
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
--- more_headers
X-Forwarded-For: 114.114.114.114
--- request
GET /hello
--- error_code: 403
--- response_body
{"message":"Your IP address is not allowed"}
--- no_error_log
[error]



=== TEST 11: hit route and ipv6 not not in the whitelist
--- http_config
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
--- more_headers
X-Forwarded-For: 2001:db8::2
--- request
GET /hello
--- error_code: 403
--- response_body
{"message":"Your IP address is not allowed"}
--- no_error_log
[error]



=== TEST 12: set blacklist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ip-restriction": {
                                 "blacklist": [
                                     "127.0.0.0/24",
                                     "113.74.26.106"
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
--- no_error_log
[error]



=== TEST 13: hit route and ip cidr in the blacklist
--- request
GET /hello
--- error_code: 403
--- response_body
{"message":"Your IP address is not allowed"}
--- no_error_log
[error]



=== TEST 14: hit route and ip in the blacklist
--- http_config
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
--- more_headers
X-Forwarded-For: 113.74.26.106
--- request
GET /hello
--- error_code: 403
--- response_body
{"message":"Your IP address is not allowed"}
--- no_error_log
[error]



=== TEST 15: hit route and ip not not in the blacklist
--- http_config
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
--- more_headers
X-Forwarded-For: 114.114.114.114
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 16: hit route and ipv6 not not in the blacklist
--- http_config
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
--- more_headers
X-Forwarded-For: 2001:db8::2
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 17: remove ip-restriction
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
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
--- no_error_log
[error]



=== TEST 18: hit route
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
