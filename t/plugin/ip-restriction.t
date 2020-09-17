#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
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
qr/invalid ip address: 10.255.256.0\/24/
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
qr@invalid ip address: 10.255.254.0/38@
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
value should match only one schema, but matches none
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
value should match only one schema, but matches none
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
value should match only one schema, but matches none
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



=== TEST 11: hit route and IPv6 not not in the whitelist
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



=== TEST 16: hit route and IPv6 not not in the blacklist
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



=== TEST 19: sanity(IPv6)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")
            local conf = {
                whitelist = {
                    "::1",
                    "fe80::/32",
                    "2001:DB8:0:23:8:800:200C:417A",
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say("pass")
        }
    }
--- request
GET /t
--- response_body
pass
--- no_error_log
[error]



=== TEST 20: set blacklist
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
                                "::1",
                                "fe80::/32"
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



=== TEST 21: hit route
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 22: hit route and IPv6 in the blacklist
--- http_config
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
--- more_headers
X-Forwarded-For: ::1
--- request
GET /hello
--- error_code: 403
--- response_body
{"message":"Your IP address is not allowed"}
--- no_error_log
[error]



=== TEST 23: hit route and IPv6 in the blacklist
--- http_config
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
--- more_headers
X-Forwarded-For: fe80::1:1
--- request
GET /hello
--- error_code: 403
--- response_body
{"message":"Your IP address is not allowed"}
--- no_error_log
[error]



=== TEST 24: wrong IPv6 format
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")
            for i, ip in ipairs({"::1/129", "::ffgg"}) do
                local conf = {
                    whitelist = {
                        ip
                    }
                }
                local ok, err = plugin.check_schema(conf)
                if not ok then
                    ngx.say(err)
                end
            end
        }
    }
--- request
GET /t
--- response_body
invalid ip address: ::1/129
value should match only one schema, but matches none
--- no_error_log
[error]
